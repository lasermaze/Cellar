# Phase 42: Unify Agent Loop with Single Model Catalog and Typed Tool Boundary - Context

**Gathered:** 2026-05-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Three structural refactors to the agent infrastructure, all delivered together because they touch the same surface (`AgentLoop`, `AgentLoopProvider`, `AgentTools`, `AIService`):

1. **Unify agent loop**: collapse `AgentLoop` + `AgentLoopProvider` into one path. Replace the protocol-with-three-implementations pattern (623 lines in `AgentLoopProvider.swift`) with a single concrete `AgentProvider` struct that holds its own message state and delegates wire-protocol differences to per-provider adapters.

2. **Single model catalog**: one source of truth for model identity, provider routing, pricing, and max-output limits. Today these are duplicated across `AgentLoopProvider.swift` (per-provider `modelPricing` dicts) and `AIService.swift` (`fallbackModels: [ModelOption]` plus four `if requested == "kimi"`-style routing branches).

3. **Typed tool boundary**: replace `switch toolName: String` (twice, at `AgentTools.swift:656` and `:692`) with a Swift enum. Tool implementations in `Tools/*.swift` keep their `JSONValue → String` signatures (Phase 31 / v1.3 carry-forward).

**Out of scope (other phases):**
- Extracting system prompt / engine rules / allowlists to `Resources/` — Phase 43.
- Achieving tool-use parity across providers — Phase 43.
- Splitting `AgentTools` into session/runtime actors — Phase 45.
- Memory layer collapse into `KnowledgeStore` — Phase 44.

</domain>

<decisions>
## Implementation Decisions

### Model catalog shape

- **Storage**: static Swift table in `Sources/cellar/Core/ModelCatalog.swift`. Compile-time checked, no I/O, ships in binary. (Bundled JSON deferred — fits Phase 43's "policy data to versioned resources" theme better, but this catalog isn't policy data.)
- **Fields (lean)**: each entry declares only `id`, `provider`, `pricing` (input/output per token), `maxOutputTokens`. No `displayLabel`, no `supportsToolUse` flag, no `contextWindow`, no `recommendedBudget`. Tool-use exclusions stay implicit by what's *in* the catalog (e.g. `deepseek-reasoner` is not a catalog entry — Phase 18 carry-forward).
- **Lookup behavior**: strict resolution at session boundary. If `CellarConfig.aiModel` references an unknown ID, the resolver throws / surfaces a clear error to the UI. Inside the loop the resolved descriptor is non-optional. Today's silent `?? (0.0, 0.0)` pricing fallback is removed.
- **Provider routing collapse**: catalog entry carries `provider: AIProvider` (enum). The four scattered `if requested == "kimi" || requested == "moonshot"` branches in `AIService.swift` (lines 227, 311, 439, 662) collapse to one catalog lookup.
- **Live `/v1/models` fetching**: kept, but feeds the catalog. The web UI dropdown shows `catalog ∩ live_available_for_configured_providers`. Static catalog remains authoritative for pricing/limits; live fetch is purely an availability check.

### Loop + Provider unification

- **One concrete provider type, not a protocol**: `AgentProvider` is a single concrete struct. AgentLoop holds `var provider: AgentProvider` — no protocol dispatch from the loop's point of view.
- **Wire-protocol differences live in adapters**: Anthropic Messages API and OpenAI-compatible Chat Completions are genuinely different and cannot be merged at the JSON level. The `AgentProvider` composes a `transport` closure with a per-provider adapter that handles encoding/decoding and quirks.
- **Three adapters, not two**: `AnthropicAdapter`, `DeepseekAdapter`, `KimiAdapter`. Each owns its quirks explicitly (Kimi's `partial`/safety flags, Deepseek's reasoning-content handling, base URL, auth header style). Sharing across Deepseek/Kimi happens via small private helpers if duplication becomes painful — but the adapters themselves stay distinct.
- **Provider owns conversation message state (status quo)**: keeps `mutating func appendUserMessage / appendAssistantResponse / appendToolResults`. Per-provider message types stay encapsulated inside the adapter — `AgentLoop` never sees raw API messages. Preserves Phase 18 decision ("AgentLoopProvider protocol owns message array").
- **File layout**: `Core/AgentProvider.swift` (concrete struct + adapter protocol/types), `Core/Providers/AnthropicAdapter.swift`, `Core/Providers/DeepseekAdapter.swift`, `Core/Providers/KimiAdapter.swift`. Replaces the 623-line `AgentLoopProvider.swift`.

### Typed tool boundary

- **Depth: string-backed enum (names only)**: `enum AgentToolName: String, CaseIterable { case inspectGame = "inspect_game", ... }`. Replaces both `switch toolName: String` blocks. Eliminates the typo class of bug. Tool implementations in `Tools/*.swift` keep `JSONValue → String` signatures unchanged (v1.3 carry-forward).
- **Tool definitions derive from the enum**: per-case static metadata (description, JSON schema literal, optional pending-action description) lives on the enum (e.g. via `extension AgentToolName { var definition: ToolDefinition { ... } }` or a `[Case: Metadata]` table). Hand-authored `toolDefinitions: [ToolDefinition]` array goes away; dispatch and schema can no longer drift. Schemas stay in Swift literals — moving them to `Resources/` is Phase 43 territory.
- **Single dispatcher**: pending-action tracking unifies under the same enum. The parallel `switch toolName: String` at `AgentTools.swift:692` collapses into a property/method on `AgentToolName` (e.g. `func pendingActionDescription(for input: JSONValue) -> String?`) called from one site. One source of truth for what each tool *is*.

### Claude's Discretion

- **Budget**: stays a runtime / `CellarConfig` concern. Catalog does not carry per-model budget defaults. (Phase wording groups "model/pricing/budget" but in practice budget is policy, pricing is data — keeping them separate.)
- **Migration approach**: staged within the phase (model catalog → adapters → typed dispatch, atomic commits each), with the old `AgentLoopProvider` protocol deleted at the end of the phase. Big-bang single PR avoided to preserve bisect-ability.
- **Type/file naming**: final names (`AgentProvider` vs `Provider`, `AnthropicAdapter` vs `AnthropicTransport`, etc.) decided during planning.
- **Adapter sharing**: whether Deepseek and Kimi adapters share an internal `OpenAICompatHelpers.swift` (private) is decided at implementation time — only if the duplication becomes loud.
- **`AIService.fallbackModels` fate**: with strict catalog resolution, this list becomes either a thin web-layer view over the catalog or is removed entirely. Decision deferred to planning — not load-bearing for the loop.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `OSAllocatedUnfairLock` pattern from `AgentControl` (Phase 31): the canonical Swift-6-safe lock for any mutable state in the new `AgentProvider`.
- `JSONValue` (already used by `AgentTools.execute`): stays the input type at the dispatch boundary. No need to introduce a new value type.
- `ToolDefinition` struct (sent to LLM as `tools: [...]`): keep the type, derive instances from the enum metadata instead of hand-authoring the array.
- `ModelOption` in `AIService.swift` (lines 14–26): repurpose as the web-layer view of catalog entries, or delete in favor of catalog descriptors directly.
- `AgentLoopProviderResponse` (stop reason, text blocks, tool calls): provider-output shape is unchanged — adapters decode to this same type.

### Established Patterns

- **Provider owns message array** (Phase 18): kept. `AgentProvider` mutates internal state via `appendX` methods; loop never sees provider-specific messages.
- **Tool implementations return String** (Phase 31, v1.3 roadmap): kept. Wrapping into `ToolResult` happens in `AgentTools.execute()`, not in `Tools/*.swift`.
- **Concrete-struct-with-closure over protocol** (e.g. `AgentMiddleware` is a protocol but `BudgetTracker`/`SpinDetector` are concrete; `AgentControl` is concrete with `Sendable`): Phase 42 leans concrete for `AgentProvider`, protocol for `Adapter` only because there are 3 implementations.
- **Strict resolution at boundaries** (e.g. `WikiService.fetchContext` returns `nil` not throws — but pricing-fallback hides errors): catalog adopts strict-throw semantics for unknown model IDs.
- **Atomic commits per layer** (Phase 41 etc.): supports the staged migration approach.

### Integration Points

- **`AgentLoop.swift`**: changes the type of `provider` (protocol → concrete struct). Body unchanged in shape; `provider.maxOutputTokensLimit` and `provider.pricingPerToken()` still readable but their values now come from the catalog via the resolved descriptor.
- **`AgentTools.swift`**: `execute()` body switches from `switch toolName: String` over case strings to `switch AgentToolName(rawValue: toolName)`. The pending-action tracking switch (line 692) goes away — replaced by enum metadata.
- **`AIService.swift`**: four provider-routing branches (lines 227, 311, 439, 662) collapse to one `catalog.descriptor(for: requestedID).provider` switch. `fallbackModels` either becomes a thin view or is removed.
- **`CellarConfig.aiModel`**: stays a `String?`. Resolution happens at session boundary via the catalog. Format unchanged ("claude-sonnet-4-6", "deepseek-chat", "moonshot-v1-128k").
- **Web UI model dropdown**: now rendered from `catalog ∩ liveFetched(perConfiguredProvider)`. Routes that today branch on provider keys read the catalog instead.

</code_context>

<specifics>
## Specific Ideas

- The phase wording "single model catalog" comes from observing two parallel sources today: per-provider `modelPricing` dicts inside `AgentLoopProvider.swift` AND `AIService.fallbackModels`. The catalog must replace both, not add a third.
- "Typed tool boundary" is intentionally narrow — the boundary is the dispatch site (`switch toolName`), not the tool implementations. Type safety stops at the wire-name match. Stronger typing of inputs/outputs is explicitly *not* the goal of this phase (Phase 41 just stabilized those signatures).
- Three adapters over two: the user values per-provider isolation more than maximum sharing — easier to add a fourth provider with quirks later without churning the OpenAI-compat code.

</specifics>

<deferred>
## Deferred Ideas

- **Move tool schemas / system prompt / engine rules to `Resources/`** — Phase 43.
- **Tool-use parity across providers** (DeepSeek + Kimi to match Anthropic's tool-use semantics) — Phase 43.
- **Bundled JSON model catalog editable without recompile** — could revisit if model churn outpaces release cadence; not a current pain point.
- **Hybrid catalog with `~/.cellar/models.json` override** — same; defer until ops need it.
- **Per-model budget defaults / context-window aware prepareStep trimming** — useful, but budget is runtime policy, not model identity. If pursued, becomes its own small phase.
- **Per-tool protocol with associated Input/Output types** — discussed and rejected for this phase (would force `Tools/*.swift` signature churn that v1.3 explicitly avoided).

</deferred>

---

*Phase: 42-unify-agent-loop-with-single-model-catalog-and-typed-tool-boundary*
*Context gathered: 2026-05-03*

# Phase 43: Extract Agent Policy Data to Versioned Resources & Provider Parity for Tool-Use - Context

**Gathered:** 2026-05-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Two coupled refactors delivered together:

1. **Externalize agent policy data**: move ~180-line system prompt, engine detection rules (KnownDLLRegistry + engine families), allowlists (env keys, registry prefixes), and tool schemas out of Swift literals into versioned files in `Resources/policy/`. Loader is fail-loud on schema mismatch.

2. **Provider tool-use parity**: DeepSeek and Kimi behave the same as Anthropic for tool-use semantics. All three providers call all 24 tools natively via their function-calling APIs through a single normalized internal shape (`AgentToolCall`). No JSON-in-text fallbacks, no degraded modes.

**Out of scope (other phases):**
- Memory layer collapse into `KnowledgeStore` — Phase 44.
- Splitting `AgentTools` into session/runtime actors, sandbox PageParser allowlist — Phase 45.
- New tools or prompt content rewrites — content moves verbatim to Resources/.

</domain>

<decisions>
## Implementation Decisions

### Resource format & layout

- **Location**: `Sources/cellar/Resources/policy/` bundled via SPM `.copy(...)` (matches Phase 38 wiki pattern).
- **Markdown for prose, JSON for structured data**:
  - `system_prompt.md` — the ~180-line system prompt verbatim (reviewable diffs)
  - `engines.json` — engine families, signatures, INI templates
  - `engine_dll_registry.json` — DLL replacement rules (cnc-ddraw, dgVoodoo2, dxwrapper, DXVK)
  - `env_allowlist.json` — env keys (AgentTools.allowedEnvKeys, Phase 28 carry-forward)
  - `registry_allowlist.json` — registry prefix list (Phase 28 carry-forward)
  - `tool_schemas.json` — JSON schemas keyed by tool raw name (currently inline on AgentToolName metadata, Phase 42)
- **No YAML**: avoids new SPM dep; codebase has no YAML parser today.

### Schema versioning

- **Per-file `schema_version` field**: each JSON file has a top-level `schema_version: 1`. Markdown files use a frontmatter `schema_version: 1`.
- **Fail-loud on mismatch**: loader throws `PolicyError.schemaVersionMismatch(file:expected:got:)`. No silent fallback to defaults. Bumping a schema is a code change — prevents drift.
- **No global pin**: each resource versions independently so unrelated changes don't co-evolve.

### Loading behavior

- **Ship-with-binary only**: SPM bundle is the single source. No `~/.cellar/policy/` override. Same call as Phase 38's wiki — keeps policy versioned with the binary, no extra attack surface, simpler loader.
- **No env var override**: deferred. If dev iteration friction shows up, revisit.
- **Single loader entry point**: `PolicyResources.shared` (or equivalent) reads everything once at startup and validates schema versions before the first agent session can run.

### Tool-use parity scope

- **Native function calling only**: DeepSeek and Kimi call all 24 tools via OpenAI-compat `tool_calls`. Anthropic uses `tool_use` blocks. No JSON-in-text fallback path. No degraded mode.
- **Models that can't tool-call stay excluded**: `deepseek-reasoner` remains excluded from `ModelCatalog` (Phase 18 carry-forward — no change).
- **No feature-parity stretch goals**: parallel tool calls, streaming `tool_use` deltas, system tool integration are NOT in scope for this phase. Behavioral parity for the existing single-call-per-step pattern is sufficient.
- **Same tool surface across providers**: all 24 tools available on every provider in the catalog. Tool surface is provider-independent.

### Where translation lives

- **Adapter classes own translation**: `AnthropicAdapter`, `DeepseekAdapter`, `KimiAdapter` (Phase 42 boundary) translate between their wire-protocol `tool_use`/`tool_calls` shapes and the canonical internal `AgentToolCall` shape.
- **AgentLoop and AgentTools see only the canonical shape**: the wire-protocol seam stays at the adapter (Phase 42 decision honored).
- **Canonical internal shape**: `struct AgentToolCall { let id: String; let name: String; let input: JSONValue }`. Provider-neutral. Pairs with `AgentToolName` enum for typed dispatch (Phase 42 carry-forward).
- **Tool result translation symmetric**: adapters also translate `ToolResult` → wire format (`tool_result` content blocks for Anthropic, `tool` role messages for OpenAI-compat).

### Verification

- **Unit tests on adapter translation**: each adapter's encode/decode round-trips a fixture set of `AgentToolCall` values. Catches API shape regressions cheaply.
- **Manual smoke test per provider**: one game launch per provider (Anthropic / DeepSeek / Kimi) end-to-end as part of phase verification. Catches what unit tests miss (auth headers, real tool_use_id semantics, retry behavior).
- **Tests live alongside adapters**: `Tests/cellarTests/Providers/AnthropicAdapterTests.swift` etc.

### Claude's Discretion

- **Migration ordering**: probably extract resources first (mechanical move + loader), then adapter parity work (riskier, depends on the catalog + adapter scaffolding from Phase 42). Atomic commit per resource extraction.
- **Loader implementation shape**: singleton vs DI, whether `PolicyResources` exposes typed structs or raw `JSONValue` — decided during planning.
- **Whether engine detection logic also moves**: data moves, but the matching logic (Swift functions that consume `engines.json`) stays in Swift. The boundary between data and logic to be drawn during planning.
- **Whether to introduce a shared OpenAI-compat helper now**: DeepSeek/Kimi adapter duplication grows when both gain tool-use translation. Phase 42 deferred this; Phase 43 may revisit if the duplication becomes loud.
- **Test fixture format**: hand-written vs captured-from-real-API. Trade-off between deterministic tests and real-world coverage.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- **Phase 42 adapter classes** (`AnthropicAdapter`, `DeepseekAdapter`, `KimiAdapter` under `Core/Providers/`): natural home for tool-call translation. Each is already a `final class` with distinct wire-protocol handling.
- **AgentToolName enum + metadata table** (Phase 42): keeps schema/description/pendingAction. Tool-schema migration to `tool_schemas.json` reads back into the metadata table at startup.
- **JSONValue** (already at the AgentTools dispatch boundary): stays the input type for `AgentToolCall.input`. No new value type needed.
- **SPM resource bundling pattern** (Phase 38 wiki): `.copy("Resources/policy")` in Package.swift. `Bundle.module` for access. Proven shipping path.
- **Phase 28 allowlists**: `AgentTools.allowedEnvKeys` (static let) and the registry prefix list — these are the literal arrays that move to JSON files.
- **CryptoKit / no new SPM deps preference**: stays. Resource loading uses `Foundation.JSONDecoder` only.

### Established Patterns

- **Adapters own wire-protocol differences** (Phase 42): tool-call translation extends what they already do for messages.
- **Provider owns conversation message state** (Phase 18): unchanged. Adapters' tool-call translation feeds the same `appendUserMessage`/`appendToolResults` paths.
- **Strict resolution at boundaries** (Phase 42 catalog): policy loading adopts the same fail-loud contract.
- **Three adapters, not two** (Phase 42): per-provider isolation valued over OpenAI-compat sharing. Phase 43 may revisit only if duplication becomes loud.
- **Atomic commits per layer** (Phase 41 etc.): supports staged migration.

### Integration Points

- **`AIService.swift`**: today builds the system prompt as a Swift string literal. Switches to `PolicyResources.shared.systemPrompt`. Loader runs once at startup.
- **`AgentTools.swift`**: `allowedEnvKeys` static let → `PolicyResources.shared.envAllowlist`. Same call sites, different source.
- **`AgentToolName` metadata table**: schema literals (currently `String` JSON in metadata) → loaded from `tool_schemas.json` at startup, keyed by raw value.
- **`KnownDLLRegistry` / engine detection**: data moves to `engines.json` + `engine_dll_registry.json`; matchers stay in Swift.
- **Adapter classes** (Phase 42): grow new methods `encodeToolCalls(_:[AgentToolCall]) -> WireShape` and `decodeToolCalls(_: WireResponse) -> [AgentToolCall]`. Existing message methods unchanged in signature.
- **Tests**: new `Tests/cellarTests/Providers/{Anthropic,Deepseek,Kimi}AdapterTests.swift`. New `Tests/cellarTests/Policy/PolicyResourcesTests.swift` for the loader.

</code_context>

<specifics>
## Specific Ideas

- "Provider parity" is intentionally narrow: same 24-tool surface, same single-call-per-step semantics. Not feature parity (parallel calls, streaming) — those are deferred.
- The adapter is the only place that knows about `tool_use_id` vs `tool_call_id` mapping. The rest of the codebase sees `AgentToolCall.id` as opaque.
- Resource extraction is "mechanical move + loader" first — content stays byte-identical so diffs are minimal. Schema versioning lets future content reorganization happen safely.
- Phase 42 deliberately chose Swift-static for `ModelCatalog` (data, not policy). Phase 43 chooses Resources/ for policy (prompt, rules, allowlists, schemas). The line: policy is reviewable text/data that ops/community might iterate on; data is type-safe constants the compiler should check.

</specifics>

<deferred>
## Deferred Ideas

- **`~/.cellar/policy/` override** — power-user escape hatch. Defer until ops need it.
- **Env var override (`CELLAR_POLICY_DIR`)** — dev iteration. Defer until rebuild friction shows up.
- **Parallel tool calls** — Anthropic supports them; OpenAI-compat partially. Future phase if multi-step parallelism becomes a bottleneck.
- **Streaming tool_use deltas** — would need event-stream reshape, large surface change.
- **Shared `OpenAICompatHelpers.swift`** — Phase 42 deferred; revisit during planning if tool-use translation makes Deepseek/Kimi adapter duplication loud.
- **Hot-reload during `cellar serve`** — would require file-watch + cache invalidation. Out of scope.
- **YAML format** — would need new SPM dep. Markdown + JSON sufficient.
- **Captured-from-real-API test fixtures** — defer to test design during planning.

</deferred>

---

*Phase: 43-extract-agent-policy-data-to-versioned-resources-and-achieve-provider-parity-for-tool-use-across-anthropic-deepseek-and-kimi*
*Context gathered: 2026-05-03*

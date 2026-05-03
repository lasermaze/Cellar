# Phase 42: Unify Agent Loop with Single Model Catalog and Typed Tool Boundary - Research

**Researched:** 2026-05-03
**Domain:** Swift refactor — agent loop architecture, provider abstraction, model catalog, typed enums
**Confidence:** HIGH (pure internal refactor; research is code archaeology, not library discovery)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Model catalog shape**
- Storage: static Swift table in `Sources/cellar/Core/ModelCatalog.swift`. Compile-time checked, no I/O, ships in binary.
- Fields (lean): `id`, `provider`, `pricing` (input/output per token), `maxOutputTokens`. No displayLabel, no supportsToolUse flag, no contextWindow, no recommendedBudget.
- Lookup behavior: strict resolution at session boundary. Unknown ID → throws / surfaces error to UI. Inside loop the resolved descriptor is non-optional. Silent `?? (0.0, 0.0)` fallback removed.
- Provider routing collapse: catalog entry carries `provider: AIProvider`. Four `if requested == "kimi"` branches in AIService collapse to one catalog lookup.
- Live `/v1/models` fetching: kept. Web dropdown = `catalog ∩ live_available_for_configured_providers`. Catalog is authoritative for pricing/limits; live fetch is availability check only.

**Loop + Provider unification**
- `AgentProvider` is a single concrete struct. `AgentLoop` holds `var provider: AgentProvider` — no protocol dispatch.
- Wire-protocol differences live in adapters (`AnthropicAdapter`, `DeepseekAdapter`, `KimiAdapter`). Each owns its quirks explicitly.
- Three adapters stay distinct; sharing via private helpers only if duplication becomes loud.
- Provider owns conversation message state (status quo). `AgentLoop` never sees raw API messages. Phase 18 decision preserved.
- File layout: `Core/AgentProvider.swift` (struct + adapter protocol/types), `Core/Providers/AnthropicAdapter.swift`, `Core/Providers/DeepseekAdapter.swift`, `Core/Providers/KimiAdapter.swift`. Replaces 623-line `AgentLoopProvider.swift`.

**Typed tool boundary**
- `enum AgentToolName: String, CaseIterable` — string-backed, replaces both `switch toolName: String` blocks.
- Per-case static metadata (description, JSON schema literal, optional pending-action descriptor) lives on enum via extension or static table.
- Hand-authored `toolDefinitions` array eliminated — derives from enum.
- Pending-action tracking collapses into enum property/method. Two parallel switches become one.
- Tool implementations in `Tools/*.swift` keep `JSONValue → String` signatures unchanged.

### Claude's Discretion

- Budget: stays runtime/`CellarConfig` concern. Catalog does not carry per-model budget defaults.
- Migration approach: staged within the phase (catalog → adapters → typed dispatch), atomic commits each. Old `AgentLoopProvider` protocol deleted at end of phase.
- Type/file naming: final names decided during planning.
- Adapter sharing: whether Deepseek/Kimi share `OpenAICompatHelpers.swift` decided at implementation time.
- `AIService.fallbackModels` fate: becomes thin web-layer view over catalog or removed entirely.

### Deferred Ideas (OUT OF SCOPE)

- Move tool schemas / system prompt / engine rules to `Resources/` — Phase 43.
- Tool-use parity across providers — Phase 43.
- Bundled JSON model catalog editable without recompile.
- Hybrid catalog with `~/.cellar/models.json` override.
- Per-model budget defaults / context-window aware prepareStep trimming.
- Per-tool protocol with associated Input/Output types.
</user_constraints>

---

## Summary

Phase 42 is a pure structural refactor with zero behavior change and zero new user-facing features. The work is archaeological: three overlapping concerns (model identity, provider wire-protocol, tool dispatch) are currently expressed in at least two places each. The phase's job is to make each concern exist in exactly one place. Because all three workstreams touch the same files (`AgentLoopProvider.swift`, `AIService.swift`, `AgentTools.swift`), ordering matters: the model catalog is the right starting point because it has no reverse dependencies on the other two, while the loop/provider unification and typed tool dispatch both benefit from having a canonical descriptor to reference.

The trickiest part is the provider unification. Today `AgentLoopProvider.swift` is a protocol + three concrete classes, each holding its own message array type. The new `AgentProvider` struct must encapsulate those different message array types inside per-provider adapters while keeping the same `appendX` / `callWithRetry` contract visible to `AgentLoop`. The key insight from CONTEXT.md is that the adapter protocol exists solely because there are three implementations — the rest of the codebase sees only the concrete `AgentProvider`.

The typed tool boundary is the smallest scope: two `switch toolName: String` blocks and a hand-authored array collapse into one enum with a computed property. The risk is underestimating the pending-action tracking switch at line 692 — it has different semantics (returns an optional description, not a dispatch result) and must become an enum method, not just a case in the execute() switch.

**Primary recommendation:** Sequence as three atomic commits — (1) ModelCatalog + AIService routing collapse, (2) AgentProvider struct + three adapters + delete AgentLoopProvider, (3) AgentToolName enum + derived toolDefinitions + unified pending-action. Build must be green after each commit.

---

## Architecture Patterns

### Recommended File Layout

```
Sources/cellar/
├── Core/
│   ├── ModelCatalog.swift          # NEW — static table, ModelDescriptor, resolver
│   ├── AgentProvider.swift         # NEW — concrete struct, ProviderAdapter protocol
│   ├── Providers/
│   │   ├── AnthropicAdapter.swift  # NEW — Anthropic Messages API encoding/decoding
│   │   ├── DeepseekAdapter.swift   # NEW — OpenAI-compat + reasoning-content quirks
│   │   └── KimiAdapter.swift       # NEW — OpenAI-compat + partial/safety flags
│   ├── AgentLoop.swift             # MODIFIED — provider: AgentProvider (was protocol)
│   ├── AgentTools.swift            # MODIFIED — enum dispatch, derived toolDefinitions
│   └── AgentLoopProvider.swift     # DELETED at end of phase
├── AIService.swift                 # MODIFIED — 4 routing branches → 1 catalog lookup
└── Persistence/CellarConfig.swift  # UNCHANGED — aiModel: String? stays
```

### Pattern 1: Refactor Sequencing (Foundational to Dependent)

**What:** Three ordered atomic commits where each leaves the build green.

**Order:**
1. **Commit A — ModelCatalog**: Create `ModelCatalog.swift` with `ModelDescriptor` struct and `ModelCatalog.descriptor(for id: String) throws -> ModelDescriptor`. Collapse the four AIService routing branches to one catalog lookup. Remove `fallbackModels` or reduce to a thin view. The existing `AgentLoopProvider` protocol is untouched — pricing/limits now read from the catalog descriptor at session init, injected as values.
2. **Commit B — AgentProvider**: Define `ProviderAdapter` protocol (internal) with `appendUserMessage`, `appendAssistantResponse`, `appendToolResults`, `callWithRetry`. Create three adapter files. Create `AgentProvider` concrete struct that holds an adapter and the resolved `ModelDescriptor`. Update `AgentLoop.provider` from `any AgentLoopProvider` to `AgentProvider`. Delete `AgentLoopProvider.swift`.
3. **Commit C — AgentToolName enum**: Define `enum AgentToolName: String, CaseIterable`. Add `var definition: ToolDefinition` computed property (or static `[AgentToolName: ToolMetadata]` table). Replace both `switch toolName: String` blocks. Remove hand-authored `toolDefinitions` array.

**Why catalog first:** `ModelDescriptor` provides the `provider: AIProvider` value that the adapter factory in `AgentProvider.init` needs to select which adapter to instantiate. Doing catalog after provider unification would require a placeholder or double-touch.

**Why tool enum last:** The enum change is contained inside `AgentTools.swift` and has no compile-time dependencies on the catalog or provider changes. It can slip to a separate PR if needed.

### Pattern 2: AgentProvider Concrete Struct with Internal Adapter Protocol

**What:** `AgentProvider` is the only type `AgentLoop` knows. Three adapter types conform to an internal protocol, one is held as `any ProviderAdapter` inside the struct.

```swift
// Internal protocol — not visible outside Core/
protocol ProviderAdapter {
    mutating func appendUserMessage(_ content: String)
    mutating func appendAssistantResponse(_ text: String, toolCalls: [ToolCall])
    mutating func appendToolResults(_ results: [ToolResult])
    mutating func callWithRetry(maxOutputTokens: Int) async throws -> AgentLoopProviderResponse
}

// Single concrete type AgentLoop holds
struct AgentProvider {
    private var adapter: any ProviderAdapter     // one of three adapters
    let descriptor: ModelDescriptor              // resolved at session boundary

    var maxOutputTokensLimit: Int { descriptor.maxOutputTokens }
    func pricingPerToken() -> (input: Double, output: Double) { descriptor.pricing }

    mutating func appendUserMessage(_ content: String) { adapter.appendUserMessage(content) }
    // ... delegates through
    mutating func callWithRetry(maxOutputTokens: Int) async throws -> AgentLoopProviderResponse {
        try await adapter.callWithRetry(maxOutputTokens: maxOutputTokens)
    }
}
```

**Key design point:** `ProviderAdapter` is `internal` (or even `fileprivate` to the `Core/` group). The protocol exists as an implementation mechanism, not as an extension point. `AgentLoop` is insulated from it entirely. This is the "concrete-struct-with-composition" pattern already used elsewhere in the codebase (`AgentControl`, `BudgetTracker`).

**Message array type problem:** Each provider today holds a different array element type (Anthropic's `MessageParam`, OpenAI's `ChatMessage`). Solution: each adapter struct holds its own message array as a private field typed to the provider-specific element type. The adapter is the module boundary — `AgentProvider` holds `any ProviderAdapter`, which erases the specific element type. This is exactly the Phase 18 decision preserved.

**Swift 6 concurrency note:** `AgentProvider` will be mutated inside `AgentLoop.runAgentLoop()`. Because `AgentLoop` owns the provider and the loop runs as a single async task, no additional lock is needed for the provider itself. If `AgentProvider` needs to be shared across tasks in the future, wrap in `OSAllocatedUnfairLock` per the Phase 31 pattern.

### Pattern 3: ModelCatalog — Static Table with Strict Resolver

```swift
// Sources/cellar/Core/ModelCatalog.swift

struct ModelDescriptor: Sendable {
    let id: String
    let provider: AIProvider       // existing enum
    let inputPricePerToken: Double
    let outputPricePerToken: Double
    let maxOutputTokens: Int
}

enum ModelCatalog {
    static let all: [ModelDescriptor] = [
        ModelDescriptor(id: "claude-opus-4-5",      provider: .anthropic,  inputPricePerToken: ..., outputPricePerToken: ..., maxOutputTokens: 32000),
        ModelDescriptor(id: "claude-sonnet-4-6",    provider: .anthropic,  ...),
        ModelDescriptor(id: "claude-haiku-3-5",     provider: .anthropic,  ...),
        ModelDescriptor(id: "deepseek-chat",        provider: .deepseek,   ...),
        // deepseek-reasoner intentionally absent (Phase 18: no function calling)
        ModelDescriptor(id: "moonshot-v1-128k",     provider: .kimi,       ...),
        ModelDescriptor(id: "moonshot-v1-32k",      provider: .kimi,       ...),
    ]

    static func descriptor(for id: String) throws -> ModelDescriptor {
        guard let d = all.first(where: { $0.id == id }) else {
            throw ModelCatalogError.unknownModel(id)
        }
        return d
    }
}

enum ModelCatalogError: Error, LocalizedError {
    case unknownModel(String)
    var errorDescription: String? {
        switch self {
        case .unknownModel(let id): return "Unknown model '\(id)'. Check your AI model setting."
        }
    }
}
```

**Resolution site:** `AIService.startSession()` (or equivalent session-boundary method). This is the single call site: `let descriptor = try ModelCatalog.descriptor(for: config.aiModel ?? defaultModelID)`. The descriptor is then passed into `AgentProvider.init(descriptor:)`. Nowhere else resolves a model string.

### Pattern 4: AgentToolName Enum with Derived Metadata

**Two viable approaches — recommend static dictionary table:**

**Option A — Computed property switch:**
```swift
extension AgentToolName {
    var definition: ToolDefinition {
        switch self {
        case .inspectGame: return ToolDefinition(name: rawValue, description: "...", inputSchema: [...])
        // 21 more cases
        }
    }
}
```
Pro: compiler enforces exhaustiveness. Con: 22-case switch with multi-line schema literals is loud (~200 lines). Adding a case requires editing the switch.

**Option B — Static dictionary table (recommended):**
```swift
extension AgentToolName {
    private static let metadata: [AgentToolName: ToolMetadata] = [
        .inspectGame: ToolMetadata(
            description: "...",
            inputSchema: JSONValue.object([...]),
            pendingActionDescription: nil
        ),
        // ...
    ]

    var definition: ToolDefinition {
        let m = Self.metadata[self]!   // safe: table is complete, compiler-checked at site
        return ToolDefinition(name: rawValue, description: m.description, inputSchema: m.inputSchema)
    }

    func pendingActionDescription(for input: JSONValue) -> String? {
        Self.metadata[self]?.pendingActionDescription.map { /* format with input */ }
    }
}
```
Pro: definition of each tool is visually self-contained in one dictionary literal. The `pendingActionDescription` for each tool is co-located with its schema (currently the two switches are separated by 36 lines). Dictionary keys are enum cases — typo-safe. Con: runtime force-unwrap (mitigated by unit test that iterates `CaseIterable` and verifies all keys present).

**Recommendation:** Option B (dictionary table). The self-contained tool block is easier to read than a 22-case switch with embedded schema literals. Add a unit test: `for tool in AgentToolName.allCases { XCTAssertNotNil(AgentToolName.metadata[tool]) }`.

### Pattern 5: Live `/v1/models` Integration

**Data flow:**
```
CellarConfig.apiKey(for: provider)
    ↓
AIService.fetchAvailableModels(for: provider) → [String]   // live /v1/models
    ↓
ModelCatalog.all.filter { catalog.provider == provider && liveSet.contains(catalog.id) }
    ↓
[ModelDescriptor]  → web dropdown (id + formatted label from id)
```

**Key constraint:** The catalog is the filter, not the live fetch. Unknown IDs from live fetch are silently dropped — the UI never shows a model the catalog doesn't know about (which would mean no pricing/limits). This prevents the re-introduction of per-provider branching because the `provider` discriminant lives in the catalog entry, not in a branch condition.

**`AIService.fallbackModels` fate:** Replace with `ModelCatalog.all` filtered to currently configured providers, with live fetch layered on top. The `ModelOption` struct in `AIService` can be converted to a thin computed view: `extension ModelDescriptor { var asModelOption: ModelOption { ... } }`. Delete the hand-authored array.

---

## Common Pitfalls

### Pitfall 1: Breaking AgentLoop's Provider Call at Commit B

**What goes wrong:** `AgentLoop` calls `provider.callWithRetry(maxOutputTokens:)` which is async throws. When the field type changes from `any AgentLoopProvider` to `AgentProvider` (a struct), the mutation semantics change — `mutating` methods on a stored struct require the call site to `var provider`, not `let`. If `AgentLoop` has `let provider`, the compiler error is non-obvious.

**How to avoid:** Confirm `AgentLoop.provider` is `var` before commit B. Add `mutating` to adapter protocol methods and delegate through the struct's mutating wrappers.

**Warning signs:** Compiler error "cannot use mutating member on immutable value" in `AgentLoop.runAgentLoop()`.

### Pitfall 2: Protocol Existential Performance with `any ProviderAdapter`

**What goes wrong:** `any ProviderAdapter` inside `AgentProvider` is a protocol existential. In Swift 5.7+ this is explicit syntax, but using it for a large message array (potentially hundreds of messages across a long session) means each `appendX` call goes through dynamic dispatch.

**Why it matters (not much here):** The append calls happen at most once per tool invocation. Performance is not the concern. The concern is that `any ProviderAdapter` storing a struct adapter will copy the adapter on mutation (value semantics). Use `class`-backed adapters or a reference wrapper if the message array is large and copy-on-write overhead matters.

**How to avoid:** Make the three adapter types `class` (reference semantics), not `struct`. This avoids the existential-copy issue entirely and matches the existing `AgentLoopProvider` pattern (they are classes today via the protocol).

**Alternative:** Keep adapters as structs but use `inout` or `UnsafeMutablePointer` — more complex, not worth it. Class adapters is the straightforward choice.

### Pitfall 3: `toolDefinitions` Drift Between Enum and Live Array

**What goes wrong:** During the transition at Commit C, if the hand-authored `toolDefinitions` array is removed before the enum extension is complete, any call site that reads `toolDefinitions` will fail to compile. The old array exists as a property of `AgentTools` — it must stay until `var toolDefinitions: [ToolDefinition]` is replaced by `AgentToolName.allCases.map { $0.definition }`.

**How to avoid:** In Commit C, first add the enum metadata (additive), verify the derived array matches the hand-authored one (test or manual diff), then delete the hand-authored array as a single diff in the same commit.

### Pitfall 4: Catalog Resolution Error Swallowed at Session Start

**What goes wrong:** `AIService.startSession()` throws on unknown model ID. If the caller does `try?` or catches-and-ignores, the user sees a silent failure (no agent, no error message).

**How to avoid:** The error must propagate to the UI as a user-visible message. The existing pattern for this in `AIService` is to pass an error string back through the event channel (`AgentEvent.error(String)`). Confirm that path exists before making the throw non-optional.

### Pitfall 5: Pending-Action Descriptions That Format with Input

**What goes wrong:** The current `switch toolName: String` at `AgentTools.swift:692` for pending-action tracking is not a simple lookup — some cases format the description using the tool's input arguments (e.g., showing the game name or command being run). A static dictionary table alone can't capture this without a closure.

**How to avoid:** The `pendingActionDescription` field in `ToolMetadata` should be `((JSONValue) -> String?)?` — a closure that receives the input and returns the formatted string. For tools with no pending action it is `nil`; for tools that need the input it is a closure. This matches the existing behavior without losing information.

---

## Code Examples

### ModelDescriptor + Strict Resolver

```swift
// Source: pattern from CONTEXT.md + project conventions
struct ModelDescriptor: Sendable {
    let id: String
    let provider: AIProvider
    let inputPricePerToken: Double
    let outputPricePerToken: Double
    let maxOutputTokens: Int
}

enum ModelCatalog {
    static let all: [ModelDescriptor] = [ /* ... */ ]

    static func descriptor(for id: String) throws -> ModelDescriptor {
        guard let d = all.first(where: { $0.id == id }) else {
            throw ModelCatalogError.unknownModel(id)
        }
        return d
    }
}
```

### AgentProvider Struct Delegating to Adapter

```swift
// Source: CONTEXT.md decisions + project concrete-struct pattern
struct AgentProvider {
    private var adapter: any ProviderAdapter
    let descriptor: ModelDescriptor

    init(descriptor: ModelDescriptor, apiKey: String) {
        self.descriptor = descriptor
        switch descriptor.provider {
        case .anthropic: adapter = AnthropicAdapter(model: descriptor.id, apiKey: apiKey)
        case .deepseek:  adapter = DeepseekAdapter(model: descriptor.id, apiKey: apiKey)
        case .kimi:      adapter = KimiAdapter(model: descriptor.id, apiKey: apiKey)
        }
    }

    var maxOutputTokensLimit: Int { descriptor.maxOutputTokens }
    func pricingPerToken() -> (input: Double, output: Double) {
        (descriptor.inputPricePerToken, descriptor.outputPricePerToken)
    }

    mutating func appendUserMessage(_ content: String) { adapter.appendUserMessage(content) }
    // ... other delegates
    mutating func callWithRetry(maxOutputTokens: Int) async throws -> AgentLoopProviderResponse {
        try await adapter.callWithRetry(maxOutputTokens: maxOutputTokens)
    }
}
```

### AgentToolName Enum with Metadata Table

```swift
// Source: CONTEXT.md decisions
enum AgentToolName: String, CaseIterable {
    case inspectGame         = "inspect_game"
    case runWineCommand      = "run_wine_command"
    case saveSuccess         = "save_success"
    case saveFailure         = "save_failure"
    case updateWiki          = "update_wiki"
    // ... ~18 more
}

private struct ToolMetadata {
    let description: String
    let inputSchema: JSONValue
    let pendingAction: ((JSONValue) -> String?)?   // nil if no pending action
}

extension AgentToolName {
    private static let metadata: [AgentToolName: ToolMetadata] = [
        .inspectGame: ToolMetadata(
            description: "Inspect a game installation...",
            inputSchema: .object(["type": .string("object"), "properties": .object([...])]),
            pendingAction: nil
        ),
        .runWineCommand: ToolMetadata(
            description: "Run a Wine command...",
            inputSchema: .object([...]),
            pendingAction: { input in
                guard case .string(let cmd) = (input.objectValue?["command"]) else { return nil }
                return "Running: \(cmd)"
            }
        ),
        // ...
    ]

    var definition: ToolDefinition {
        let m = Self.metadata[self]!
        return ToolDefinition(name: rawValue, description: m.description, inputSchema: m.inputSchema)
    }

    func pendingActionDescription(for input: JSONValue) -> String? {
        Self.metadata[self]??.pendingAction?(input)
    }
}

// Derived toolDefinitions — replaces hand-authored array
extension AgentTools {
    var toolDefinitions: [ToolDefinition] {
        AgentToolName.allCases.map { $0.definition }
    }
}
```

### AIService Routing Collapse

```swift
// Before (4 scattered branches):
if requested == "kimi" || requested == "moonshot" { ... }  // line 227
if model.contains("kimi") { ... }                          // line 311

// After (one resolution site):
let descriptor = try ModelCatalog.descriptor(for: requestedModel)
switch descriptor.provider {
case .anthropic: return makeAnthropicRequest(...)
case .deepseek:  return makeDeepseekRequest(...)
case .kimi:      return makeKimiRequest(...)
}
```

---

## Migration Safety

### Dual-Path States Needed

The migration can proceed with **no dual-path states** if commits are strictly ordered. The old `AgentLoopProvider` protocol is not deleted until Commit B is complete and building. The old `toolDefinitions` hand-authored array is not deleted until Commit C's enum metadata is verified.

| Step | Old code state | New code state | Dual-path? |
|------|---------------|----------------|------------|
| Commit A: catalog | `AgentLoopProvider` unchanged | `ModelCatalog` added; AIService uses catalog for routing; pricing/limits injected into provider init | No — catalog is additive until AIService routing branches removed |
| Commit B: provider | `AgentLoopProvider.swift` present but unused (adapters replace it) | `AgentProvider`, three adapters, `AgentLoop.provider` switched | Brief dual compile: old protocol file stays until adapters compile; then deleted in same commit |
| Commit C: enum | Hand-authored `toolDefinitions` present | Enum + metadata added; derived array verified equal; then old array deleted | Additive add, then delete in same commit |

**Types that delete at end of phase (not mid-phase):**
- `AgentLoopProvider` protocol and all three existing provider implementations — deleted at end of Commit B
- Hand-authored `toolDefinitions: [ToolDefinition]` array — deleted within Commit C

**Types that delete mid-phase (safe):**
- The four `if requested == "kimi"` style routing conditions in AIService — removed in Commit A

---

## Verification / Smoke Test

This is a refactor phase — verification is behavioral identity, not new behavior.

**Minimum smoke-test path:** Launch a real agent session with any provider. Confirm:
1. Session starts (model resolves from catalog without error)
2. Tools are dispatched correctly (no "unknown tool" path)
3. Pending-action descriptions appear for tools that had them before
4. Session costs are calculated (pricing comes from catalog)
5. Stop/confirm still work (AgentControl unaffected by this phase)

**Build verification after each commit:** `swift build` must succeed with no warnings promoted to errors.

**Unit test seams worth adding:**
- `ModelCatalog.allCases` completeness: verify all expected model IDs resolve without throwing
- `AgentToolName.allCases` metadata completeness: verify every case has a metadata entry (catches dictionary gaps that compiler won't)
- `AgentToolName.allCases.map { $0.rawValue }` against the old hand-authored tool-name strings (regression guard)

**No automated test infrastructure detected** in the project (pure Swift app, no XCTest files observed). Manual smoke test is the gate. The unit test seams above are worthwhile additions but are not blocking.

---

## Open Questions

1. **`any ProviderAdapter` mutability: struct vs class adapters**
   - What we know: protocol existentials storing structs copy on mutation in Swift; the existing providers are classes.
   - What's unclear: whether `mutating` methods on a protocol existential work as expected or require `class` constraint.
   - Recommendation: Make all three adapter types `class` (consistent with current implementation, avoids existential mutation surprises). The adapter protocol can add `: AnyObject` constraint.

2. **`AIProvider` enum — does it already exist?**
   - What we know: CONTEXT.md references `provider: AIProvider` as if it exists; `AIService.swift` has routing branches.
   - What's unclear: whether `AIProvider` is already a named enum or is inferred from context.
   - Recommendation: Planner should grep for `enum AIProvider` or `enum Provider` before writing Commit A. If it doesn't exist, creating it is a prerequisite in Commit A.

3. **`toolDefinitions` call sites beyond `AgentTools`**
   - What we know: `AgentTools.execute()` uses the array; the LLM call sends it as `tools:`.
   - What's unclear: whether `toolDefinitions` is read outside `AgentTools` (e.g., in `AIService` for the API call body).
   - Recommendation: Planner should grep for `toolDefinitions` usage before Commit C to find all call sites.

4. **Pricing values for current model lineup**
   - What we know: Pricing is duplicated in `AgentLoopProvider.swift` per-provider dicts and must be copied correctly to `ModelCatalog.all`.
   - What's unclear: whether the values are stale (models get repriced).
   - Recommendation: Copy values from the existing dicts (lines 43-49, 264-265, 469-470 of `AgentLoopProvider.swift`) and note them as "from prior implementation, verify against current provider pricing pages."

---

## Sources

### Primary (HIGH confidence)
- CONTEXT.md — complete locked decisions, architecture constraints, file scope
- `AgentLoop.swift` (read directly) — confirmed `AgentLoopResult`, `AgentEvent`, `ToolResult` types; `var provider` field
- STATE.md lines 245-270 — confirmed phase 42 intent and phase 41 completion state
- REQUIREMENTS.md — confirmed v1.3 requirements all complete; phase 42 is post-v1.3 cleanup

### Secondary (MEDIUM confidence)
- Swift documentation on protocol existentials (`any P`) and mutation semantics — training knowledge, flagged

### Tertiary (LOW confidence)
- Specific pricing values in `AgentLoopProvider.swift` lines 43-49, 264-265, 469-470 — not read directly; planner must verify

---

## Metadata

**Confidence breakdown:**
- Refactor sequencing: HIGH — derived directly from CONTEXT.md decisions and file dependency analysis
- AgentProvider struct shape: HIGH — locked in CONTEXT.md, Swift idioms well-established
- Catalog design: HIGH — CONTEXT.md specifies fields, resolver semantics, and resolution site
- Tool enum metadata shape: HIGH — both options analyzed, recommendation made with rationale
- Pitfalls: MEDIUM — based on Swift language behavior and code archaeology; actual code not fully read

**Research date:** 2026-05-03
**Valid until:** 2026-06-03 (stable internal refactor, no external dependencies)

# Phase 43: Extract Agent Policy Data to Versioned Resources & Provider Parity - Research

**Researched:** 2026-05-03
**Domain:** Swift/SPM resource bundling, JSON policy loading, OpenAI-compat tool-call wire protocol
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Resource format & layout**
- Location: `Sources/cellar/Resources/policy/` bundled via SPM `.copy(...)` (matches Phase 38 wiki pattern).
- Markdown for prose, JSON for structured data:
  - `system_prompt.md` — the ~180-line system prompt verbatim (reviewable diffs)
  - `engines.json` — engine families, signatures, INI templates
  - `engine_dll_registry.json` — DLL replacement rules (cnc-ddraw, dgVoodoo2, dxwrapper, DXVK)
  - `env_allowlist.json` — env keys (AgentTools.allowedEnvKeys, Phase 28 carry-forward)
  - `registry_allowlist.json` — registry prefix list (Phase 28 carry-forward)
  - `tool_schemas.json` — JSON schemas keyed by tool raw name (currently inline on AgentToolName metadata, Phase 42)
- No YAML: avoids new SPM dep; codebase has no YAML parser today.

**Schema versioning**
- Per-file `schema_version` field: each JSON file has a top-level `schema_version: 1`. Markdown files use a frontmatter `schema_version: 1`.
- Fail-loud on mismatch: loader throws `PolicyError.schemaVersionMismatch(file:expected:got:)`. No silent fallback to defaults. Bumping a schema is a code change — prevents drift.
- No global pin: each resource versions independently so unrelated changes don't co-evolve.

**Loading behavior**
- Ship-with-binary only: SPM bundle is the single source. No `~/.cellar/policy/` override. Same call as Phase 38's wiki — keeps policy versioned with the binary, no extra attack surface, simpler loader.
- No env var override: deferred.
- Single loader entry point: `PolicyResources.shared` (or equivalent) reads everything once at startup and validates schema versions before the first agent session can run.

**Tool-use parity scope**
- Native function calling only: DeepSeek and Kimi call all 24 tools via OpenAI-compat `tool_calls`. Anthropic uses `tool_use` blocks. No JSON-in-text fallback path. No degraded mode.
- Models that can't tool-call stay excluded: `deepseek-reasoner` remains excluded from `ModelCatalog` (Phase 18 carry-forward — no change).
- No feature-parity stretch goals: parallel tool calls, streaming `tool_use` deltas, system tool integration are NOT in scope. Behavioral parity for the existing single-call-per-step pattern is sufficient.
- Same tool surface across providers: all 24 tools available on every provider in the catalog. Tool surface is provider-independent.

**Where translation lives**
- Adapter classes own translation: `AnthropicAdapter`, `DeepseekAdapter`, `KimiAdapter` (Phase 42 boundary) translate between their wire-protocol `tool_use`/`tool_calls` shapes and the canonical internal `AgentToolCall` shape.
- AgentLoop and AgentTools see only the canonical shape: the wire-protocol seam stays at the adapter (Phase 42 decision honored).
- Canonical internal shape: `struct AgentToolCall { let id: String; let name: String; let input: JSONValue }`. Provider-neutral. Pairs with `AgentToolName` enum for typed dispatch (Phase 42 carry-forward).
- Tool result translation symmetric: adapters also translate `ToolResult` → wire format (`tool_result` content blocks for Anthropic, `tool` role messages for OpenAI-compat).

**Verification**
- Unit tests on adapter translation: each adapter's encode/decode round-trips a fixture set of `AgentToolCall` values. Catches API shape regressions cheaply.
- Manual smoke test per provider: one game launch per provider (Anthropic / DeepSeek / Kimi) end-to-end as part of phase verification.
- Tests live alongside adapters: `Tests/cellarTests/Providers/AnthropicAdapterTests.swift` etc.

### Claude's Discretion

- **Migration ordering**: probably extract resources first (mechanical move + loader), then adapter parity work (riskier, depends on the catalog + adapter scaffolding from Phase 42). Atomic commit per resource extraction.
- **Loader implementation shape**: singleton vs DI, whether `PolicyResources` exposes typed structs or raw `JSONValue` — decided during planning.
- **Whether engine detection logic also moves**: data moves, but the matching logic (Swift functions that consume `engines.json`) stays in Swift. The boundary between data and logic to be drawn during planning.
- **Whether to introduce a shared OpenAI-compat helper now**: DeepSeek/Kimi adapter duplication grows when both gain tool-use translation. Phase 42 deferred this; Phase 43 may revisit if the duplication becomes loud.
- **Test fixture format**: hand-written vs captured-from-real-API. Trade-off between deterministic tests and real-world coverage.

### Deferred Ideas (OUT OF SCOPE)

- `~/.cellar/policy/` override — power-user escape hatch. Defer until ops need it.
- Env var override (`CELLAR_POLICY_DIR`) — dev iteration. Defer until rebuild friction shows up.
- Parallel tool calls — Anthropic supports them; OpenAI-compat partially. Future phase if multi-step parallelism becomes a bottleneck.
- Streaming tool_use deltas — would need event-stream reshape, large surface change.
- Shared `OpenAICompatHelpers.swift` — Phase 42 deferred; revisit during planning if tool-use translation makes Deepseek/Kimi adapter duplication loud.
- Hot-reload during `cellar serve` — would require file-watch + cache invalidation. Out of scope.
- YAML format — would need new SPM dep. Markdown + JSON sufficient.
- Captured-from-real-API test fixtures — defer to test design during planning.
</user_constraints>

---

## Summary

Phase 43 has two coupled sub-tracks: (1) **policy extraction** — move ~180-line system prompt, `KnownDLLRegistry`, `EngineRegistry`, `allowedEnvKeys`, the registry prefix list, and `AgentToolName` inline schemas out of Swift literals into six versioned files under `Sources/cellar/Resources/policy/`; and (2) **provider tool-use parity** — add tool-call encode/decode methods to all three adapters so DeepSeek and Kimi route tool calls through their native `tool_calls` wire protocol, eliminating any JSON-in-text fallback.

The codebase is ready for both tracks. Phase 42 created the three adapter classes and `AgentToolName` enum that Phase 43 builds on. The existing SPM resource bundling pattern from Phase 38 (`Bundle.module` + `.copy("Resources")` in `Package.swift`) already works and ships the policy directory in the same binary — no new infrastructure needed. The six policy files are straightforward serializations of data already in the codebase; the loader is the only new type required.

The tool-use parity work is simpler than it appears: DeepSeek and Kimi adapters already parse `tool_calls` responses in `translateDeepseekResponse`/`translateKimiResponse` (they already decode `call.id`, `call.function.name`, and the JSON `arguments` string into `(id, name, input)` tuples). The gap is on the **request side** — the adapters currently accept `[ToolDefinition]` and convert to `[OpenAIToolDef]` at init, but there is no canonical `AgentToolCall` struct and no `appendToolCalls` method on `ProviderAdapter`. Adding those makes the wire boundary explicit and testable.

**Primary recommendation:** Migrate the two sub-tracks as two plan files: P01 = policy extraction + loader (mechanical, zero behavior change), P02 = `AgentToolCall` struct + adapter encode/decode methods + tests.

---

## Standard Stack

### Core (already in codebase — no new dependencies)

| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| `Foundation.JSONDecoder` | stdlib | Parse policy JSON files | Already used throughout; no new dep |
| `Bundle.module` | SPM + Foundation | Access bundled resources | Phase 38 wiki already uses this pattern |
| `.copy("Resources")` in `Package.swift` | SPM | Bundle Resources/ directory | Already wired; `policy/` subdirectory just appears inside |
| `swift-testing` | Test target | Unit tests | Already the test framework (see existing tests) |

### No New Dependencies

The constraint from CONTEXT.md is honored: Foundation `JSONDecoder` is sufficient for all policy files. No YAML parser, no new SPM packages.

**Existing resources path:**
```
Sources/cellar/Resources/   ← already bundled via .copy("Resources")
├── Public/                 ← Vapor static assets
└── Views/                  ← Leaf templates
```

`policy/` becomes a new subdirectory inside `Resources/` — the existing `.copy("Resources")` in `Package.swift` picks it up automatically. No `Package.swift` change needed.

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/cellar/
├── Core/
│   ├── PolicyResources.swift        # NEW: loader singleton
│   └── Providers/
│       ├── AnthropicAdapter.swift   # MODIFY: add AgentToolCall encode/decode
│       ├── DeepseekAdapter.swift    # MODIFY: add AgentToolCall encode/decode
│       └── KimiAdapter.swift        # MODIFY: add AgentToolCall encode/decode
├── Models/
│   └── AgentToolCall.swift          # NEW: canonical struct (or add to AIModels.swift)
└── Resources/
    └── policy/                      # NEW directory
        ├── system_prompt.md
        ├── engines.json
        ├── engine_dll_registry.json
        ├── env_allowlist.json
        ├── registry_allowlist.json
        └── tool_schemas.json

Tests/cellarTests/
├── Providers/                       # NEW directory
│   ├── AnthropicAdapterTests.swift
│   ├── DeepseekAdapterTests.swift
│   └── KimiAdapterTests.swift
└── Policy/                          # NEW directory
    └── PolicyResourcesTests.swift
```

### Pattern 1: SPM Bundle Resource Loading (HIGH confidence)

**What:** Resources under `.copy("Resources")` are accessible via `Bundle.module` in Swift Package Manager targets.
**When to use:** Any static data that ships with the binary but benefits from being a reviewable file.
**Example (from Phase 38 WikiService — verified in codebase):**

```swift
// Source: existing WikiService.swift pattern in this codebase
guard let resourceURL = Bundle.module.url(forResource: "wiki/index", withExtension: "md") else {
    return nil
}
let content = try String(contentsOf: resourceURL, encoding: .utf8)
```

For `policy/system_prompt.md`:
```swift
guard let url = Bundle.module.url(forResource: "policy/system_prompt", withExtension: "md") else {
    fatalError("policy/system_prompt.md missing from bundle — build error")
}
let raw = try String(contentsOf: url, encoding: .utf8)
```

**Note:** `Bundle.module.url(forResource:withExtension:)` does NOT use path separators in the resource name — the full path from the bundle root must be provided as the resource name without extension. For files in subdirectories, use the full relative path: `"policy/system_prompt"`.

### Pattern 2: Fail-Loud Schema Version Check (HIGH confidence)

**What:** Each JSON file has `"schema_version": 1` at top level. Loader compares against the expected version constant and throws immediately on mismatch.
**When to use:** Any versioned resource file.
**Example:**

```swift
// PolicyResources.swift — verified pattern from CONTEXT.md decisions
enum PolicyError: Error {
    case missingResource(String)
    case schemaVersionMismatch(file: String, expected: Int, got: Int)
    case decodingError(String, Error)
}

private func loadJSON<T: Decodable>(resource: String, expectedVersion: Int) throws -> T {
    guard let url = Bundle.module.url(forResource: resource, withExtension: "json") else {
        throw PolicyError.missingResource("\(resource).json")
    }
    let data = try Data(contentsOf: url)
    let raw = try JSONDecoder().decode(VersionedWrapper<T>.self, from: data)
    guard raw.schemaVersion == expectedVersion else {
        throw PolicyError.schemaVersionMismatch(
            file: "\(resource).json",
            expected: expectedVersion,
            got: raw.schemaVersion
        )
    }
    return raw.data  // or raw itself if wrapper is flat
}
```

### Pattern 3: Markdown Frontmatter for system_prompt.md (MEDIUM confidence)

**What:** `system_prompt.md` needs a `schema_version` field. The locked decision says "Markdown files use a frontmatter `schema_version: 1`". This means a YAML-style frontmatter block at the top.
**How to parse without a YAML parser:** Simple line-by-line frontmatter extraction. The frontmatter is minimal (one field). No YAML library needed.

```swift
// Parse --- frontmatter --- from markdown, extract schema_version: N, return body
func parseMarkdownFrontmatter(_ raw: String) throws -> (version: Int, body: String) {
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.first == "---" else {
        // No frontmatter — treat whole content as body with version 0
        return (0, raw)
    }
    guard let endIdx = lines.dropFirst().firstIndex(of: "---") else {
        throw PolicyError.decodingError("system_prompt.md", NSError()) // unclosed frontmatter
    }
    let fmLines = lines[1..<endIdx]
    var version = 0
    for line in fmLines {
        if line.hasPrefix("schema_version:") {
            let val = line.dropFirst("schema_version:".count).trimmingCharacters(in: .whitespaces)
            version = Int(val) ?? 0
        }
    }
    let body = lines[(endIdx + 1)...].joined(separator: "\n")
    return (version, body)
}
```

### Pattern 4: AgentToolCall Canonical Struct (HIGH confidence)

**What:** The `AgentToolCall` struct is the provider-neutral representation of a single tool invocation. It pairs with `AgentToolName` (Phase 42) for typed dispatch.
**Location:** Best placed in `Models/AgentToolCall.swift` (or appended to `Models/AIModels.swift`).

```swift
// Source: CONTEXT.md canonical shape decision
struct AgentToolCall {
    let id: String        // opaque; maps to tool_use_id (Anthropic) or tool_call_id (OpenAI-compat)
    let name: String      // raw tool name string (e.g. "set_environment")
    let input: JSONValue  // parsed arguments
}
```

The `id` field is already an opaque string in the existing `AgentLoopProviderResponse.toolCalls` tuple `(id: String, name: String, input: JSONValue)`. `AgentToolCall` is a named struct version of that tuple — no logic change, just naming.

### Pattern 5: Adapter Tool-Call Translation (HIGH confidence — verified from existing code)

**What:** Adapters already translate responses. They need symmetric encoding for requests.
**Current state:** `appendAssistantResponse` already serializes `(id, name, input)` tuples into `OpenAIToolRequest.ToolCall` or `ToolContentBlock.toolUse`. The gap is: `AgentLoopProviderResponse.toolCalls` uses anonymous tuples; `AgentToolCall` makes this typed.
**Migration path:** Replace the tuple type with `AgentToolCall` in `AgentLoopProviderResponse`, update the three adapters' `translateXxxResponse` methods to build `[AgentToolCall]` instead of `[(id:name:input:)]` tuples.

Anthropic response decoding (already correct in `AnthropicAdapter`):
```swift
// translateAnthropicResponse — already correct pattern, just typed:
case .toolUse(let id, let name, let input):
    toolCalls.append(AgentToolCall(id: id, name: name, input: input))
```

DeepSeek/Kimi response decoding (already correct, just needs struct):
```swift
// translateDeepseekResponse / translateKimiResponse — already parses arguments:
let input = try JSONDecoder().decode(JSONValue.self, from: argumentsData)
toolCalls.append(AgentToolCall(id: call.id, name: call.function.name, input: input))
```

Tool result encoding for Anthropic (`tool_result` content blocks):
```swift
// appendToolResults already does this — no change needed
.toolResult(toolUseId: result.id, content: result.content, isError: result.isError)
```

Tool result encoding for OpenAI-compat (`tool` role messages):
```swift
// appendToolResults already does this — no change needed
OpenAIToolRequest.Message(role: "tool", content: result.content, toolCallId: result.id)
```

### Pattern 6: PolicyResources Singleton (HIGH confidence)

**What:** Single-entry loader, initialized once before any agent session.
**Shape decision (Claude's Discretion):** Use a struct with static `shared` instance. Avoids protocol overhead, keeps it simple.

```swift
// PolicyResources.swift
struct PolicyResources {
    static let shared: PolicyResources = {
        do {
            return try PolicyResources()
        } catch {
            fatalError("PolicyResources failed to load: \(error)")
        }
    }()

    let systemPrompt: String
    let engines: [EngineDefinition]     // or a raw parsed struct
    let dllRegistry: [KnownDLL]         // or a raw parsed struct  
    let envAllowlist: Set<String>
    let registryAllowlist: [String]
    let toolSchemas: [String: JSONValue] // keyed by tool raw name

    private init() throws {
        // load all six files, validate schema versions
    }
}
```

**AIService.swift integration:**
```swift
// Replace literal system prompt string:
let systemPrompt = PolicyResources.shared.systemPrompt
```

**AgentTools.swift (ConfigTools.swift) integration:**
```swift
// Replace static let allowedEnvKeys
static var allowedEnvKeys: Set<String> { PolicyResources.shared.envAllowlist }
```

### Anti-Patterns to Avoid

- **Lazy per-file loading:** Loading each file on demand creates partial-init states. Load everything in `init() throws` and fail loudly.
- **Silent fallback to hardcoded defaults:** If `policy/engines.json` is missing, it's a build error, not a runtime condition. `fatalError` is correct here — policy is not optional.
- **Mutating the singleton:** `PolicyResources.shared` is immutable after init. If callers want to override for testing, inject the struct directly.
- **Duplicating JSON data from EngineRegistry:** The data migrates to JSON, but the Swift detection algorithm (`EngineRegistry.detect()`) stays in Swift. Do not serialize the algorithm.
- **Assuming subdirectory paths in Bundle.module work without testing:** The `.copy("Resources")` rule copies the entire `Resources/` directory. Files inside `Resources/policy/` are accessible with resource name `"policy/system_prompt"` (no leading slash, no `.md` extension in the `forResource:` parameter).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Encoding tool schemas to JSON | Custom JSONValue serializer | `JSONEncoder().encode(jsonValue)` — JSONValue is already Codable | JSONValue already implements Codable in the codebase |
| Version check with fallback | Graceful degradation on version mismatch | `fatalError` / `throw` loud error | Policy drift is a build error, not a runtime condition |
| Dynamic resource discovery | File listing / glob in bundle | Hardcoded file names in loader | Resources are known at build time; dynamic discovery adds fragility |
| Markdown parsing library | External dep | Simple frontmatter line scanner | Single field, no nested YAML |
| Argument deserialization in adapters | Custom JSON parser | Existing `JSONDecoder().decode(JSONValue.self, ...)` | Already done in `translateDeepseekResponse` and `translateKimiResponse` |

**Key insight:** Everything needed is already in the codebase. Policy extraction is data movement, not new infrastructure.

---

## Common Pitfalls

### Pitfall 1: Bundle.module URL for Subdirectories
**What goes wrong:** `Bundle.module.url(forResource: "policy/system_prompt", withExtension: "md")` returns `nil` even though the file exists.
**Why it happens:** SPM's `.copy("Resources")` copies the tree but the resource name for lookup may need adjustment depending on SPM version. Some SPM versions require the path relative to the bundle root.
**How to avoid:** Test `Bundle.module.url(forResource:withExtension:)` in a unit test with the actual path. Phase 38's WikiService already uses a similar pattern (`wiki/index.md`) — check how that lookup is done and replicate exactly.
**Warning signs:** `fatalError("...missing from bundle — build error")` fires on first run.

### Pitfall 2: JSON File Schema — Flat vs. Wrapped
**What goes wrong:** `schema_version` at top level conflicts with the actual data fields if the loader uses a single `Decodable` struct.
**Why it happens:** If `EngineDefinition` is decoded directly and also has `schema_version` at the same level, the keys collide.
**How to avoid:** Use a wrapper struct:
```swift
struct Versioned<T: Decodable>: Decodable {
    let schemaVersion: Int
    let data: T  // or spread keys via custom decode
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case data
    }
}
```
OR put `schema_version` as a top-level sibling with the array under a separate key:
```json
{ "schema_version": 1, "engines": [...] }
```
**Warning signs:** Decoding fails with "key not found" or extra key errors.

### Pitfall 3: EngineDefinition Codable Conformance
**What goes wrong:** `EngineDefinition` is currently a non-Codable `struct` with `Sendable`. Making it `Codable` for JSON loading requires all fields to be Codable.
**Why it happens:** All fields ARE basic Swift types (`String`, `[String]`, `String?`) — all naturally Codable. But adding `Codable` means `CodingKeys` must match the JSON field names exactly, or a custom mapping is needed.
**How to avoid:** Add `Codable` conformance to `EngineDefinition` in `EngineRegistry.swift`, use `CodingKeys` if the JSON field names differ from Swift property names (e.g. `peImportSignals` → `"pe_import_signals"`). The JSON schema must match.
**Warning signs:** Decode errors in unit tests.

### Pitfall 4: KnownDLL Codable — CompanionFile and Nested Types
**What goes wrong:** `KnownDLL` has `CompanionFile`, `DLLPlacementTarget`, and `[String: String]` fields. All need to be Codable.
**Why it happens:** `DLLPlacementTarget` is an enum — it needs `Codable` (probably raw-value `String` enum). `CompanionFile` is a struct — straightforward. `[String: String]` is already Codable.
**How to avoid:** Check the definition of `DLLPlacementTarget` and add `Codable` / `String` raw value conformance.
**Warning signs:** Compiler error on `KnownDLL: Codable` declaration.

### Pitfall 5: AgentToolName Schemas Are JSONValue, Not String
**What goes wrong:** `tool_schemas.json` stores schemas as actual JSON objects (nested maps), not JSON-escaped strings. If stored as strings, the loader has to double-decode.
**Why it happens:** The current `AgentToolName` metadata table has `inputSchema: JSONValue` — the schema is already a Swift `JSONValue` tree. When serialized to `tool_schemas.json`, each schema value must be a JSON object, not a string.
**How to avoid:** Serialize `tool_schemas.json` by extracting `AgentToolName.allCases` and encoding `{ rawValue: inputSchema }` pairs as a JSON object. The loader decodes to `[String: JSONValue]` and looks up by raw name.
**Warning signs:** Schema lookup returns `.string(...)` instead of `.object(...)`.

### Pitfall 6: AIService Has Duplicate System Prompt Builds
**What goes wrong:** `AIService.swift` builds the agent system prompt at line 673, but also builds shorter prompts for `_diagnose` (line 240), `_generateRecipe` (line 335), and `_generateVariants` (line 462). Only the agent loop prompt (line 673) moves to `system_prompt.md`.
**Why it happens:** The non-agent prompts are short, inline, and context-specific. Only the 270-line agent loop prompt is "policy."
**How to avoid:** Migrate only the `let systemPrompt = """..."""` block at line 673. Leave the diagnosis/recipe/variant prompts as inline strings.
**Warning signs:** Test for correct prompt content in `PolicyResourcesTests` would catch a wrong extraction.

### Pitfall 7: AgentToolCall — Avoiding Double-Introducing the Tuple
**What goes wrong:** `AgentLoopProviderResponse.toolCalls` is currently `[(id: String, name: String, input: JSONValue)]`. If `AgentToolCall` is introduced but `AgentLoopProviderResponse` is not updated, both representations exist and callers must convert.
**Why it happens:** Partial migration.
**How to avoid:** In the same commit that introduces `struct AgentToolCall`, update `AgentLoopProviderResponse.toolCalls` to `[AgentToolCall]`. All three adapters and all call sites update atomically.
**Warning signs:** Compiler error "cannot convert [AgentToolCall] to [(id:name:input:)]."

---

## Code Examples

### JSON Schema for engines.json
```json
{
  "schema_version": 1,
  "engines": [
    {
      "name": "GSC/DMCR",
      "family": "gsc",
      "file_patterns": ["fsgame.ltx", "xr_3da.exe", "dmcr.exe", "*.db0", "*.db1"],
      "pe_import_signals": ["ddraw.dll"],
      "string_signatures": ["X-Ray Engine", "GSC Game World", "DMCR"],
      "typical_graphics_api": "directdraw"
    }
  ]
}
```
Note: Swift property names (camelCase) must map to JSON keys (snake_case) via `CodingKeys`.

### JSON Schema for engine_dll_registry.json
```json
{
  "schema_version": 1,
  "dlls": [
    {
      "name": "cnc-ddraw",
      "dll_file_name": "ddraw.dll",
      "github_owner": "FunkyFr3sh",
      "github_repo": "cnc-ddraw",
      "asset_pattern": "cnc-ddraw.zip",
      "description": "DirectDraw replacement for classic 2D games via OpenGL/D3D9",
      "required_overrides": {"ddraw": "n,b"},
      "companion_files": [
        { "filename": "ddraw.ini", "content": "[ddraw]\nrenderer=opengl\n..." }
      ],
      "preferred_target": "syswow64",
      "is_system_dll": true,
      "variants": {}
    }
  ]
}
```

### JSON Schema for env_allowlist.json
```json
{
  "schema_version": 1,
  "allowed_keys": [
    "WINEDLLOVERRIDES",
    "WINEFSYNC",
    "WINEESYNC",
    "WINEDEBUG",
    "WINE_CPU_TOPOLOGY",
    "WINE_LARGE_ADDRESS_AWARE",
    "WINED3D_DISABLE_CSMT",
    "MESA_GL_VERSION_OVERRIDE",
    "MESA_GLSL_VERSION_OVERRIDE",
    "STAGING_SHARED_MEMORY",
    "DXVK_HUD",
    "DXVK_FRAME_RATE",
    "__GL_THREADED_OPTIMIZATIONS"
  ]
}
```

### JSON Schema for registry_allowlist.json
```json
{
  "schema_version": 1,
  "allowed_prefixes": [
    "HKEY_CURRENT_USER\\Software\\Wine",
    "HKEY_CURRENT_USER\\Software\\",
    "HKEY_LOCAL_MACHINE\\Software\\Wine",
    "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\DirectX"
  ]
}
```

### JSON Schema for tool_schemas.json
```json
{
  "schema_version": 1,
  "schemas": {
    "inspect_game": {
      "type": "object",
      "properties": {},
      "required": []
    },
    "set_environment": {
      "type": "object",
      "properties": {
        "key": { "type": "string", "description": "Environment variable name" },
        "value": { "type": "string", "description": "Environment variable value" }
      },
      "required": ["key", "value"]
    }
  }
}
```

### system_prompt.md Frontmatter
```markdown
---
schema_version: 1
---
You are a Wine compatibility expert for macOS. Your job is to get a Windows game running via Wine on macOS.

## Research Minimum (before first real launch)
...
```

### PolicyResources — Minimal Viable Loader Shape
```swift
// Source: CONTEXT.md + Phase 38 WikiService pattern
struct PolicyResources {
    // Typed accessor fields
    let systemPrompt: String
    let engineDefinitions: [EngineDefinition]
    let dllRegistry: [KnownDLL]
    let envAllowlist: Set<String>
    let registryAllowlist: [String]
    let toolSchemas: [String: JSONValue]

    static let shared: PolicyResources = {
        do { return try PolicyResources() }
        catch { fatalError("PolicyResources: \(error)") }
    }()

    private init() throws {
        // Load system_prompt.md with frontmatter version check
        // Load each .json with schema_version check
        // Assign to let properties
    }
}
```

### AgentToolCall Struct
```swift
// Models/AgentToolCall.swift (or appended to AIModels.swift)
struct AgentToolCall {
    let id: String       // opaque — Anthropic: tool_use_id, OpenAI-compat: tool_call_id
    let name: String     // e.g. "set_environment"
    let input: JSONValue // parsed arguments
}
```

### Updated AgentLoopProviderResponse
```swift
// Replace tuple array with named struct
struct AgentLoopProviderResponse {
    // ...existing fields...
    let toolCalls: [AgentToolCall]  // was [(id: String, name: String, input: JSONValue)]
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 270-line Swift string literal for system prompt | `system_prompt.md` in Resources/policy/ | Phase 43 | Reviewable diffs, content editable without recompile |
| `static let allowedEnvKeys: Set<String>` in Swift | `env_allowlist.json` loaded at startup | Phase 43 | Auditable policy file, schema versioned |
| `static let registry: [KnownDLL]` in Swift array | `engine_dll_registry.json` | Phase 43 | New DLL entries don't require Swift changes |
| `static let engines: [EngineDefinition]` in Swift | `engines.json` | Phase 43 | Same |
| Inline `JSONValue` schema in AgentToolName metadata | `tool_schemas.json` | Phase 43 | Single source for schema edits |
| Anonymous tuple `(id: String, name: String, input: JSONValue)` for tool calls | `struct AgentToolCall` | Phase 43 | Named, testable, matches CONTEXT.md canonical shape |
| DeepSeek/Kimi tool-call translation (tuples already parsed) | Same + `AgentToolCall` struct | Phase 43 | Type-safe, adapter tests validate encode/decode round-trip |

**Already in good shape (no change):**
- `appendToolResults` in all three adapters: already correct for Anthropic (`tool_result` blocks) and OpenAI-compat (`tool` role messages)
- `translateDeepseekResponse` / `translateKimiResponse`: already parse `tool_calls` correctly (no JSON-in-text fallback exists to remove)

---

## Open Questions

1. **Does `DLLPlacementTarget` need to become a String raw-value enum for Codable?**
   - What we know: `DLLPlacementTarget` is used as a field in `KnownDLL`, which must become `Codable` for `engine_dll_registry.json` loading.
   - What's unclear: The current definition of `DLLPlacementTarget` (not checked in research — it appears in `KnownDLLRegistry.swift` and `WineActionExecutor.swift`).
   - Recommendation: Check during planning. If it's already a `String` enum, add `Codable`. If it's `Int`, switch to `String` raw values with explicit cases.

2. **Is there a `winetricks_allowlist` policy file?**
   - What we know: `AgentTools.agentValidWinetricksVerbs` exists at `AgentTools.swift:209`. `AIService.validWinetricksVerbs` also exists at `AIService.swift:1408` — these appear to be duplicates (one public, one private).
   - What's unclear: CONTEXT.md doesn't list a `winetricks_allowlist.json` file. The locked resource list is six files.
   - Recommendation: Leave winetricks allowlist as Swift for now (it's used in logic, not just policy lookup). If it appears in planning review as an omission, add a seventh file.

3. **Migration ordering for EngineRegistry.swift and KnownDLLRegistry.swift**
   - What we know: Data moves to JSON, but Swift detection algorithms stay in Swift. The Swift files become loaders of the JSON data rather than holders of static arrays.
   - What's unclear: Whether `EngineRegistry.engines` becomes a computed property backed by `PolicyResources.shared.engineDefinitions` or remains a `static let` that is assigned once from the loader.
   - Recommendation: During planning, make `EngineRegistry.engines` and `KnownDLLRegistry.registry` computed properties that delegate to `PolicyResources.shared`. This avoids touching every call site.

4. **Bundle.module subdirectory lookup behavior (SPM version sensitivity)**
   - What we know: Phase 38's `WikiService.fetchContext` uses `Bundle.module.url(forResource:withExtension:)` for wiki files. The exact path lookup format used there is the proven pattern.
   - What's unclear: Whether `"policy/system_prompt"` is the correct resource name or whether it needs to be `"Resources/policy/system_prompt"`.
   - Recommendation: During P01 implementation, write a `PolicyResourcesTests.swift` test that calls `Bundle.module.url(forResource: "policy/system_prompt", withExtension: "md")` and asserts non-nil. Run it first.

---

## Sources

### Primary (HIGH confidence)
- Existing codebase — `Sources/cellar/Core/Providers/{Anthropic,Deepseek,Kimi}Adapter.swift` directly examined
- Existing codebase — `Sources/cellar/Models/KnownDLLRegistry.swift`, `Sources/cellar/Models/EngineRegistry.swift` directly examined
- Existing codebase — `Sources/cellar/Core/AIService.swift` lines 673-941 (agent system prompt) directly examined
- Existing codebase — `Sources/cellar/Core/Tools/ConfigTools.swift` lines 1-80 (`allowedEnvKeys`, registry prefixes) directly examined
- Existing codebase — `Sources/cellar/Core/AgentToolName.swift` (Phase 42 output — inline schemas) directly examined
- Existing codebase — `Package.swift` (`.copy("Resources")` bundling, no YAML dep) directly examined
- `43-CONTEXT.md` — all locked decisions and discretion areas

### Secondary (MEDIUM confidence)
- Phase 38 wiki pattern (`WikiService.fetchContext`, `Bundle.module.url`) — verified as existing shipping path for bundled SPM resources
- `Tests/cellarTests/AgentToolDefinitionTests.swift` — confirmed `swift-testing` framework and testing patterns in use

### Tertiary (LOW confidence)
- SPM `Bundle.module` subdirectory path behavior — confirmed by Phase 38 wiki pattern but the exact resource name format for `policy/` subdirectory needs a unit test to confirm.

---

## Metadata

**Confidence breakdown:**
- Policy extraction (resource layout, loader shape): HIGH — exact data is in the codebase, SPM pattern proven in Phase 38
- AgentToolCall struct + adapter update: HIGH — current code already parses tool calls correctly; adding named struct is mechanical
- JSON schema design: HIGH — data structures are known (directly read from Swift source)
- Bundle.module subdirectory path format: MEDIUM — proven by Phase 38 but exact path format needs a quick smoke test

**Research date:** 2026-05-03
**Valid until:** 2026-06-03 (stable domain — SPM resource bundling and wire protocol shapes don't change frequently)

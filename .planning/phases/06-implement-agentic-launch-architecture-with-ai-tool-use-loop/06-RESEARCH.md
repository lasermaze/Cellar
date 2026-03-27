# Phase 6: Implement Agentic Launch Architecture with AI Tool-Use Loop - Research

**Researched:** 2026-03-27
**Domain:** Anthropic tool-use API, Swift Codable JSON, agentic loop state machine
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Architecture**
- Replace hardcoded `LaunchCommand.run()` pipeline with ~50-line agent loop calling `AIService.runAgentLoop()`
- AI drives the entire process via tool-use API — no fixed escalation levels
- Agent loop: send messages → execute tools → send results → repeat until `end_turn` or max iterations
- Graceful degradation: if no API key, fall back to recipe-only launch (no agent)

**API Types**
- Add `JSONValue` recursive Codable enum for arbitrary JSON (tool schemas)
- Add `MessageContent` — either plain string or array of content blocks
- Add `ContentBlock` — tagged union: `.text(String)`, `.toolUse(id, name, input)`, `.toolResult(toolUseId, content, isError)`
- Add `ToolDefinition` — `name`, `description`, `inputSchema: JSONValue`
- Extend request/response types with `tools` array, `stopReason`, and `ContentBlock` array

**Diagnostic Tools (read-only, safe)**
- `inspect_game` — exe type, imports, game files, bottle state, installed DLLs, recipe
- `read_log` — Wine launch log (last 8000 chars stderr)
- `read_registry` — read Wine registry values from user.reg/system.reg files directly
- `ask_user` — ask user questions with optional multiple-choice options

**Action Tools (modify state)**
- `set_environment` — accumulate Wine env vars for next launch
- `set_registry` — write Wine registry values
- `install_winetricks` — install winetricks verb (validated against allowlist, 5-min timeout)
- `place_dll` — download and place known DLL from KnownDLLRegistry only

**Execution Tools**
- `launch_game` — run Wine process with accumulated environment, return structured result
- `save_recipe` — persist working configuration as recipe file

**System Prompt** — Wine compatibility expert persona, methodical workflow baked in, max 8 launch attempts

**Guardrails**
- Max iterations: 20 tool calls
- Max launches: 8 game launches per session
- Winetricks allowlist: only known-safe verbs
- DLL allowlist: only KnownDLLRegistry entries
- Sandbox: all file operations restricted to game bottle + ~/.cellar/

**Code Reuse** — all existing infrastructure (WineProcess, WineActionExecutor, DLLDownloader, WinetricksRunner, RecipeEngine, WineErrorParser, CellarStore, BottleManager, ValidationPrompt) becomes tool implementations

### Claude's Discretion
- Internal code organization (separate file per tool vs grouped)
- Error handling strategy within tool implementations
- Exact streaming/terminal output approach during agent loop
- How to structure the agent loop state machine
- Whether to keep WineErrorParser as enrichment or let agent reason from raw stderr
- Token/cost optimization strategies

### Deferred Ideas (OUT OF SCOPE)
- Model selection per game complexity (sonnet for simple games, opus for complex)
- TUI improvements (deferred to v2 per existing project decision)
</user_constraints>

---

## Summary

Phase 6 replaces the ~500-line hardcoded `LaunchCommand.run()` pipeline with a ~50-line agent loop backed by the Anthropic tool-use API. The existing infrastructure (WineProcess, WineActionExecutor, DLLDownloader, WinetricksRunner, RecipeEngine, CellarStore, BottleManager) is preserved entirely — it becomes tool implementations rather than pipeline stages. The core new work is: (1) Swift Codable types for the tool-use API contract, (2) an `AgentLoop` that drives the send→execute→return cycle, (3) 10 tool functions wiring new and existing code, and (4) a refactored `LaunchCommand.run()` that gathers context, builds a system prompt, and hands off to the agent.

The Anthropic tool-use API is well-documented and follows a clean contract: tools are JSON Schema objects in a `tools` array, responses include `tool_use` content blocks when `stop_reason == "tool_use"`, and tool results are sent back as `tool_result` blocks in the next `user` message. The main Swift engineering challenge is modeling this heterogeneous JSON (arbitrary tool inputs, mixed content block arrays) within Swift's Codable type system using a recursive `JSONValue` enum and a tagged `ContentBlock` enum.

The project already has a proven pattern for synchronous Anthropic API calls (URLSession + DispatchSemaphore + ResultBox @unchecked Sendable). The agent loop extends this pattern with a mutable message history array that grows each iteration. No new dependencies are needed — all tool implementations compose existing code.

**Primary recommendation:** Build in this order: JSONValue + new API types → AgentLoop core → 10 tool functions → refactored LaunchCommand. Keep tools in a single `AgentTools.swift` file grouped by category (diagnostic/action/execution), keep AgentLoop in `AgentLoop.swift`, and keep new API types as additions to the existing `AIModels.swift`.

---

## Standard Stack

### Core
| Component | Version/Source | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| Anthropic Messages API | `anthropic-version: 2023-06-01` | Tool-use loop via HTTP | Already used in `AIService.swift` |
| Swift Codable | Built-in (Swift 5.9+) | Serialize/deserialize heterogeneous JSON | Project already uses it throughout |
| Foundation (URLSession, Process) | Built-in | HTTP calls + subprocess execution | Established pattern in project |

### No New Dependencies
This phase introduces zero new Swift packages. All new code is pure Swift using Foundation.

---

## Architecture Patterns

### Recommended File Structure

```
Sources/cellar/
├── Core/
│   ├── AgentLoop.swift          # NEW: the agent loop state machine
│   ├── AgentTools.swift         # NEW: all 10 tool implementations
│   ├── AIService.swift          # MODIFIED: add runAgentLoop(), remove old variant/diagnose calls
│   ├── WineActionExecutor.swift # UNCHANGED: powers set_environment, set_registry, place_dll, install_winetricks
│   ├── WineProcess.swift        # UNCHANGED: powers launch_game
│   ├── WinetricksRunner.swift   # UNCHANGED: powers install_winetricks
│   ├── DLLDownloader.swift      # UNCHANGED: powers place_dll
│   ├── RecipeEngine.swift       # UNCHANGED: powers save_recipe, inspect_game
│   ├── BottleManager.swift      # UNCHANGED: powers inspect_game
│   └── ValidationPrompt.swift  # DELETED (replaced by ask_user tool)
├── Models/
│   └── AIModels.swift           # MODIFIED: add JSONValue, new ContentBlock, ToolDefinition, updated request/response types
└── Commands/
    └── LaunchCommand.swift      # REPLACED: ~50-line agent loop replacing ~500-line pipeline
```

---

### Pattern 1: JSONValue Recursive Enum (HIGH confidence)

**What:** A recursive `indirect enum` that can represent any JSON value. Required because tool `input_schema` is JSON Schema (arbitrary structure), and tool `input` in responses is also arbitrary JSON.

**Why it's needed:** Swift's `Codable` requires known types at compile time. Tool inputs are arbitrary objects defined by each tool's schema — a `JSONValue` enum is the standard Swift pattern for this.

```swift
// AIModels.swift addition
indirect enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.typeMismatch(JSONValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown JSON type"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}
```

**Helper to extract tool input fields:**
```swift
extension JSONValue {
    var asString: String? { if case .string(let v) = self { return v }; return nil }
    var asBool: Bool? { if case .bool(let v) = self { return v }; return nil }
    var asObject: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }; return nil
    }
}
```

---

### Pattern 2: ContentBlock Tagged Union (HIGH confidence — from official docs)

**What:** Represents the mixed content blocks in Anthropic responses. A response may contain `text` blocks and `tool_use` blocks together. Tool results are `tool_result` blocks sent in user messages.

**API-verified field names (from official docs):**
- Response `tool_use` block: `type`, `id`, `name`, `input` (as JSONValue/object)
- User `tool_result` block: `type: "tool_result"`, `tool_use_id`, `content` (string or array), `is_error` (optional bool)

```swift
// Replace existing AnthropicResponse.ContentBlock in AIModels.swift
enum ContentBlock: Codable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String, content: String, isError: Bool)

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "tool_use":
            self = .toolUse(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                input: try container.decode(JSONValue.self, forKey: .input)
            )
        case "tool_result":
            self = .toolResult(
                toolUseId: try container.decode(String.self, forKey: .toolUseId),
                content: try container.decode(String.self, forKey: .content),
                isError: (try? container.decode(Bool.self, forKey: .isError)) ?? false
            )
        default:
            self = .text("") // ignore unknown block types gracefully
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let v):
            try container.encode("text", forKey: .type)
            try container.encode(v, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
            if isError { try container.encode(isError, forKey: .isError) }
        }
    }
}
```

---

### Pattern 3: MessageContent (Polymorphic) (HIGH confidence)

**What:** Anthropic's `content` field can be either a plain `String` (for simple user messages) or an array of `ContentBlock` objects (for tool results and mixed content). The request type needs to send both forms.

```swift
enum MessageContent: Codable {
    case text(String)
    case blocks([ContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .text(s); return }
        self = .blocks(try container.decode([ContentBlock].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let v): try container.encode(v)
        case .blocks(let v): try container.encode(v)
        }
    }
}
```

---

### Pattern 4: Updated AnthropicRequest with Tools (HIGH confidence)

```swift
struct AnthropicToolRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [Message]
    let tools: [ToolDefinition]?

    struct Message: Encodable {
        let role: String
        let content: MessageContent
    }

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools
        case maxTokens = "max_tokens"
    }
}

struct ToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONValue  // Must be JSON Schema object: {"type":"object","properties":{...},"required":[...]}

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct AnthropicToolResponse: Decodable {
    let content: [ContentBlock]
    let stopReason: String

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}
```

---

### Pattern 5: AgentLoop State Machine (MEDIUM confidence — design choice)

**What:** A struct or class that holds mutable conversation history and drives the send→execute→return loop.

**Key design points:**
- Message history grows each iteration: append assistant response, then append user message with tool_result blocks
- **CRITICAL (from official docs):** Tool result blocks MUST come FIRST in the content array of the user message. Text must come AFTER all tool_results.
- Loop exits on `stopReason == "end_turn"` or iteration count >= 20
- Launch count tracked separately from iteration count (max 8 launches)

```swift
struct AgentLoop {
    let apiKey: String
    let tools: [ToolDefinition]
    let toolExecutor: (String, JSONValue) -> String  // (toolName, input) -> result string
    let systemPrompt: String
    let maxIterations: Int = 20

    // Mutable state
    private var messages: [AnthropicToolRequest.Message] = []
    private var iterationCount = 0

    mutating func run(initialMessage: String) throws -> String {
        messages.append(.init(role: "user", content: .text(initialMessage)))

        while iterationCount < maxIterations {
            iterationCount += 1
            let response = try callAPI()

            // Collect any text blocks to return as final response
            let texts = response.content.compactMap { block -> String? in
                if case .text(let t) = block { return t }; return nil
            }

            if response.stopReason == "end_turn" {
                return texts.joined(separator: "\n")
            }

            guard response.stopReason == "tool_use" else {
                return texts.joined(separator: "\n")
            }

            // Append assistant turn to history
            messages.append(.init(role: "assistant", content: .blocks(response.content)))

            // Execute all tool_use blocks and collect tool_result blocks
            var resultBlocks: [ContentBlock] = []
            for block in response.content {
                guard case .toolUse(let id, let name, let input) = block else { continue }
                let result = toolExecutor(name, input)
                resultBlocks.append(.toolResult(toolUseId: id, content: result, isError: false))
            }

            // tool_result blocks MUST be first in content array (API requirement)
            messages.append(.init(role: "user", content: .blocks(resultBlocks)))
        }

        return "Agent reached max iterations (\(maxIterations))."
    }
}
```

---

### Pattern 6: Tool Schema Construction (HIGH confidence)

Each of the 10 tools needs a `ToolDefinition` with a `JSONValue` input schema. Use the object literal syntax:

```swift
ToolDefinition(
    name: "inspect_game",
    description: "Get game metadata without launching: exe type (PE32/PE32+), DLL imports, game files, bottle state, installed DLLs, and recipe. Call this first to understand the game before attempting configuration.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "game_id": .object(["type": .string("string"), "description": .string("The game ID")])
        ]),
        "required": .array([.string("game_id")])
    ])
)
```

---

### Pattern 7: Tool Executor Switch (recommended design)

The `toolExecutor` closure in AgentLoop delegates to `AgentTools`. Keep all 10 tool implementations in `AgentTools.swift`:

```swift
struct AgentTools {
    // Injected dependencies
    let gameId: String
    let entry: GameEntry
    let bottleURL: URL
    let wineURL: URL
    let wineProcess: WineProcess
    let executor: WineActionExecutor
    var accumulatedEnv: [String: String] = [:]  // set_environment accumulates here
    var launchCount = 0
    let maxLaunches = 8

    func execute(toolName: String, input: JSONValue) -> String {
        switch toolName {
        case "inspect_game":    return inspectGame(input: input)
        case "read_log":        return readLog(input: input)
        case "read_registry":   return readRegistry(input: input)
        case "ask_user":        return askUser(input: input)
        case "set_environment": return setEnvironment(input: input)
        case "set_registry":    return setRegistry(input: input)
        case "install_winetricks": return installWinetricks(input: input)
        case "place_dll":       return placeDLL(input: input)
        case "launch_game":     return launchGame(input: input)
        case "save_recipe":     return saveRecipe(input: input)
        default:                return "Error: Unknown tool '\(toolName)'"
        }
    }
}
```

Note: `AgentTools` needs `mutating` functions (or use a class) because `accumulatedEnv` and `launchCount` are mutable state.

---

### Pattern 8: Tool Return Format

All tools return a JSON string. The agent loop passes this directly as the `tool_result` content string. Use a simple helper:

```swift
private func jsonResult(_ dict: [String: Any]) -> String {
    (try? String(data: JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]), encoding: .utf8)) ?? "{}"
}
```

---

### Anti-Patterns to Avoid

- **Putting text before tool_result in user messages:** The Anthropic API returns a 400 error if any text content block appears before tool_result blocks in the same user message. Always put tool_result blocks FIRST.
- **Reusing AnthropicRequest for tool-use calls:** The existing `AnthropicRequest` has `content: String` for messages. Tool-use requires `MessageContent` (string or array). Create `AnthropicToolRequest` separately rather than forcing the existing type.
- **Parsing tool input as Codable struct:** Tool inputs arrive as `JSONValue`. Extract fields with subscript/`asString`/`asObject` helpers — don't try to decode into a specific struct (that would require knowing types at compile time for each tool).
- **Sharing `WineActionExecutor.execute()` signature:** The existing `execute()` takes `inout envConfigs` and `configIndex` — not compatible with the agent loop's `accumulatedEnv` design. Tool implementations in `AgentTools` should call the underlying operations directly (WinetricksRunner, DLLDownloader, wineProcess.applyRegistryFile) rather than through the old executor signature.
- **Accumulating env vars via WineActionExecutor.setEnvVar:** In the old pipeline, `setEnvVar` mutated `envConfigs[configIndex].environment`. In the agent loop, `set_environment` should accumulate into `AgentTools.accumulatedEnv` — a flat dict passed to `launch_game`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Wine process execution | Custom subprocess wrapper | `WineProcess.run()` | Already handles stderr capture, timeout, log writing, SIGINT |
| Registry edits | Direct file writes | `wineProcess.applyRegistryFile()` / `WineActionExecutor.setRegistry` | Handles temp file creation, wine regedit invocation |
| Winetricks install | Shell subprocess | `WinetricksRunner.install(verb:)` | Already has 5-min timeout, -q flag, output monitoring |
| DLL download + place | URL downloads | `DLLDownloader.downloadAndCache()` + `.place()` | Already has caching, requiredOverrides application |
| API HTTP call | New URLSession wrapper | Extend `AIService.callAPI()` | Already has semaphore pattern, ResultBox Sendable fix |
| Recipe load/save | JSON file I/O | `RecipeEngine.findBundledRecipe()` + `.saveUserRecipe()` | Already handles paths, encoding |
| Exe inspection | Custom binary parser | Shell `file` command via `Process` | `file` is always available on macOS, handles PE32/PE32+ detection |
| Registry reading | Custom .reg parser | Direct file read of user.reg/system.reg | Wine registry files are plain text — simple line parsing |

**Key insight:** The entire existing infrastructure is a perfect set of building blocks. The agent loop is essentially a thin orchestration layer over code that already exists.

---

## Common Pitfalls

### Pitfall 1: tool_result content ordering in user message
**What goes wrong:** API returns HTTP 400 with "tool_use ids were found without tool_result blocks immediately after"
**Why it happens:** The Anthropic API strictly requires tool_result blocks to appear FIRST in a user message's content array. Any text block before them triggers a 400.
**How to avoid:** In the agent loop, when building the user message after tool execution, put tool_result blocks first, then any additional text (there usually won't be any).
**Warning signs:** HTTP 400 error in agent loop after first tool call.

### Pitfall 2: Double-encoding JSONValue in tool input_schema
**What goes wrong:** Tool schema arrives as a JSON string rather than a JSON object, causing "tools[0].input_schema must be an object" API error.
**Why it happens:** If `JSONValue` is encoded to a string wrapper instead of directly as JSON, the API sees a string where it expects an object.
**How to avoid:** Verify `JSONValue.encode()` uses `singleValueContainer` and directly encodes without wrapping. Test by encoding a sample ToolDefinition and checking the output.
**Warning signs:** API returns 400 "invalid tool definition" immediately on first request.

### Pitfall 3: Mutable AgentTools state with closure capture
**What goes wrong:** Swift 6 Sendable error when `toolExecutor` closure captures mutable `AgentTools` state (accumulatedEnv, launchCount).
**Why it happens:** The existing codebase is Swift 6 strict. Closures capturing `inout` or mutable vars in concurrent contexts hit Sendable restrictions.
**How to avoid:** Make `AgentTools` a `class` (reference type) rather than a `struct`, or pass it as `inout` explicitly. Alternatively, use the existing `@unchecked Sendable` class wrapper pattern (already used in `WineProcess.StderrCapture`, `OutputMonitor`, `ResultBox`).
**Warning signs:** Swift 6 compile error about mutable captured variable.

### Pitfall 4: WineActionExecutor signature mismatch
**What goes wrong:** Trying to call `WineActionExecutor.execute()` from AgentTools hits a type error because it takes `inout [(description: String, environment: [String: String], actions: [WineFix])]` and `configIndex` — incompatible with the agent loop's flat `accumulatedEnv`.
**Why it happens:** The old executor was designed for the retry variant loop, not the agent loop.
**How to avoid:** In AgentTools tool implementations, call the underlying primitives directly (WinetricksRunner, DLLDownloader, wineProcess.applyRegistryFile) rather than through the old WineActionExecutor. The executor can be retired or kept for LaunchCommand fallback path.
**Warning signs:** Compile error trying to call executor.execute() from an AgentTools method.

### Pitfall 5: Agent loop with no max_tokens headroom
**What goes wrong:** Agent loop gets stuck in a partial tool_use response that's cut off mid-JSON because `max_tokens` was too low.
**Why it happens:** Each iteration generates tool_use blocks plus any text. Tool inputs can be verbose (e.g., inspect_game output). Using 1024 tokens (current AIService default) can truncate.
**How to avoid:** Set `max_tokens: 4096` for agent loop calls. Tool outputs should be kept compact (JSON, not prose) but the model's reasoning can be verbose.
**Warning signs:** `stop_reason: "max_tokens"` in responses, incomplete JSON in tool_use blocks.

### Pitfall 6: inspect_game `file` command path on macOS
**What goes wrong:** `file` command not found or returns unexpected format when run via `Process`.
**Why it happens:** `Process` does not inherit shell PATH. `/usr/bin/file` is always present on macOS; use the full path.
**How to avoid:** Use `URL(fileURLWithPath: "/usr/bin/file")` as executable URL. Parse output for "PE32+" vs "PE32" to detect 64-bit vs 32-bit.
**Warning signs:** "No such file or directory" or empty output from inspect_game.

### Pitfall 7: Registry file direct read (user.reg/system.reg)
**What goes wrong:** Registry files use a Windows-1252 or UTF-16 encoding that `String(contentsOf:encoding:.utf8)` can't read.
**Why it happens:** Wine's registry files are text-based but may have non-UTF8 encoding.
**How to avoid:** Try UTF-8 first, fall back to `.windowsCP1252` or `.utf16`. Return the raw lines matching the requested key path. Simple substring search is sufficient — no full .reg parser needed.
**Warning signs:** `read_registry` returns empty or throws on first use.

### Pitfall 8: Graceful degradation path remains functional
**What goes wrong:** Removing the old LaunchCommand pipeline breaks the no-API-key path.
**Why it happens:** The refactored LaunchCommand hands off to `AIService.runAgentLoop()` which returns `.unavailable` when no key is set — but the fallback path (recipe-only launch) still needs to work.
**How to avoid:** Keep a minimal recipe-only launch path in LaunchCommand that runs once without AI involvement when `detectProvider()` returns `.unavailable`. This is simpler than the old 500-line loop — just apply recipe, launch once, ask user if it worked.
**Warning signs:** `cellar launch` crashes or errors when ANTHROPIC_API_KEY is not set.

---

## Code Examples

### Building tool definitions from static constants

```swift
// AgentTools.swift — tool definitions as a static property
static let toolDefinitions: [ToolDefinition] = [
    ToolDefinition(
        name: "inspect_game",
        description: """
            Get complete game metadata without launching. Returns exe type (PE32 for 32-bit, \
            PE32+ for 64-bit), DLL imports list, game directory file listing, whether the \
            bottle exists, list of DLLs already installed in the bottle, and the current \
            recipe if one exists. Call this first to understand the game before configuring.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "game_id": .object(["type": .string("string"), "description": .string("Game identifier")])
            ]),
            "required": .array([.string("game_id")])
        ])
    ),
    // ... other tools
]
```

### Refactored LaunchCommand.run() (target ~50 lines)

```swift
mutating func run() throws {
    // 1. Dependency check
    let status = DependencyChecker().checkAll()
    guard status.allRequired, let wineURL = status.wine else {
        print("Error: Wine is not installed. Run `cellar` first.")
        throw ExitCode.failure
    }

    // 2. Find game
    guard let entry = try CellarStore.findGame(id: game) else {
        print("Game not found. Run `cellar add /path/to/installer` first.")
        throw ExitCode.failure
    }

    guard BottleManager(wineBinary: wineURL).bottleExists(gameId: game) else {
        print("Error: Bottle for '\(game)' not found.")
        throw ExitCode.failure
    }

    // 3. Try agent loop (requires API key)
    switch AIService.runAgentLoop(gameId: game, entry: entry, wineURL: wineURL) {
    case .success:
        return
    case .unavailable:
        // Fall back to recipe-only launch
        try recipeLaunch(entry: entry, wineURL: wineURL)
    case .failed(let msg):
        print("Agent failed: \(msg)")
        throw ExitCode.failure
    }
}
```

### ask_user tool implementation

```swift
// Replaces ValidationPrompt — agent calls this when it needs user input
private func askUser(input: JSONValue) -> String {
    guard let question = input["question"]?.asString else {
        return jsonResult(["error": "Missing 'question' parameter"])
    }
    if let options = input["options"], case .array(let opts) = options {
        let optStrings = opts.compactMap { $0.asString }
        print("\n\(question)")
        for (i, opt) in optStrings.enumerated() {
            print("  \(i + 1). \(opt)")
        }
        print("Enter number: ", terminator: "")
    } else {
        print("\n\(question) ", terminator: "")
    }
    fflush(stdout)
    let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return jsonResult(["answer": answer])
}
```

### launch_game tool with accumulated env

```swift
mutating private func launchGame(input: JSONValue) -> String {
    guard launchCount < maxLaunches else {
        return jsonResult(["error": "Max launches (\(maxLaunches)) reached"])
    }
    launchCount += 1

    let extraDebug = input["extra_winedebug"]?.asString

    // Merge accumulated env with optional extra_winedebug
    var env = accumulatedEnv
    if let debug = extraDebug {
        let existing = env["WINEDEBUG"] ?? ""
        env["WINEDEBUG"] = existing.isEmpty ? debug : "\(existing),\(debug)"
    }

    let timestamp = Date()
    let logFile = CellarPaths.logFile(for: gameId, timestamp: timestamp)

    do {
        let result = try wineProcess.run(
            binary: executablePath,
            arguments: [],
            environment: env,
            logFile: logFile
        )
        let errors = WineErrorParser.parse(result.stderr)
        let detectedErrors = errors.map { e -> [String: Any] in
            var dict: [String: Any] = ["category": "\(e.category)", "detail": e.detail]
            if let fix = e.suggestedFix { dict["suggested_fix"] = "\(fix)" }
            return dict
        }
        return jsonResult([
            "exit_code": result.exitCode,
            "elapsed_seconds": result.elapsed,
            "timed_out": result.timedOut,
            "stderr_tail": String(result.stderr.suffix(4000)),
            "detected_errors": detectedErrors
        ])
    } catch {
        return jsonResult(["error": error.localizedDescription])
    }
}
```

---

## Existing Code Inventory (What to Reuse)

| Existing Component | Used By | Notes |
|-------------------|---------|-------|
| `WineProcess.run()` | `launch_game` tool | Unchanged — already handles log, timeout, stderr capture |
| `WineProcess.applyRegistryFile()` | `set_registry` tool | Unchanged |
| `WinetricksRunner.install(verb:)` | `install_winetricks` tool | Unchanged — has 5-min timeout already |
| `DLLDownloader.downloadAndCache()` + `.place()` | `place_dll` tool | Unchanged |
| `KnownDLLRegistry.find(name:)` | `place_dll` tool | Unchanged — validates DLL is known |
| `RecipeEngine.findBundledRecipe(for:)` | `inspect_game` tool, graceful degradation | Unchanged |
| `RecipeEngine.saveUserRecipe(_:)` | `save_recipe` tool | Unchanged |
| `RecipeEngine.apply(recipe:wineProcess:)` | Graceful degradation only | Unchanged |
| `CellarStore.findGame(id:)` | `inspect_game` tool, LaunchCommand | Unchanged |
| `BottleManager.bottleExists(gameId:)` | `inspect_game` tool, LaunchCommand | Unchanged |
| `WineErrorParser.parse(_:)` | `launch_game` tool (enriches output) | Unchanged — optional enrichment |
| `AIService.callAPI(request:)` | Agent loop HTTP call | Unchanged — reuse private method |
| `AIService.detectProvider()` | Agent loop provider check | Unchanged |
| `AIService.validWinetricksVerbs` | `install_winetricks` tool | Unchanged — still need verb validation |
| `ValidationPrompt` | — | RETIRED — replaced by `ask_user` tool |

---

## New Types Summary

All new types added to `AIModels.swift`:

| Type | Kind | Purpose |
|------|------|---------|
| `JSONValue` | indirect enum | Recursive Codable for arbitrary JSON (tool schemas, tool inputs) |
| `MessageContent` | enum | Polymorphic message content: string or [ContentBlock] |
| `ContentBlock` (new, replaces existing) | enum | Tagged union: .text, .toolUse(id,name,input), .toolResult(id,content,isError) |
| `ToolDefinition` | struct | name + description + inputSchema: JSONValue |
| `AnthropicToolRequest` | struct | Messages API request with tools array and MessageContent messages |
| `AnthropicToolResponse` | struct | Messages API response with ContentBlock array and stopReason |

Note: The existing `AnthropicResponse.ContentBlock` is a simple struct used only for plain text responses. The new `ContentBlock` enum replaces it. The existing `AnthropicRequest` struct (plain string content) stays for the graceful degradation path if needed — or can be replaced entirely with the new types since `MessageContent` handles both cases.

---

## Validation Architecture

> `workflow.nyquist_validation` is not present in `.planning/config.json` — only `workflow.research`, `workflow.plan_check`, `workflow.verifier` are set. Treating as `false` — Validation Architecture section skipped.

---

## Open Questions

1. **Where does `executablePath` come from in AgentTools?**
   - What we know: `GameEntry.executablePath` is stored during `cellar add`. The old LaunchCommand had a fallback for legacy entries without it.
   - What's unclear: Does AgentTools receive executablePath directly, or does it look it up from the entry?
   - Recommendation: Pass `executablePath: String` into AgentTools constructor. Compute it in LaunchCommand (same logic as current LaunchCommand step 6) before constructing AgentTools. Keeps tool implementations clean.

2. **Should WineActionExecutor be retained or retired?**
   - What we know: The old `execute()` signature is not compatible with AgentTools' flat accumulated env. The underlying operations (WinetricksRunner, DLLDownloader, registry) are called directly.
   - What's unclear: Is there value in keeping WineActionExecutor for the graceful degradation path?
   - Recommendation: Keep WineActionExecutor for now but don't use it in AgentTools. The graceful degradation path (recipe apply + single launch) doesn't need it either. Mark for cleanup in a future phase.

3. **Streaming progress output during agent loop**
   - What we know: Current AIService calls are silent during generation. The agent loop may run for 5-10 minutes (multiple winetricks installs, launches). User needs feedback.
   - What's unclear: Should the agent loop print tool calls as they happen? Print thinking text blocks?
   - Recommendation: Print each tool call name before execution (`print("→ \(toolName)...")`) and print any `.text` content blocks from assistant responses in real-time. This is simple and gives good UX without streaming the API response.

4. **max_tokens for agent loop calls**
   - What we know: Current AIService uses 1024. Tool-use calls need more headroom.
   - Recommendation: Use 4096 for agent loop calls. The system prompt + tool definitions add ~346 tokens overhead (per official pricing table for claude-opus-4-6).

---

## Sources

### Primary (HIGH confidence)
- `https://platform.claude.com/docs/en/agents-and-tools/tool-use/how-tool-use-works` — confirmed: agentic loop structure, stop_reason values ("tool_use", "end_turn"), client vs server tool distinction
- `https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools` — confirmed: exact tool definition structure (name/description/input_schema with JSON Schema), tool_choice options, content block format with id/name/input
- `https://platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls` — confirmed: tool_result block exact fields (tool_use_id/content/is_error), CRITICAL ordering requirement (tool_result blocks must be FIRST in user message), multi-turn message structure
- Existing codebase (`AIService.swift`, `AIModels.swift`, `WineProcess.swift`, `WineActionExecutor.swift`, etc.) — confirmed: all existing infrastructure is intact and reusable

### Secondary (MEDIUM confidence)
- N/A — all critical claims verified against official documentation

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; existing patterns verified in codebase
- Architecture: HIGH — API contract verified against official docs; tool patterns verified against existing code
- Pitfalls: HIGH for API pitfalls (verified in docs); MEDIUM for Swift implementation pitfalls (based on existing codebase patterns)

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (API contract is stable; Anthropic versioned APIs don't change without new anthropic-version header)

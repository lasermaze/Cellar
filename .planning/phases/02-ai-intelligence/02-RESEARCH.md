# Phase 02: AI Intelligence - Research

**Researched:** 2026-03-27
**Domain:** Swift HTTP clients, Anthropic Messages API, OpenAI Chat Completions API, prompt engineering
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Support both Claude and OpenAI — user's choice at config time
- Provider auto-detected from env var name: `ANTHROPIC_API_KEY` → Claude, `OPENAI_API_KEY` → OpenAI
- If both set, prefer Claude (no additional config needed)
- Use cheapest model tier that works: Claude Haiku / GPT-4o-mini
- No `CELLAR_AI_PROVIDER` env var needed — key name determines provider
- AI diagnosis shown inline during retry loop, before each retry attempt
- 2-3 sentence plain-English explanation: what Wine tried, why it failed, what Cellar will do
- AI only called when `WineErrorParser` can't diagnose (returns `.unknown` or no `suggestedFix`) — saves API calls
- AI can suggest any `WineFix` type (`installWinetricks`, `setEnvVar`, `setDLLOverride`) — retry loop auto-applies them
- `WineErrorParser` remains the first-pass, free, instant diagnosis layer
- Recipe generation trigger: `cellar add` with no bundled recipe → AI generates one
- Timing: after installer runs and files are installed (not before)
- Context sent to AI: game name (from installer filename) + scan of installed files (DLLs, configs, data formats)
- Generated recipe displayed with full transparency (same as bundled recipes)
- Auto-applied without asking for approval
- Auto-saved to `~/.cellar/recipes/` for reuse on next launch
- No API key: work without AI, show one-time tip on first run
- API call fails: retry 3 times, then fall back to `WineErrorParser` (for diagnosis) or defaults (for recipe)
- No bundled recipe AND AI unavailable: warn user and ask whether to continue with defaults

### Claude's Discretion

- Exact prompt engineering for diagnosis and recipe generation
- HTTP client choice for API calls (URLSession vs third-party)
- AI response parsing and validation strategy
- `~/.cellar/recipes/` directory structure
- How installed file scan works (which files to include, size limits for context)
- Retry backoff strategy (exponential, fixed, etc.)

### Deferred Ideas (OUT OF SCOPE)

- macOS Keychain storage for API keys (future phase)
- AI-powered game identification from EXE metadata and file hashes (GAME-03, v2)
- Confidence scoring on AI-generated recipes (RECIPE-05, v2)
- Recipe refinement loop (feed error back to AI for improved recipe)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| RECIPE-03 | AI generates a candidate recipe for games without a bundled recipe | AIService recipe generation method + RecipeEngine save-to-user-recipes support |
| LAUNCH-04 | AI interprets Wine crash logs and provides human-readable diagnosis | AIService diagnosis method + LaunchCommand retry loop integration |
</phase_requirements>

---

## Summary

This phase adds an `AIService` module that makes HTTP calls to either Anthropic's Messages API (Claude Haiku) or OpenAI's Chat Completions API (GPT-4o-mini), selected automatically by which env var is present. The service is consumed synchronously by `LaunchCommand` (diagnosis) and `AddCommand` (recipe generation), fitting into the existing `ParsableCommand` synchronous architecture without converting commands to `AsyncParsableCommand`.

Both provider APIs are simple JSON-over-HTTPS with `Authorization: Bearer` headers. No third-party HTTP library is needed — `URLSession.shared.data(for:)` with a `DispatchSemaphore` bridge (or a synchronous wrapper using `RunLoop`) keeps the implementation within the existing code pattern. Response parsing uses `Codable` structs. The key design challenge is prompt engineering: getting the AI to return structured `WineFix` JSON for diagnosis and a valid `Recipe` JSON for generation, without schema drift.

`RecipeEngine` needs one new method: `saveUserRecipe(_:)` that writes to `~/.cellar/recipes/{gameId}.json`, and `findBundledRecipe()` needs a new search pass for that directory (before the CWD fallback). `LaunchCommand`'s post-WineErrorParser branch needs a new step: if `errors` is empty or no `suggestedFix`, call `AIService.diagnose(wineResult:)`. `AddCommand` needs an AI recipe generation step after the post-install scan (step 10), before saving the `GameEntry`.

**Primary recommendation:** Build a single `AIService` struct with two public methods (`diagnose` and `generateRecipe`), each synchronous-blocking, backed by `URLSession` with `DispatchSemaphore`. Use structured JSON output in prompts to avoid fragile text parsing.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `Foundation.URLSession` | macOS 14 built-in | HTTP requests to AI APIs | Already in project; no new dependency; proven for CLI tools |
| `Foundation.JSONEncoder` / `JSONDecoder` | macOS 14 built-in | Serialize requests, deserialize responses | Codable already used throughout project |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `DispatchSemaphore` | Foundation built-in | Bridge async URLSession to sync ParsableCommand | Needed because commands are synchronous; URLSession.shared.data(for:) is async |
| `ProcessInfo.processInfo.environment` | Foundation built-in | Read API key env vars | Already used in project for WINEPREFIX etc. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `URLSession` + semaphore | `AsyncParsableCommand` | Switching all commands to async touches Cellar.swift + all commands; higher risk, no benefit here |
| `URLSession` + semaphore | `SwiftAnthropic` / `MacPaw/OpenAI` | Third-party packages add dependency weight for what is 30 lines of JSON |
| Direct JSON prompt parsing | Structured JSON output (`response_format`) | OpenAI supports `response_format: {type: "json_object"}`; Anthropic needs prompt instruction + validation |

**Installation:** No new packages needed.

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/cellar/
├── Core/
│   ├── AIService.swift          # NEW: provider abstraction, HTTP calls, response parsing
│   ├── RecipeEngine.swift       # MODIFIED: add saveUserRecipe() + user-recipes search pass
│   ├── WineErrorParser.swift    # unchanged
│   └── ...
├── Models/
│   ├── AIModels.swift           # NEW: Codable structs for API requests/responses
│   └── ...
├── Commands/
│   ├── LaunchCommand.swift      # MODIFIED: AI diagnosis branch after WineErrorParser
│   ├── AddCommand.swift         # MODIFIED: AI recipe generation after post-install scan
│   └── ...
```

`~/.cellar/recipes/` — user-generated recipe directory (created on first save)

### Pattern 1: Provider Auto-Detection

**What:** Check env vars in order; first found wins; prefer Claude if both present.
**When to use:** Every AIService method call.

```swift
// Source: ProcessInfo.processInfo.environment (Foundation, built-in)
enum AIProvider {
    case anthropic(apiKey: String)
    case openai(apiKey: String)
    case unavailable
}

static func detectProvider() -> AIProvider {
    let env = ProcessInfo.processInfo.environment
    if let key = env["ANTHROPIC_API_KEY"], !key.isEmpty {
        return .anthropic(apiKey: key)
    }
    if let key = env["OPENAI_API_KEY"], !key.isEmpty {
        return .openai(apiKey: key)
    }
    return .unavailable
}
```

### Pattern 2: Synchronous HTTP Call via DispatchSemaphore

**What:** Bridge `URLSession.shared.data(for:)` async method to a synchronous call, matching the `ParsableCommand.run() throws` context.
**When to use:** Every `AIService` call site.

```swift
// Source: DispatchSemaphore pattern, verified against Swift Forums concurrency discussion
func callAPI(request: URLRequest) throws -> Data {
    var result: Result<Data, Error> = .failure(URLError(.unknown))
    let semaphore = DispatchSemaphore(value: 0)

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            result = .failure(error)
        } else if let data = data {
            let httpResponse = response as? HTTPURLResponse
            if let code = httpResponse?.statusCode, code >= 400 {
                result = .failure(AIServiceError.httpError(statusCode: code))
            } else {
                result = .success(data)
            }
        }
        semaphore.signal()
    }.resume()

    semaphore.wait()
    return try result.get()
}
```

Note: Using `dataTask(with:completionHandler:)` rather than the `async` variant avoids the need to spin up a Task or change command signatures. This is the safest pattern for Swift 6 synchronous CLI contexts.

### Pattern 3: Structured JSON Response from AI

**What:** Ask the AI to return machine-parseable JSON by embedding the schema in the system prompt. Validate the response against expected keys before using it.
**When to use:** Both diagnosis and recipe generation.

For diagnosis, ask for:
```json
{
  "explanation": "2-3 sentence plain English",
  "fix_type": "installWinetricks|setEnvVar|setDLLOverride|none",
  "fix_arg1": "...",
  "fix_arg2": "..."
}
```

For recipe generation, ask for a full `Recipe` JSON matching the existing schema (embed the schema in the prompt).

### Pattern 4: Retry with Simple Delay

**What:** Retry API calls up to 3 times with a 1-second fixed delay between attempts.
**When to use:** Any `AIService` method that calls the network.

```swift
// Simple retry — no exponential backoff needed for 3 retries
func withRetry<T>(maxAttempts: Int = 3, work: () throws -> T) throws -> T {
    var lastError: Error = AIServiceError.unknown
    for attempt in 1...maxAttempts {
        do {
            return try work()
        } catch {
            lastError = error
            if attempt < maxAttempts {
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }
    throw lastError
}
```

### Pattern 5: User-Recipes Directory

**What:** `~/.cellar/recipes/` stores AI-generated recipes. `RecipeEngine.findBundledRecipe()` gains a new search pass for this directory, checked before the CWD fallback.
**When to use:** Any recipe lookup (load) and after AI generation (save).

```swift
// CellarPaths extension
static let userRecipesDir: URL = base.appendingPathComponent("recipes")

static func userRecipeFile(for gameId: String) -> URL {
    userRecipesDir.appendingPathComponent("\(gameId).json")
}
```

### Anti-Patterns to Avoid

- **Async command migration:** Don't convert `ParsableCommand` to `AsyncParsableCommand` just for AI calls. There is a known Swift 6 + ArgumentParser issue where `AsyncParsableCommand` shows only help text. The semaphore approach is safer and keeps changes local to `AIService`.
- **Streaming responses:** Don't use streaming (`stream: true`) for diagnosis or recipe generation. These are short single-turn calls; streaming adds complexity for no UX benefit in a CLI.
- **Trust AI output blindly:** Always validate that required JSON keys are present before constructing `WineFix` or `Recipe`. A malformed AI response should fall back gracefully, not crash.
- **Printing raw AI response:** Never print the raw JSON to the user. Always extract the `explanation` field and format it in the project's "a few lines per action" style.
- **Expensive scan for context:** Don't send the entire bottle to the AI. Filter to: game EXEs found, DLL files in game directory only (not Wine system dirs), and known config file types (`.ini`, `.cfg`, `.json`). Cap total file listing at 50 entries.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP requests | Custom TCP socket code | `URLSession.shared.dataTask` | URLSession handles TLS, redirects, timeouts correctly |
| JSON serialization | String interpolation for request body | `JSONEncoder` + `Codable` | Escaping, Unicode, special chars in game names cause subtle bugs |
| Provider routing | Complex config file system | Env var auto-detection | CONTEXT.md specifies this; zero user configuration needed |
| Retry logic | Complex circuit breaker | Simple `for` loop + `Thread.sleep` | 3 retries with 1s delay is sufficient; circuit breaker overkill for MVP |

**Key insight:** The AI API calls are 20-40 lines of Foundation code each. The value is in prompt engineering, not HTTP plumbing.

---

## Common Pitfalls

### Pitfall 1: AI Returns Invalid Recipe JSON

**What goes wrong:** The AI generates a recipe missing required `Codable` fields (e.g., `id`, `name`, `executable`), causing `JSONDecoder` to throw.
**Why it happens:** Large language models don't always follow schema constraints even with explicit instructions.
**How to avoid:** Embed the exact schema as a JSON example in the system prompt. After decoding, validate that `executable` is non-empty and that `environment` is present (even if empty). If validation fails, fall back to defaults and warn the user.
**Warning signs:** `DecodingError.keyNotFound` in logs.

### Pitfall 2: WineFix Mapping From AI Response

**What goes wrong:** AI returns `"fix_type": "installWinetricks"` but uses a different winetricks verb name than what winetricks actually accepts (e.g., `"dotnet4.8"` instead of `"dotnet48"`).
**Why it happens:** AI hallucination of exact verb names.
**How to avoid:** Include a list of valid winetricks verbs in the diagnosis prompt (at minimum the 8 verbs `WineErrorParser` already knows). Validate the returned verb against a known-safe list; if unrecognized, treat as `none`.
**Warning signs:** `winetricks` exits non-zero after AI-suggested install.

### Pitfall 3: Semaphore Deadlock on Main Thread

**What goes wrong:** `DispatchSemaphore.wait()` on the main thread while `URLSession` tries to deliver its callback on the same main queue.
**Why it happens:** If the URLSession delegate queue is set to `OperationQueue.main`, the callback can't fire while the main thread is blocked on the semaphore.
**How to avoid:** Use `URLSession.shared` (which uses a background delegate queue, not main), not a custom session with `delegateQueue: OperationQueue.main`. The `dataTask(with:completionHandler:)` callback fires on a background thread by default with `URLSession.shared`.
**Warning signs:** CLI hangs indefinitely with no output.

### Pitfall 4: Context Window Overflow

**What goes wrong:** Sending too much Wine stderr to the AI diagnosis endpoint causes the request to be rejected (payload too large) or costs unnecessary tokens.
**Why it happens:** Wine stderr can be many thousands of lines for crash dumps.
**How to avoid:** Truncate stderr to last 200 lines (most relevant) before including in the prompt. Cap at ~8000 characters.
**Warning signs:** HTTP 400 from API with "context length exceeded" message.

### Pitfall 5: One-Time API Key Tip Shown Repeatedly

**What goes wrong:** The "Set ANTHROPIC_API_KEY for AI-powered features" tip prints on every `cellar add` run.
**Why it happens:** No state is tracked for whether the tip has been shown.
**How to avoid:** Write a sentinel file `~/.cellar/.ai-tip-shown` on first display. Check for it before printing.
**Warning signs:** User sees the tip on every invocation.

---

## Code Examples

### Anthropic Messages API Call (URLSession)

```swift
// Source: https://platform.claude.com/docs/en/api/messages (verified 2026-03-27)
// POST https://api.anthropic.com/v1/messages
// Headers: x-api-key, anthropic-version: 2023-06-01, content-type: application/json

struct AnthropicRequest: Encodable {
    let model: String           // "claude-haiku-4-5"
    let maxTokens: Int
    let system: String?
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }

    struct Message: Encodable {
        let role: String        // "user"
        let content: String
    }
}

struct AnthropicResponse: Decodable {
    let content: [ContentBlock]
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    var firstText: String? { content.first(where: { $0.type == "text" })?.text }
}

// Request headers:
// "x-api-key": apiKey
// "anthropic-version": "2023-06-01"
// "content-type": "application/json"
```

### OpenAI Chat Completions API Call (URLSession)

```swift
// Source: https://platform.openai.com/docs/api-reference (verified 2026-03-27)
// POST https://api.openai.com/v1/chat/completions
// Headers: Authorization: Bearer <key>, content-type: application/json

struct OpenAIRequest: Encodable {
    let model: String           // "gpt-4o-mini"
    let messages: [Message]
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages
        case responseFormat = "response_format"
    }

    struct Message: Encodable {
        let role: String        // "system" | "user"
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String        // "json_object"
    }
}

struct OpenAIResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
        struct Message: Decodable {
            let content: String
        }
    }
    var firstContent: String? { choices.first?.message.content }
}

// Request headers:
// "Authorization": "Bearer \(apiKey)"
// "content-type": "application/json"
```

### AIService Interface (Recommended Design)

```swift
// AIService — public API consumed by LaunchCommand and AddCommand
struct AIService {
    enum Result<T> {
        case success(T)
        case unavailable           // no API key
        case failed(String)        // all retries exhausted
    }

    /// Diagnose a Wine failure. Returns a 2-3 sentence explanation + optional WineFix.
    struct Diagnosis {
        let explanation: String
        let suggestedFix: WineFix?
    }

    static func diagnose(stderr: String, gameId: String) -> Result<Diagnosis>
    static func generateRecipe(gameName: String, gameId: String, installedFiles: [URL]) -> Result<Recipe>
}
```

### LaunchCommand Integration Point

```swift
// In LaunchCommand, after WineErrorParser.parse(), when errors has no suggestedFix:
let errors = WineErrorParser.parse(result.stderr)
let hasActionableFix = errors.contains { $0.suggestedFix != nil }

if !hasActionableFix {
    // First-pass parser couldn't help — try AI
    let truncatedStderr = String(result.stderr.suffix(8000))
    switch AIService.diagnose(stderr: truncatedStderr, gameId: game) {
    case .success(let diagnosis):
        print("AI diagnosis: \(diagnosis.explanation)")
        if let fix = diagnosis.suggestedFix {
            // inject fix into errors for the retry loop to handle
        }
    case .unavailable:
        break  // silent — no API key is not an error during launch
    case .failed(let msg):
        print("AI diagnosis unavailable: \(msg)")
    }
}
```

### AddCommand Integration Point

```swift
// In AddCommand, after step 10 (post-install scan), before step 11 (save GameEntry):
// Only runs when recipe == nil (no bundled recipe found)
if recipe == nil {
    let bottleURL = CellarPaths.bottleDir(for: gameId)
    let allFiles = BottleScanner.scanForExecutables(bottlePath: bottleURL)
    switch AIService.generateRecipe(gameName: gameName, gameId: gameId, installedFiles: allFiles) {
    case .success(let aiRecipe):
        print("AI generated recipe for \(gameName):")
        // display with same transparency as bundled recipes
        try RecipeEngine.saveUserRecipe(aiRecipe)
        // use aiRecipe for this launch
    case .unavailable:
        printAITipIfNotShownBefore()
        print("No recipe available. Continue with defaults? [y/n] ", terminator: "")
        // ... prompt user
    case .failed:
        print("No recipe available. Continue with defaults? [y/n] ", terminator: "")
    }
}
```

### RecipeEngine: Save User Recipe

```swift
// New method in RecipeEngine
static func saveUserRecipe(_ recipe: Recipe) throws {
    let dir = CellarPaths.userRecipesDir
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(recipe)
    let file = CellarPaths.userRecipeFile(for: recipe.id)
    try data.write(to: file, options: .atomic)
    print("Recipe saved to \(file.path)")
}
```

### findBundledRecipe: User-Recipes Search Pass

Insert between Strategy 2 (CWD) and Strategy 3 (substring scan) in `RecipeEngine.findBundledRecipe()`:

```swift
// Strategy 2b: User-generated recipes in ~/.cellar/recipes/
let userRecipePath = CellarPaths.userRecipeFile(for: gameId)
if FileManager.default.fileExists(atPath: userRecipePath.path) {
    return try loadRecipe(from: userRecipePath)
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Raw Wine error output to user | WineErrorParser structured diagnosis | Phase 1 | Plain English for known patterns |
| Static bundled recipes only | AI-generated recipes for unknown games | This phase | Long-tail game support |
| Hard failure on unknown game | Graceful fallback + user prompt | This phase | Better UX for unsupported games |

**API versions in use:**
- Anthropic: `anthropic-version: 2023-06-01` (stable, current as of 2026-03-27)
- OpenAI: No version header required; model name pins to specific capability

---

## Open Questions

1. **OpenAI `response_format: json_object` vs Anthropic prompt-only JSON**
   - What we know: OpenAI supports `response_format: {type: "json_object"}` which forces JSON output. Anthropic does not have an equivalent in the standard Messages API (tool use can force structure, but adds complexity).
   - What's unclear: Whether Anthropic's Haiku model reliably outputs valid JSON from prompt instruction alone.
   - Recommendation: For Anthropic, use a clear system prompt with a JSON example and validate the output. If parsing fails after 3 attempts, fall back. Test with real stderr samples during implementation.

2. **File scan context size**
   - What we know: `BottleScanner.scanForExecutables()` returns EXEs only. Recipe generation also benefits from DLL names and config files.
   - What's unclear: How much additional scan logic is needed vs. the existing scanner.
   - Recommendation: For recipe generation, extend context to include: (a) all `.exe` files from `scanForExecutables`, (b) `.dll` files in game install dir only (not Wine system dirs), (c) `.ini` / `.cfg` file names only (not content). Cap at 50 total entries. This is enough for the AI to infer DirectX version, engine type, etc.

3. **One-time tip sentinel file race**
   - What we know: `~/.cellar/.ai-tip-shown` approach works for single-user CLI.
   - What's unclear: Behaviour if two concurrent `cellar add` runs race on creation.
   - Recommendation: Use atomic write (`options: .withoutOverwriting`) or simply check existence before writing; the race is harmless (worst case, tip shows twice on a truly concurrent first run, which is an edge case not worth guarding in v1).

---

## Sources

### Primary (HIGH confidence)

- Anthropic Messages API — `https://platform.claude.com/docs/en/api/messages` (fetched 2026-03-27): endpoint URL, headers, request/response schema, model names including `claude-haiku-4-5`
- Foundation `URLSession.shared.dataTask(with:completionHandler:)` — built-in macOS SDK, used throughout project

### Secondary (MEDIUM confidence)

- OpenAI Chat Completions — `https://platform.openai.com/docs/api-reference` + web search cross-reference: endpoint `POST https://api.openai.com/v1/chat/completions`, `Authorization: Bearer`, `choices[0].message.content`, `gpt-4o-mini` as cheapest model; OpenAI docs returned 403 for direct fetch, confirmed via web search multiple sources
- swift-argument-parser async issues — Swift Forums + GitHub issues: `AsyncParsableCommand` has Swift 6 `@main` resolution bug; `DispatchSemaphore` bridge is the safer alternative for keeping commands synchronous

### Tertiary (LOW confidence)

- `response_format: json_object` for OpenAI — confirmed in web search but not directly verified against latest OpenAI API reference (403 on fetch). Should be validated during implementation.
- `gpt-4o-mini` as cheapest OpenAI model — web search indicates this; newer cheaper models may exist (`gpt-4.1-mini` appeared in results). Verify at implementation time.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — URLSession + Foundation Codable is what the project already uses; no new packages
- Architecture: HIGH — AIService struct with semaphore bridge is proven pattern; integration points clearly identified from code reading
- API schemas: HIGH (Anthropic, fetched directly) / MEDIUM (OpenAI, web search cross-reference)
- Pitfalls: HIGH — semaphore deadlock, JSON validation, context overflow are well-documented issues

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (API schemas stable; model names may change — verify at implementation)

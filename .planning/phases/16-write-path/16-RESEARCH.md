# Phase 16: Write Path - Research

**Researched:** 2026-03-30
**Domain:** GitHub Contents API write path, Swift synchronous HTTP, CellarConfig extension, opt-in prompt pattern
**Confidence:** HIGH

## Summary

Phase 16 is the write counterpart to Phase 15. After the agent loop exits with `taskState == .savedAfterConfirm`, AIService pushes the just-saved SuccessRecord to the collective memory GitHub repo as a CollectiveMemoryEntry. The implementation is a new `CollectiveMemoryWriteService` (or method group) that mirrors the read-path's sync HTTP patterns — GET for read-for-write, merge or append, PUT with SHA, one retry on 409. The opt-in prompt is a `contributeMemory: Bool?` field on `CellarConfig` (nil = never asked, false = declined, true = opted in).

All decisions are fully locked in CONTEXT.md. Research confirms that the existing code provides all necessary primitives: `GitHubAuthService.shared.getToken()` for auth, `URLSession + DispatchSemaphore` for sync HTTP, `CollectiveMemoryEntry` + `EnvironmentFingerprint` for the target schema, and `SuccessDatabase.load(gameId:)` for the source data. The only new code surface is the write service itself, the CellarConfig extension, and the settings toggle.

**Primary recommendation:** Implement `CollectiveMemoryWriteService` as a new file following `CollectiveMemoryService` patterns exactly. Keep it stateless (`struct`, all `static` methods). Hook into `AIService.runAgentLoop()` immediately after the `result.completed` check, before returning `.success`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Contribution trigger:**
- Push happens post-loop in AIService, after the agent loop exits and taskState == .savedAfterConfirm
- Trigger is tied to user confirmation that the game actually launched (the "did the game reach the menu?" prompt)
- Agent launches only — direct launches with existing recipes do not push (no new data to contribute)
- Data source: load the just-saved SuccessRecord from local SuccessDatabase, transform to CollectiveMemoryEntry
- Synchronous push — completes before AIService returns, consistent with existing sync HTTP patterns (5s timeout max per request, 10s total for write flow)

**Opt-in flow:**
- Prompt appears on first successful push opportunity (user just confirmed a game works, before pushing)
- Simple yes/no: "Share this working config with the Cellar community? Other users will benefit when setting up this game. [y/N]"
- Default: no (user must explicitly opt in)
- Stored in CellarConfig as `contributeMemory: Bool?` — nil = not asked yet, true/false = decided
- Also toggleable in web settings page alongside AI provider selection
- Preference checked before every push — if nil, prompt; if false, skip silently; if true, push

**Merge & conflict handling:**
- Same environmentHash already exists in the file → increment confirmations count + update lastConfirmed timestamp. No new entry appended.
- Different environmentHash → append new entry to the array
- New game (file doesn't exist / 404) → create new file with single-entry array
- On 409 conflict: re-fetch latest version, re-apply merge logic, PUT again with new SHA. One retry only — if it conflicts again, give up silently.
- Separate read-for-write method (GET with standard JSON Accept header, returns SHA + content) for the merge flow. Read path keeps its raw mode.
- Commit messages: "Add {game-name} entry" for new files, "Update {game-name} (+1 confirmation)" or "Update {game-name} (new environment)" for updates

**Failure resilience:**
- Silent skip on any push failure (network, auth, timeout, conflict after retry) — user sees nothing
- Failure logged internally to ~/.cellar/logs/ for debugging
- No queue, no retry-on-next-launch — fire and forget. Next successful launch will push fresh data anyway.
- 10-second timeout for the full write operation (GET + merge + PUT)
- Local SuccessRecord save is completely independent — happens first in save_success, GitHub push is a separate optional step after agent loop exits

### Claude's Discretion
- Exact structure of CollectiveMemoryWriteService (or extend existing CollectiveMemoryService)
- How to extract Wine version and flavor for EnvironmentFingerprint construction at push time
- Internal logging format for push success/failure
- SuccessRecord → CollectiveMemoryEntry transformation details (field mapping)
- Whether opt-in prompt uses print/readLine or goes through a helper

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| WRIT-01 | After user-confirmed successful launch, agent automatically pushes config + reasoning + environment to collective memory repo via GitHub Contents API | GitHub Contents API PUT pattern confirmed; integration point in AIService.runAgentLoop after result.completed; SuccessRecord→CollectiveMemoryEntry field mapping documented below |
| WRIT-02 | Confidence counter increments when a different agent confirms the same config works (deduplicated by environment hash) | environmentHash field already on CollectiveMemoryEntry; merge logic: GET entries array, find matching hash, increment confirmations + update lastConfirmed, PUT back with SHA |
| WRIT-03 | User is prompted on first run to opt into collective memory contribution; preference saved in config | CellarConfig extension with contributeMemory: Bool?; nil triggers prompt; true/false persists to ~/.cellar/config.json via existing save pattern |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation (URLSession) | system | Synchronous HTTP via DispatchSemaphore | Already used in CollectiveMemoryService and GitHubAuthService — no new deps |
| Foundation (JSONEncoder/Decoder) | system | Encode entries array; base64 content body | Already used throughout codebase |
| CryptoKit | system | SHA-256 for environmentHash | Already imported in CollectiveMemoryEntry.swift |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Security.framework | system | RS256 JWT (via GitHubAuthService) | Already handles auth — write service just calls getToken() |

**Installation:** No new dependencies. All required frameworks are already imported.

## Architecture Patterns

### Recommended Project Structure
```
Sources/cellar/Core/
├── CollectiveMemoryService.swift       # existing read path (unchanged)
├── CollectiveMemoryWriteService.swift  # new write path
├── AIService.swift                     # hook write-back here post-loop
Sources/cellar/Persistence/
├── CellarConfig.swift                  # extend with contributeMemory: Bool?
Sources/cellar/Web/Controllers/
├── SettingsController.swift            # add contributeMemory toggle
Sources/cellar/Resources/Views/
├── settings.leaf                       # UI for toggle
```

### Pattern 1: GitHub Contents API Write (GET + merge + PUT)

**What:** Read the current file to get the SHA and entries array, merge locally, PUT the new content.
**When to use:** Every contribution push, always — SHA is required for non-conflict PUT.

```swift
// Source: GitHub REST API documentation (Contents endpoint)
// GET returns JSON with "sha" and "content" (base64-encoded)
// PUT requires: message, content (base64), sha (omit for new file)

struct GitHubContentsResponse: Codable {
    let sha: String
    let content: String   // base64-encoded file content
}

struct GitHubPutRequest: Codable {
    let message: String
    let content: String   // base64-encoded new content
    let sha: String?      // nil for new file creation

    enum CodingKeys: String, CodingKey {
        case message, content, sha
    }
}
```

**GET URL:** `https://api.github.com/repos/{owner}/{repo}/contents/entries/{slug}.json`
**Accept header for read-for-write:** `application/vnd.github+json` (returns JSON with sha + base64 content)
**Accept header for raw read (existing read path):** `application/vnd.github.v3.raw` (returns file bytes directly — no sha)

These are two distinct Accept headers for two distinct purposes. The write service uses the JSON form.

### Pattern 2: Synchronous HTTP (established DispatchSemaphore pattern)

```swift
// Source: CollectiveMemoryService.swift and GitHubAuthService.swift — identical pattern
private static func performRequest(request: URLRequest) -> (data: Data, statusCode: Int)? {
    final class ResultBox: @unchecked Sendable {
        var value: (Data, Int)?
    }
    let box = ResultBox()
    let semaphore = DispatchSemaphore(value: 0)

    URLSession.shared.dataTask(with: request) { data, response, error in
        if error == nil,
           let data = data,
           let httpResponse = response as? HTTPURLResponse {
            box.value = (data, httpResponse.statusCode)
        }
        semaphore.signal()
    }.resume()

    semaphore.wait()
    return box.value
}
```

### Pattern 3: CellarConfig extension with optional Bool

```swift
// Source: existing CellarConfig.swift pattern — extend with new optional field
struct CellarConfig: Codable {
    var budgetCeiling: Double
    var aiProvider: String?
    var contributeMemory: Bool?  // nil = not asked, true = opted in, false = declined

    enum CodingKeys: String, CodingKey {
        case budgetCeiling = "budget"
        case aiProvider = "ai_provider"
        case contributeMemory = "contribute_memory"
    }
}
```

CellarConfig already uses `JSONDecoder` with default synthesized Codable — an unknown field on disk is silently ignored, and a missing field deserializes as `nil` for Optional types. No migration needed.

**Save pattern** (CellarConfig needs a `save()` method — it currently only has `load()`):

```swift
static func save(_ config: CellarConfig) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    try FileManager.default.createDirectory(
        at: CellarPaths.base, withIntermediateDirectories: true)
    try data.write(to: CellarPaths.configFile, options: .atomic)
}
```

### Pattern 4: SuccessRecord → CollectiveMemoryEntry Transformation

Full field mapping from `SuccessRecord` to `CollectiveMemoryEntry`:

| CollectiveMemoryEntry field | Source | Notes |
|----------------------------|--------|-------|
| `schemaVersion` | hardcoded `1` | |
| `gameId` | `record.gameId` | |
| `gameName` | `record.gameName` | |
| `config.environment` | `record.environment` | `[String: String]` — direct copy |
| `config.dllOverrides` | `record.dllOverrides` | `[DLLOverrideRecord]` — same type |
| `config.registry` | `record.registry` | `[RegistryRecord]` — same type |
| `config.launchArgs` | `record.tags` filtered for launch args OR empty `[]` | SuccessRecord has no dedicated launchArgs field — use `[]` |
| `config.setupDeps` | `record.tags` filtered OR empty `[]` | Same — use `[]` unless tags contain known verbs |
| `environment` | `EnvironmentFingerprint.current(wineVersion:wineFlavor:)` | Detect at push time |
| `environmentHash` | `environment.computeHash()` | Computed from fingerprint |
| `reasoning` | `record.resolutionNarrative ?? ""` | |
| `engine` | `record.engine` | |
| `graphicsApi` | `record.graphicsApi` | |
| `confirmations` | `1` | First confirmation for this agent |
| `lastConfirmed` | ISO8601 timestamp of now | |

Note on `launchArgs` and `setupDeps`: `SuccessRecord` does not have these fields directly. `WorkingConfig` (the CollectiveMemoryEntry config type) expects arrays. Use empty arrays — the agent's `resolutionNarrative` captures the intent, and launch args / setup deps are rarely generalizable across machines anyway.

### Pattern 5: Opt-in Prompt Flow

```swift
// Called in AIService.runAgentLoop() after result.completed check
// Before: tools.taskState == .savedAfterConfirm && result.completed == true
private static func handleContributionIfNeeded(
    tools: AgentTools,
    wineURL: URL
) {
    guard tools.taskState == .savedAfterConfirm else { return }

    var config = CellarConfig.load()

    // Check/prompt for opt-in
    if config.contributeMemory == nil {
        print("\nShare this working config with the Cellar community?")
        print("Other users will benefit when setting up this game. [y/N]: ", terminator: "")
        fflush(stdout)
        let answer = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        config.contributeMemory = (answer == "y" || answer == "yes")
        try? CellarConfig.save(config)
    }

    guard config.contributeMemory == true else { return }

    // Load SuccessRecord and push
    guard let record = SuccessDatabase.load(gameId: tools.gameId) else { return }
    CollectiveMemoryWriteService.push(record: record, wineURL: wineURL)
}
```

### Pattern 6: Merge Logic

```swift
// Source: CONTEXT.md decisions
enum MergeAction {
    case createNew          // 404 — no file exists
    case incrementExisting  // same environmentHash found
    case appendNew          // different environmentHash
}

// Pseudo-code for merge
func mergeEntries(
    existing: [CollectiveMemoryEntry],
    newEntry: CollectiveMemoryEntry
) -> ([CollectiveMemoryEntry], MergeAction) {
    if let idx = existing.firstIndex(where: { $0.environmentHash == newEntry.environmentHash }) {
        var updated = existing
        let old = updated[idx]
        updated[idx] = CollectiveMemoryEntry(
            // ... all fields from old ...
            confirmations: old.confirmations + 1,
            lastConfirmed: newEntry.lastConfirmed  // current timestamp
        )
        return (updated, .incrementExisting)
    } else {
        return (existing + [newEntry], .appendNew)
    }
}
```

### Pattern 7: Failure Logging

```swift
// Log to ~/.cellar/logs/memory-push.log
// Append-only, one line per event
// Format: ISO8601 LEVEL gameId message
// Example: 2026-03-30T14:23:01Z INFO cossacks-european-wars Push succeeded (+1 confirmation)
// Example: 2026-03-30T14:23:01Z ERROR cossacks-european-wars Push failed: network timeout
private static func logPushEvent(_ level: String, gameId: String, _ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) \(level) \(gameId) \(message)\n"
    let logFile = CellarPaths.logsDir.appendingPathComponent("memory-push.log")
    // Append to file — use FileHandle for append-only write
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forUpdating: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            // File doesn't exist yet — create it
            try? FileManager.default.createDirectory(
                at: CellarPaths.logsDir, withIntermediateDirectories: true)
            try? data.write(to: logFile)
        }
    }
}
```

### Anti-Patterns to Avoid

- **Throwing from the write service:** The write service must never throw — all errors are caught and logged internally. AIService hook is a fire-and-forget call site.
- **Prompting for opt-in on non-savedAfterConfirm exits:** Only prompt when the game actually succeeded. Budget exhaustion, iteration limit, or API failure should never trigger the prompt.
- **Using `.vnd.github.v3.raw` Accept header for read-for-write GET:** The raw endpoint returns file bytes, not the SHA. The write service needs `application/vnd.github+json` to get the SHA alongside the content.
- **Omitting SHA for existing files:** A PUT without SHA on an existing file creates a conflict — always include SHA from the preceding GET.
- **Blocking the user experience on push timeout:** The 10s total timeout is a ceiling; if the push takes 9 seconds, the session is still delayed. Use URLRequest.timeoutInterval properly per-request.
- **Modifying CollectiveMemoryService.swift for write logic:** Keep read and write in separate files. CollectiveMemoryService is already well-tested and used by Phase 15.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Auth token | Custom JWT/token logic | `GitHubAuthService.shared.getToken()` | Already handles caching, refresh, RS256 JWT |
| Sync HTTP | Async/await or callback chains | `DispatchSemaphore + URLSession.shared.dataTask` | Established pattern in codebase; no async context at call site |
| base64 encoding of file content | Manual encoding | `Data.base64EncodedString()` | Standard Foundation API |
| Config persistence | Custom file writing | Extend existing `CellarConfig.save()` pattern | Already has load(); save() follows same pattern |
| Environment fingerprint | Re-detect wine version inline | `EnvironmentFingerprint.current(wineVersion:wineFlavor:)` | Already implemented in Phase 14 |
| Game slug | Custom string munging | `slugify()` | Already implemented in CollectiveMemoryEntry.swift |

**Key insight:** This phase is almost entirely plumbing between existing components. The hard problems (auth, schema, dedup hash, slug) are already solved. The write service is primarily connecting known pieces in the right order.

## Common Pitfalls

### Pitfall 1: CollectiveMemoryEntry is a struct with `let` fields
**What goes wrong:** Cannot mutate a single field (e.g., `entry.confirmations += 1`) — must construct a new instance.
**Why it happens:** Swift structs with `let` stored properties are immutable.
**How to avoid:** Build a new `CollectiveMemoryEntry` value using member-wise initializer when incrementing.
**Warning signs:** Compiler error "cannot assign to property: 'confirmations' is a 'let' constant."

### Pitfall 2: base64 content from GET includes newlines
**What goes wrong:** GitHub wraps base64 content at 60 characters with `\n`. `Data(base64Encoded:)` rejects strings with embedded newlines by default.
**Why it happens:** RFC 2045 base64 wrapping — GitHub follows it in responses.
**How to avoid:** Strip newlines before decoding: `content.replacingOccurrences(of: "\n", with: "")` before passing to `Data(base64Encoded:)`.
**Warning signs:** `Data(base64Encoded:)` returns nil even though the string looks valid.

### Pitfall 3: CellarConfig save races with concurrent load
**What goes wrong:** If two processes run simultaneously (unlikely but possible), one save can overwrite the other's contribute_memory update.
**Why it happens:** File write is not atomic across processes.
**How to avoid:** Use `.atomic` write option (already in pattern). The race window is tiny and the worst case (losing the opt-in) is recoverable — user is prompted again. Acceptable for this use case.
**Warning signs:** Not a warning sign — just a known accepted limitation.

### Pitfall 4: taskState check timing in AIService
**What goes wrong:** Checking `tools.taskState` after `agentLoop.run()` returns works — the loop updates taskState via AgentTools. But accessing `tools` after `result` is returned should be fine since both are in the same stack frame.
**Why it happens:** N/A — this is the correct pattern.
**How to avoid:** Access `tools.taskState` before the `if result.completed` branch but use it inside. The hook should be: `if result.completed && tools.taskState == .savedAfterConfirm { ... }`.

### Pitfall 5: ISO8601 timestamp format consistency
**What goes wrong:** `lastConfirmed` is a `String` in the schema. If the format differs between what the read path expects and what the write path produces, parsing may fail elsewhere.
**Why it happens:** ISO8601 has many valid forms.
**How to avoid:** Use `ISO8601DateFormatter().string(from: Date())` which produces `2026-03-30T14:23:01Z` — consistent with `verifiedAt` in `SuccessRecord`.

### Pitfall 6: Web settings contributeMemory toggle — CellarConfig vs .env
**What goes wrong:** `SettingsController` manages `.env` file (API keys), not `config.json`. The `contributeMemory` field lives in `config.json`. Mixing them in one save call will write the wrong file.
**Why it happens:** Two separate persistence mechanisms for different concern types.
**How to avoid:** Settings toggle for `contributeMemory` must call `CellarConfig.load()` → mutate → `CellarConfig.save()`, not the `.env` file writer. Separate POST route or extend existing `/settings/keys` to also handle config.json fields.

## Code Examples

### GitHub Contents API GET for read-for-write

```swift
// Returns (sha, entries) or nil on failure
// Source: GitHub REST API documentation — Contents endpoint, JSON Accept header
private static func fetchEntriesForWrite(
    token: String,
    slug: String,
    memoryRepo: String,
    timeout: TimeInterval
) -> (sha: String, entries: [CollectiveMemoryEntry])? {
    let urlString = "https://api.github.com/repos/\(memoryRepo)/contents/entries/\(slug).json"
    guard let url = URL(string: urlString) else { return nil }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.timeoutInterval = timeout

    guard let (data, statusCode) = performRequest(request: request) else { return nil }

    if statusCode == 404 {
        return ("", [])  // empty SHA signals new file
    }
    guard statusCode == 200 else { return nil }

    guard let response = try? JSONDecoder().decode(GitHubContentsResponse.self, from: data) else {
        return nil
    }

    // Strip newlines from base64 (GitHub wraps at 60 chars)
    let cleanBase64 = response.content.replacingOccurrences(of: "\n", with: "")
    guard let contentData = Data(base64Encoded: cleanBase64) else { return nil }
    let entries = (try? JSONDecoder().decode([CollectiveMemoryEntry].self, from: contentData)) ?? []
    return (response.sha, entries)
}
```

### GitHub Contents API PUT

```swift
// Source: GitHub REST API documentation — Contents endpoint PUT
private static func putEntries(
    token: String,
    slug: String,
    memoryRepo: String,
    entries: [CollectiveMemoryEntry],
    sha: String,          // empty string = new file creation (no sha field in body)
    commitMessage: String,
    timeout: TimeInterval
) -> Int? {  // returns HTTP status code
    let urlString = "https://api.github.com/repos/\(memoryRepo)/contents/entries/\(slug).json"
    guard let url = URL(string: urlString) else { return nil }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let contentData = try? encoder.encode(entries) else { return nil }
    let base64Content = contentData.base64EncodedString()

    // Build request body — omit sha for new file
    var body: [String: String] = [
        "message": commitMessage,
        "content": base64Content
    ]
    if !sha.isEmpty {
        body["sha"] = sha
    }

    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = bodyData
    request.timeoutInterval = timeout

    guard let (_, statusCode) = performRequest(request: request) else { return nil }
    return statusCode
}
```

### AIService integration hook

```swift
// In AIService.runAgentLoop(), replace the current `if result.completed { return .success(...) }` block:
// Source: CONTEXT.md integration point

if result.completed {
    // Post-loop: push to collective memory if task completed with user confirmation
    if tools.taskState == .savedAfterConfirm {
        handleContributionIfNeeded(tools: tools, wineURL: wineURL)
    }
    return .success(result.finalText)
} else {
    // ... existing failure handling ...
}
```

### CollectiveMemoryEntry construction with updated confirmations

```swift
// CollectiveMemoryEntry has let fields — must construct new value
// Source: CollectiveMemoryEntry.swift
extension CollectiveMemoryEntry {
    func withIncrementedConfirmation() -> CollectiveMemoryEntry {
        CollectiveMemoryEntry(
            schemaVersion: schemaVersion,
            gameId: gameId,
            gameName: gameName,
            config: config,
            environment: environment,
            environmentHash: environmentHash,
            reasoning: reasoning,
            engine: engine,
            graphicsApi: graphicsApi,
            confirmations: confirmations + 1,
            lastConfirmed: ISO8601DateFormatter().string(from: Date())
        )
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Raw Accept header (read path only) | JSON Accept header (read-for-write) | Phase 16 | Enables SHA retrieval needed for PUT |
| No write path | CollectiveMemoryWriteService | Phase 16 | Closes the community feedback loop |
| No contributeMemory field | CellarConfig.contributeMemory: Bool? | Phase 16 | Persists opt-in decision across sessions |

**No deprecated patterns for this phase** — all new code follows established conventions.

## Open Questions

1. **CellarConfig.save() — does it exist?**
   - What we know: `CellarConfig.load()` exists. The file is at `CellarPaths.configFile`. The pattern for saving is established by `SuccessDatabase.save()`.
   - What's unclear: Whether a `save()` method already exists or needs to be added.
   - Recommendation: Add `static func save(_ config: CellarConfig) throws` to CellarConfig.swift in Plan 01.

2. **Web settings toggle — separate route or extend existing POST /settings/keys?**
   - What we know: `POST /settings/keys` writes the `.env` file. `contributeMemory` lives in `config.json`, a different file.
   - What's unclear: Whether to extend the existing form/route or add a separate POST /settings/config endpoint.
   - Recommendation: Add a separate `POST /settings/config` route that handles `config.json` fields only (contributeMemory, potentially budgetCeiling in future). Keeps the two persistence mechanisms cleanly separated.

3. **Plan split: 2 plans or 3?**
   - Recommendation: 2 plans — Plan 01: CollectiveMemoryWriteService + CellarConfig.contributeMemory + AIService hook (CLI path complete); Plan 02: Web settings toggle for contributeMemory.

## Sources

### Primary (HIGH confidence)
- Direct code inspection of `CollectiveMemoryService.swift` — read-path patterns confirmed
- Direct code inspection of `GitHubAuthService.swift` — auth API, performHTTPRequest pattern confirmed
- Direct code inspection of `CollectiveMemoryEntry.swift` — schema, EnvironmentFingerprint.current() confirmed
- Direct code inspection of `SuccessDatabase.swift` — SuccessRecord fields confirmed
- Direct code inspection of `CellarConfig.swift` — config structure, load() pattern confirmed
- Direct code inspection of `AIService.swift` — runAgentLoop(), taskState check point confirmed
- Direct code inspection of `SettingsController.swift` — settings patterns confirmed

### Secondary (MEDIUM confidence)
- GitHub REST API documentation — Contents endpoint: GET returns `sha` + `content` (base64); PUT requires `message`, `content`, `sha` (omit for new file); 409 = conflict; well-established API
- base64 newline stripping requirement — standard GitHub Contents API behavior (RFC 2045 wrapping)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all from direct code inspection, no new dependencies
- Architecture: HIGH — mirrors read-path exactly, all integration points verified in code
- Pitfalls: HIGH — base64 issue is documented GitHub behavior; struct immutability is Swift language fact; other pitfalls from code inspection

**Research date:** 2026-03-30
**Valid until:** 2026-04-30 (stable — no fast-moving dependencies)

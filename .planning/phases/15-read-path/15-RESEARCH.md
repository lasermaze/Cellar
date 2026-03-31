# Phase 15: Read Path - Research

**Researched:** 2026-03-30
**Domain:** Swift / GitHub Contents API / Agent context injection
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Memory injection**
- Pre-fetch memory before spawning AgentLoop — extend AIService.swift:784 initial message construction
- Full entry dump: include complete WorkingConfig + reasoning + environment as structured text in the initial message
- System prompt instructs agent: "A community-verified config exists. Try it first before researching from scratch."
- Agent launches only — direct launches use existing recipe/success record path, no memory lookup

**Environment matching**
- Arch mismatch (arm64 vs x86_64) is hard incompatible — entry is dropped entirely, not shown to agent
- Wine version staleness: major version only — flag when local major version is >1 ahead of entry's last confirmation (e.g., Wine 9.x entry on Wine 11.x)
- Wine flavor (game-porting-toolkit vs regular Wine) is a soft factor — different flavor gets a warning annotation but entry is still shown
- All filtering happens in code (pre-agent), not in agent reasoning — agent gets clean, pre-assessed data

**Multi-entry handling**
- Best match only — pick the single entry with the highest confirmations count (tiebreaker: closest Wine version)
- If no entries pass the arch filter, skip entirely — no memory context, agent proceeds with normal R-D-A
- No "all compatible" or "top 3" — one clear recommendation

**Failure behavior**
- Silent skip when collective memory is unreachable (network, auth, API error) — log internally, user never sees an error
- 5-second timeout on the GitHub Contents API fetch
- No local caching — always fetch fresh from GitHub on each agent launch

### Claude's Discretion
- Exact format of the memory context block in the initial message
- System prompt wording for "try stored config first" instruction
- Internal logging format for silent skip
- How to extract major version number from Wine version string

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| READ-01 | Agent queries collective memory for the current game before starting diagnosis — if a matching entry exists, it's injected as context in the initial agent message | GitHub Contents API fetch + CollectiveMemoryEntry decode + initialMessage construction at AIService.swift:784 |
| READ-02 | Agent reasons about environment delta between stored entry and local environment before applying (not blind application) | Pre-agent filtering (arch hard-drop, flavor annotation) + structured context block with explicit environment comparison text |
| READ-03 | Agent flags entries as potentially stale when current Wine version is more than one major version ahead of last confirmation | Major version extraction from Wine version string + staleness annotation in context block |
</phase_requirements>

---

## Summary

Phase 15 adds a read-only path: before the agent loop starts, Cellar fetches a collective memory entry for the game from the GitHub repo, filters/ranks it, and if a compatible entry is found it injects that config plus a staleness/compatibility assessment into the agent's initial message. The agent sees this context before making any tool calls.

All the required infrastructure already exists. `CollectiveMemoryEntry`, `EnvironmentFingerprint`, `WorkingConfig`, `slugify()`, `GitHubAuthService.shared`, and the GitHub Contents API pattern (used in Phase 13) are complete. The integration point is a single, well-understood location: the `initialMessage` construction in `AIService.runAgentLoop()` at line 784. No new dependencies are needed.

The main implementation work is: (1) a new `CollectiveMemoryService` struct (or free function) that wraps the GitHub Contents API fetch and entry selection logic, (2) local Wine version detection (run `wine --version`, parse output), and (3) composing the memory context block and appending it to `initialMessage`. The system prompt also needs a small addition instructing the agent to treat the memory block as a first-resort configuration.

**Primary recommendation:** Implement a `CollectiveMemoryService.fetchBestEntry(for:wineURL:)` function that encapsulates fetch + filter + rank, then call it in `runAgentLoop` just before the `initialMessage` is built. Keep the service stateless — no caching, no side effects.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| URLSession (Foundation) | system | GitHub Contents API HTTP GET | Already used throughout AIService and GitHubAuthService — identical semaphore pattern |
| JSONDecoder (Foundation) | system | Decode `[CollectiveMemoryEntry]` from raw JSON | Already used for all API decoding |
| Security.framework | system | GitHub App JWT — via GitHubAuthService.shared.getToken() | Already wired in Phase 13 |
| CryptoKit | system | Not directly needed here (fingerprint hashing is write-path only) | Present in CollectiveMemoryEntry.swift |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Process (Foundation) | system | Run `wine --version` to detect local Wine version | Only needed to obtain wineVersion for EnvironmentFingerprint.current() |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Run `wine --version` at call site | Cache from DependencyChecker | DependencyChecker doesn't capture version string — running once per agent launch is cheap |
| URLRequest timeout via `timeoutIntervalForRequest` | DispatchSemaphore with manual timeout | `timeoutIntervalForRequest` is cleaner and built-in — use it |

---

## Architecture Patterns

### Recommended Project Structure

The new code fits inside:

```
Sources/cellar/Core/
├── AIService.swift          # integration point — calls CollectiveMemoryService
└── CollectiveMemoryService.swift   # NEW — fetch, filter, rank, format
Sources/cellar/Models/
└── CollectiveMemoryEntry.swift     # EXISTING — no changes needed
```

No new files outside `Core/` are required.

### Pattern 1: Synchronous GitHub Contents API Fetch (existing pattern)

**What:** `URLSession.shared.dataTask` wrapped in `DispatchSemaphore` to make it synchronous. Accept header `application/vnd.github.v3.raw` returns the raw file body directly — no base64 decoding needed.

**When to use:** Everywhere in this codebase that calls network APIs from a synchronous context (AIService, GitHubAuthService — both use this exact pattern).

**Example (from GitHubAuthService.performHTTPRequest):**
```swift
// Source: GitHubAuthService.swift — performHTTPRequest()
final class ResultBox: @unchecked Sendable {
    var value: Result<Data, Error> = .failure(...)
}
let box = ResultBox()
let semaphore = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: request) { data, response, error in
    // fill box
    semaphore.signal()
}.resume()
semaphore.wait()
return try box.value.get()
```

For this phase, create a `URLRequest` with:
- URL: `https://api.github.com/repos/{memoryRepo}/contents/entries/{slug}.json`
- Header `Authorization: Bearer {token}`
- Header `Accept: application/vnd.github.v3.raw`  ← returns raw JSON, not base64-wrapped
- `timeoutIntervalForRequest: 5` (5-second timeout per locked decision)

### Pattern 2: Entry Format in the Memory Repo

Each `entries/{slug}.json` file is a JSON **array** of `CollectiveMemoryEntry` objects (per SCHM-02). Decode as `[CollectiveMemoryEntry]`.

**Example:**
```swift
// Decode the array from raw file bytes
let entries = try JSONDecoder().decode([CollectiveMemoryEntry].self, from: data)
```

(If the file doesn't exist GitHub returns 404 — catch as "no entry" not as an error.)

### Pattern 3: Wine Version Detection

There is no existing Wine version detection in the codebase (DependencyChecker only checks binary existence, not version). Need to run `wine --version` once and parse it.

```swift
// Source: derived from WineProcess.run() pattern — Process() is standard
func detectWineVersion(wineURL: URL) -> String? {
    let process = Process()
    process.executableURL = wineURL
    process.arguments = ["--version"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    // Output format: "wine-9.0 (Staging)" or "wine-10.3"
    // Return the version number portion: "9.0" or "10.3"
    return output.components(separatedBy: "-").dropFirst().first?
        .components(separatedBy: " ").first
}
```

### Pattern 4: Major Version Comparison for Staleness (READ-03)

Extract integer major version from version strings like `"9.0"`, `"10.3"`, `"11.0 (Staging)"`.

```swift
// Source: Claude's discretion — simple, no regex needed
func majorVersion(from versionString: String) -> Int? {
    // Clean: strip anything after space (e.g. "(Staging)")
    let clean = versionString.components(separatedBy: " ").first ?? versionString
    // Take before the first "."
    return Int(clean.components(separatedBy: ".").first ?? "")
}
```

Staleness rule: `localMajor - entryMajor > 1` → flag as potentially stale.

### Pattern 5: Arch Filtering (READ-02 hard incompatible)

```swift
// Compile-time arch detection — already used in EnvironmentFingerprint.current()
#if arch(arm64)
let localArch = "arm64"
#else
let localArch = "x86_64"
#endif

// Filter: drop entries where entry.environment.arch != localArch
let archFiltered = entries.filter { $0.environment.arch == localArch }
```

### Pattern 6: Ranking — Highest Confirmations, Tiebreak by Wine Version Proximity

```swift
// Sort: most confirmations first, tiebreak by proximity of Wine major version to local
let ranked = archFiltered.sorted { a, b in
    if a.confirmations != b.confirmations {
        return a.confirmations > b.confirmations
    }
    let localMaj = majorVersion(from: localWineVersion) ?? 0
    let aMaj = majorVersion(from: a.environment.wineVersion) ?? 0
    let bMaj = majorVersion(from: b.environment.wineVersion) ?? 0
    return abs(aMaj - localMaj) < abs(bMaj - localMaj)
}
let best = ranked.first
```

### Pattern 7: Memory Context Block Format (Claude's Discretion)

The context block is injected into the agent's initial message. It should be clearly delimited so the agent can reason about it. Recommended format:

```
--- COLLECTIVE MEMORY ---
A community-verified configuration exists for this game. Try it first before researching from scratch.

Confirmations: 3 | Verified environment: arm64, Wine 9.0, macOS 14.2.1
[FLAVOR WARNING: Entry was verified with game-porting-toolkit; local Wine flavor is wine-stable. Config may still apply.]
[STALENESS WARNING: Entry confirmed on Wine 9.x; current Wine is 11.x (2 major versions ahead). Verify compatibility.]

Working Config:
  Environment variables:
    WINEDEBUG=-all
    WINE_CPU_TOPOLOGY=1:0
  DLL overrides:
    ddraw -> native (cnc-ddraw)
  Registry:
    HKCU\Software\Wine\Direct3D REG_SZ MaxVersionGL = 4.5
  Launch args: (none)
  Setup deps: cnc-ddraw

Agent's Reasoning (from prior session):
  "The game uses the Build engine with DirectDraw. Placed cnc-ddraw and configured ddraw.ini
   with renderer=opengl. This resolved the renderer selection dialog crash on macOS."
--- END COLLECTIVE MEMORY ---
```

Then the normal launch instruction follows.

### Pattern 8: System Prompt Addition (Claude's Discretion)

Add to the existing system prompt (after the constraints section):

```
## Collective Memory
When a COLLECTIVE MEMORY block appears in the initial message, treat it as your first hypothesis.
Apply the stored config before attempting web research. Only fall back to full R-D-A research if:
- The stored config produces errors not present in the original reasoning
- The STALENESS WARNING is present and launch fails
Explain your reasoning when you deviate from the stored config.
```

### Anti-Patterns to Avoid

- **Making entry selection/assessment inside the agent prompt:** All filtering, ranking, and staleness checks happen in code before the agent sees anything. The agent gets pre-assessed data.
- **Surfacing errors to the user:** Network errors, 404s, auth failures → silent log + skip. The user never sees "collective memory unavailable."
- **Caching entries locally:** No local caching per locked decision. Always fetch fresh.
- **Passing raw JSON to the agent:** Format the entry as human-readable structured text, not raw JSON. The agent should be able to parse it reliably.
- **Blocking launch on 404:** A 404 for `entries/{slug}.json` means no entry yet — that's normal. Proceed with standard R-D-A.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP with timeout | Custom timeout loop | `URLRequest.timeoutIntervalForRequest = 5` | Built-in, reliable |
| JSON array decode | Manual parsing | `JSONDecoder().decode([CollectiveMemoryEntry].self, from:)` | Types already defined in Phase 14 |
| GitHub API auth | New auth logic | `GitHubAuthService.shared.getToken()` | Phase 13 built this — `.unavailable` = silent skip |
| Wine version detection | Regex on plist/file | `wine --version` subprocess | Simple, always accurate |

---

## Common Pitfalls

### Pitfall 1: GitHub Contents API returns base64-wrapped JSON by default

**What goes wrong:** Without `Accept: application/vnd.github.v3.raw`, the response is a JSON envelope with `"content"` as a base64-encoded string. You'd try to decode it as `[CollectiveMemoryEntry]` and fail.

**Why it happens:** Default GitHub API response wraps file content.

**How to avoid:** Always set `Accept: application/vnd.github.v3.raw` header. Then response body is the raw file content directly decodable as `[CollectiveMemoryEntry]`.

**Warning signs:** JSONDecoder throws `typeMismatch` or `keyNotFound` errors on `schemaVersion`.

### Pitfall 2: 404 treated as error instead of "no entry"

**What goes wrong:** Game has no memory entry yet → GitHub returns 404 → code throws → launch blocked.

**Why it happens:** `callAPI` in AIService treats `statusCode >= 400` as failure. The memory fetch must handle 404 specially (return `nil` entries, not throw).

**How to avoid:** In `CollectiveMemoryService`, check specifically for 404 and return `[]` (empty array). Throw only on 5xx or network errors.

**Warning signs:** First-time game launches always fail with memory error.

### Pitfall 3: Wine version string format varies

**What goes wrong:** `wine --version` output varies: `"wine-9.0 (Staging)"`, `"wine-10.3"`, `"wine-9.0 (GE)"`. Naive splitting breaks.

**Why it happens:** Community Wine builds add custom suffixes.

**How to avoid:** Split on `-` to drop `"wine"` prefix, then split first token on space to drop suffix like `"(Staging)"`, then split on `.` to get major version integer.

**Warning signs:** `majorVersion()` returns nil for valid version strings.

### Pitfall 4: `wineURL` not available at `initialMessage` construction site

**What goes wrong:** `runAgentLoop()` receives `wineURL` as a parameter, but the call to `detectWineVersion(wineURL:)` happens inside the function. Need to ensure wineURL is passed through correctly — it already is (it's a parameter).

**Why it happens:** Non-issue — `wineURL` is already available at the integration point.

**How to avoid:** No action needed. Just call `detectWineVersion(wineURL: wineURL)` directly in `runAgentLoop`.

### Pitfall 5: `DispatchSemaphore.wait()` with no timeout can hang if URLSession delegate queue is blocked

**What goes wrong:** Memory fetch hangs indefinitely if the URLSession is congested.

**Why it happens:** The 5-second timeout via `timeoutIntervalForRequest` is set on the `URLRequest` object. This IS sufficient — URLSession will call the completion handler with an error after 5s, which signals the semaphore.

**How to avoid:** Confirm `timeoutIntervalForRequest` is set on the request before `dataTask` is created. This is the existing pattern in `GitHubAuthService.performHTTPRequest` (though that one lacks a timeout — add it here).

---

## Code Examples

Verified patterns from the existing codebase:

### CollectiveMemoryService skeleton

```swift
// Source: derived from GitHubAuthService.performHTTPRequest + CollectiveMemoryEntry (Phase 14)
struct CollectiveMemoryService {

    /// Fetch, filter, and rank entries for a game. Returns nil if no compatible entry found
    /// or if memory is unavailable (all errors are swallowed).
    static func fetchBestEntry(
        for gameName: String,
        wineURL: URL
    ) -> (entry: CollectiveMemoryEntry, isStale: Bool, flavorMismatch: Bool)? {
        // 1. Auth
        guard case .token(let token) = GitHubAuthService.shared.getToken() else {
            // silent skip — credentials not configured
            return nil
        }

        // 2. Detect local environment
        guard let localWineVersion = detectWineVersion(wineURL: wineURL) else { return nil }
        let localFlavor = detectWineFlavor(wineURL: wineURL)  // "wine-stable" or "game-porting-toolkit"
        let localFingerprint = EnvironmentFingerprint.current(
            wineVersion: localWineVersion,
            wineFlavor: localFlavor
        )

        // 3. Build request
        let slug = slugify(gameName)
        let repo = GitHubAuthService.shared.memoryRepo
        let urlString = "https://api.github.com/repos/\(repo)/contents/entries/\(slug).json"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutIntervalForRequest = 5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        // 4. Fetch (synchronous)
        guard let data = try? performFetch(request: request) else { return nil }

        // 5. Decode
        guard let entries = try? JSONDecoder().decode([CollectiveMemoryEntry].self, from: data),
              !entries.isEmpty else { return nil }

        // 6. Filter by arch (hard incompatible)
        let archFiltered = entries.filter { $0.environment.arch == localFingerprint.arch }
        guard !archFiltered.isEmpty else { return nil }

        // 7. Rank: most confirmations first, tiebreak by Wine major version proximity
        let localMajor = majorVersion(from: localWineVersion) ?? 0
        let ranked = archFiltered.sorted { a, b in
            if a.confirmations != b.confirmations { return a.confirmations > b.confirmations }
            let aMaj = majorVersion(from: a.environment.wineVersion) ?? 0
            let bMaj = majorVersion(from: b.environment.wineVersion) ?? 0
            return abs(aMaj - localMajor) < abs(bMaj - localMajor)
        }
        let best = ranked[0]

        // 8. Assess staleness and flavor mismatch
        let entryMajor = majorVersion(from: best.environment.wineVersion) ?? 0
        let isStale = (localMajor - entryMajor) > 1
        let flavorMismatch = best.environment.wineFlavor != localFingerprint.wineFlavor

        return (entry: best, isStale: isStale, flavorMismatch: flavorMismatch)
    }

    // performFetch: same DispatchSemaphore pattern as GitHubAuthService.performHTTPRequest
    // Returns nil for 404 (no entry), throws for 5xx / network errors
    private static func performFetch(request: URLRequest) throws -> Data? { ... }

    private static func detectWineVersion(wineURL: URL) -> String? { ... }
    private static func detectWineFlavor(wineURL: URL) -> String { ... }
    private static func majorVersion(from versionString: String) -> Int? { ... }
}
```

### Integration point in AIService.runAgentLoop

```swift
// Source: AIService.swift, around line 784
// Before building initialMessage:
var memoryContext = ""
if let result = CollectiveMemoryService.fetchBestEntry(
    for: entry.name,
    wineURL: wineURL
) {
    memoryContext = formatMemoryContext(result.entry, isStale: result.isStale, flavorMismatch: result.flavorMismatch)
}

let initialMessage: String
if memoryContext.isEmpty {
    initialMessage = "Launch the game '\(entry.name)' (ID: \(gameId))..."  // existing text
} else {
    initialMessage = "\(memoryContext)\n\nLaunch the game '\(entry.name)' (ID: \(gameId))..."
}
```

### Wine flavor detection

```swift
// Source: DependencyChecker.detectGPTK() — GPTK is the "game-porting-toolkit" flavor
private static func detectWineFlavor(wineURL: URL) -> String {
    // GPTK binary lives at a known path alongside gameportingtoolkit
    let gptkCandidates = [
        "/usr/local/bin/gameportingtoolkit",
        "/opt/homebrew/bin/gameportingtoolkit"
    ]
    if gptkCandidates.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
        return "game-porting-toolkit"
    }
    return "wine-stable"
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No memory | GitHub repo as shared config store | Phase 13-14 | Zero-infrastructure community memory |
| `application/vnd.github+json` (base64) | `application/vnd.github.v3.raw` (raw bytes) | Always supported | Direct JSON decode, no base64 unwrap step |

---

## Open Questions

1. **Wine flavor detection edge cases**
   - What we know: GPTK is detected by binary presence at two known paths (DependencyChecker.detectGPTK)
   - What's unclear: Are there other Wine variants on macOS (CrossOver, Whisky) that ship their own wine binary? Should they get distinct flavor strings?
   - Recommendation: For Phase 15, use "game-porting-toolkit" vs "wine-stable" as the two flavors (matching what Phase 16 will write). Edge cases can be added in future phases. The flavor field is informational/soft-incompatible only.

2. **What if `entries/{slug}.json` exists but contains an empty array?**
   - What we know: SCHM-02 defines the file as an array of entries. Phase 16 will write to it.
   - What's unclear: Could a file exist with `[]`? Edge case during concurrent write path.
   - Recommendation: `guard !entries.isEmpty` handles this — return nil and proceed with normal R-D-A.

3. **`wine --version` subprocess latency**
   - What we know: Process() calls are synchronous and very fast for `--version` (no wineserver, no prefix init).
   - What's unclear: Could this fail on CI/test environments without Wine?
   - Recommendation: Wrap in `try?` and return nil on failure. If wineVersion is nil, the entire memory fetch is skipped (fallback to normal R-D-A).

---

## Validation Architecture

> `workflow.nyquist_validation` is not present in `.planning/config.json` — skip this section per instructions.

*(config.json has no `nyquist_validation` key — section omitted.)*

---

## Sources

### Primary (HIGH confidence)

- Existing codebase: `GitHubAuthService.swift` — `performHTTPRequest()` pattern, `getToken()` API, `memoryRepo` property
- Existing codebase: `CollectiveMemoryEntry.swift` — full schema from Phase 14, `EnvironmentFingerprint.current()`, `slugify()`
- Existing codebase: `AIService.swift` lines 529–790 — `runAgentLoop()` signature, `initialMessage` construction at line 784
- GitHub REST API docs (confirmed): `Accept: application/vnd.github.v3.raw` returns raw file body for Contents API
- Existing codebase: `DependencyChecker.swift` — `detectGPTK()` for flavor detection

### Secondary (MEDIUM confidence)

- Wine project: `wine --version` output format `"wine-{major}.{minor}"` — stable across versions, confirmed by community docs

### Tertiary (LOW confidence)

- None.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies already in codebase, no new SPM packages
- Architecture: HIGH — integration point explicitly identified, existing patterns reusable directly
- Pitfalls: HIGH — 404 handling and raw Accept header are verified gotchas from GitHub API docs

**Research date:** 2026-03-30
**Valid until:** 2026-04-30 (stable domain — GitHub Contents API is not fast-moving)

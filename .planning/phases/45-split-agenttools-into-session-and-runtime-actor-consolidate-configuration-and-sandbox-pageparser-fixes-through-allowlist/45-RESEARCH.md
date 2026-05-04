# Phase 45: Split AgentTools + Sandbox PageParser — Research

**Researched:** 2026-05-03
**Domain:** Swift refactoring — class split, value-type configuration, URL allowlist security
**Confidence:** HIGH (all findings from direct source audit)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### fetch_page domain policy
- **Strict known wine/gaming allowlist** — not a permissive "block-private-only" filter. The agent should stay focused on wine/gaming research sources.
- **PolicyResources JSON file** — domain list lives in `Sources/cellar/Resources/policy/fetch_page_domains.json`, loaded as `PolicyResources.shared.fetchPageAllowlist: Set<String>`. Consistent with Phase 43 pattern. Adding a new domain = update JSON, no recompile needed.
- **Explicit error on blocked URL** — return `{"error": "Domain not in allowlist", "url": "...", "hint": "Use search_web to find relevant pages first"}`. Agent receives a clear policy signal and can pivot to `search_web`.
- **Initial allowlist** — wine/gaming core: WineHQ, ProtonDB, PCGamingWiki, Steam community, GitHub, Reddit (reddit.com covers all subreddits). Covers ~95% of real agent research. Researcher should audit actual `search_web` result domains to confirm coverage.

#### AgentTools split
- **Claude's Discretion** — whether to use a Swift `actor`, a `struct` extracted from the class, or an `@MainActor`-isolated type. The goal is: session-scoped mutable state is isolated from infrastructure. Call-site impact on AIService and LaunchController should be minimal.
- Existing coordinator role (dispatch in `execute()`, tool definitions, `jsonResult()`) stays in AgentTools.

#### Configuration consolidation
- **Claude's Discretion** — scope is internal agent session state only (the injected constructor args). Does NOT touch CellarConfig (user-visible prefs). A `SessionConfiguration` or similar value type wrapping the current init parameters is the expected shape.

### Claude's Discretion
- Whether the session state type is `actor`, `struct`, or `class`
- Exact naming: `SessionState`, `AgentSession`, `SessionContext`
- Whether AIService and LaunchController pass a single `SessionConfiguration` value or still pass individual args (if the refactor stays internal to AgentTools)
- Specific subdomain matching strategy (e.g., does `github.com` cover `raw.githubusercontent.com`? researcher should verify)

### Deferred Ideas (OUT OF SCOPE)
- **Subdomain expansion of allowlist** — e.g., `raw.githubusercontent.com` as a separate entry from `github.com`. Researcher should verify and decide during planning.
- **Per-game session allowlist extension** — letting a game's wiki page declare additional allowed domains for that game's community. Deferred.
- **HTTPS enforcement** — requiring `https://` for all fetched pages. Deferred.
- **Deletion of legacy services** (CollectiveMemoryService, WikiService wrappers). Deferred.
- **Removal of legacy Worker endpoints** (`/api/contribute`, `/api/wiki/append`). Deferred.
</user_constraints>

---

## Summary

Phase 45 has three workstreams that are independent in implementation but logically coherent: (1) extract mutable session state from `AgentTools` into an isolated type, (2) consolidate the six injected constructor arguments into a `SessionConfiguration` value type, and (3) add a domain allowlist gate in `fetchPage` backed by a new `fetch_page_domains.json` policy file.

The source audit confirms that all mutable state lives clearly in `AgentTools` and is well-categorised. The tool extension files in `Core/Tools/` reference `self` extensively but only for accessing session state (`accumulatedEnv`, `launchCount`, `installedDeps`, etc.) and the injected config (`gameId`, `bottleURL`, etc.). The split boundary is well-defined. There are exactly two `AgentTools` construction sites: `AIService.runAgentLoop()` and `LaunchController.runAgentLaunch()` — both pass the same six parameters.

The PolicyResources loading pattern is already proven across seven policy files. The `winetricks_verbs.json` plain-array pattern (no schema_version wrapper) is the right model for `fetch_page_domains.json`. The domain check in `fetchPage` is a two-line insertion before `URLRequest` creation. The critical non-obvious decision is subdomain matching: `github.com` in the allowlist should also match `raw.githubusercontent.com` because they are the same GitHub service — a suffix-based host check is required, not exact equality. This means the allowlist should contain `githubusercontent.com` separately, or the matching function checks host suffix against each allowlist entry.

**Primary recommendation:** Implement the three workstreams as three sequential plans: P01 = allowlist gate (smallest, standalone), P02 = SessionConfiguration value type (call-site refactor), P03 = session state split (largest, affects all tool extensions).

---

## AgentTools Property Inventory (Source of Truth)

Audited from `Sources/cellar/Core/AgentTools.swift` directly.

### Category A: Injected Immutable Config (init params)
These become `SessionConfiguration`:

| Property | Type | Purpose |
|----------|------|---------|
| `gameId` | `String` | Game identifier, used by every tool |
| `entry` | `GameEntry` | Full game record (name, recipeId, arch, etc.) |
| `executablePath` | `String` | Resolved path to game EXE |
| `bottleURL` | `URL` | Wine prefix directory |
| `wineURL` | `URL` | Path to wine binary |
| `wineProcess` | `WineProcess` | Configured Wine runner |

### Category B: Mutable Session State (split into new type)
These become the isolated session state type:

| Property | Type | Purpose |
|----------|------|---------|
| `accumulatedEnv` | `[String: String]` | Env vars across `set_environment` calls |
| `launchCount` | `Int` | Number of `launch_game` calls |
| `maxLaunches` | `Int` (let) | Max allowed launches per session |
| `installedDeps` | `Set<String>` | Winetricks verbs already installed |
| `lastLogFile` | `URL?` | Log from most recent launch |
| `pendingActions` | `[String]` | Actions since last launch |
| `lastAppliedActions` | `[String]` | Actions at time of last launch |
| `previousDiagnostics` | `WineDiagnostics?` | For inter-launch diff |
| `hasSubstantiveFailure` | `Bool` | Set by `save_failure` tool |
| `sessionShortId` | `String` (let) | Per-session UUID prefix for draft file path |
| `draftBuffer` | `SessionDraftBuffer` (lazy var) | Mid-session wiki observations |

### Category C: Infrastructure / Handlers (stay in AgentTools)
These remain on the coordinator class:

| Property | Type | Purpose |
|----------|------|---------|
| `control` | `AgentControl!` | Thread-safe abort/confirm channel |
| `askUserHandler` | `@Sendable (String, [String]?) -> String` | Callback for agent questions |

---

## Architecture Patterns

### Pattern 1: struct-as-extracted-state (Recommended for session state)

**Why not `actor`:** All tool extension files call session state synchronously via `self.accumulatedEnv`, `self.launchCount`, etc. Converting to an `actor` would require every extension method that mutates state to be marked `async` or use `isolated` parameter annotations. That is a large diff across ~8 extension files (DiagnosticTools, ConfigTools, LaunchTools, SaveTools, ResearchTools, etc.) and fundamentally changes the call signature since `execute()` already bridges async. The class-with-struct approach avoids this churn.

**Why not keeping `@unchecked Sendable` on the full class:** The goal is to be honest about what is mutable. Extracting state into a `final class` (not struct, because `draftBuffer` is a reference type and `SessionDraftBuffer` is already a class) with all the mutable props removes the `@unchecked` escape hatch from the coordinator.

**Recommendation:** Extract mutable state into a new `final class AgentSession` (not actor, not struct — because `SessionDraftBuffer` is a class and lazy var needs reference semantics). `AgentTools` holds `let session: AgentSession`. Tool extensions on `AgentTools` read `self.session.accumulatedEnv`, etc. This is a mechanical rename with zero concurrency model changes. The `@unchecked Sendable` on `AgentTools` can eventually be removed because the mutable state is now isolated into `AgentSession`, but that cleanup is its own step.

```swift
// New type
final class AgentSession {
    var accumulatedEnv: [String: String] = [:]
    var launchCount: Int = 0
    let maxLaunches: Int = 8
    var installedDeps: Set<String> = []
    var lastLogFile: URL? = nil
    var pendingActions: [String] = []
    var lastAppliedActions: [String] = []
    var previousDiagnostics: WineDiagnostics? = nil
    var hasSubstantiveFailure: Bool = false
    let sessionShortId: String = String(UUID().uuidString.prefix(8)).lowercased()
    lazy var draftBuffer: SessionDraftBuffer = SessionDraftBuffer(shortId: sessionShortId)
}

// AgentTools gains:
final class AgentTools: @unchecked Sendable {
    let config: SessionConfiguration
    let session: AgentSession
    var control: AgentControl!
    var askUserHandler: ...
    // execute(), toolDefinitions, jsonResult() unchanged
}
```

Tool extensions change `self.accumulatedEnv` → `self.session.accumulatedEnv`. The change is mechanical and safe.

### Pattern 2: SessionConfiguration value type

**Shape:** A plain `struct` wrapping the six init params. All fields are `let` (immutable, value-type-safe).

```swift
struct SessionConfiguration {
    let gameId: String
    let entry: GameEntry
    let executablePath: String
    let bottleURL: URL
    let wineURL: URL
    let wineProcess: WineProcess
}
```

**AgentTools init becomes:**
```swift
init(config: SessionConfiguration) {
    self.config = config
    self.session = AgentSession()
}
```

**AIService call site change:**
```swift
// Before (6 args):
let tools = AgentTools(
    gameId: gameId,
    entry: entry,
    executablePath: executablePath,
    bottleURL: bottleURL,
    wineURL: wineURL,
    wineProcess: wineProcess
)

// After (1 arg):
let tools = AgentTools(config: SessionConfiguration(
    gameId: gameId,
    entry: entry,
    executablePath: executablePath,
    bottleURL: bottleURL,
    wineURL: wineURL,
    wineProcess: wineProcess
))
```

**LaunchController call site:** `AIService.runAgentLoop` signature also takes the six individual params today and passes them through. This signature should be updated to take `SessionConfiguration` too, OR the `SessionConfiguration` construction can happen inside `runAgentLoop` and only `AgentTools.init` changes. The simplest approach is to update both `AgentTools.init` and `runAgentLoop`'s internal construction, without changing `runAgentLoop`'s public signature (which is called from LaunchController). That keeps LaunchController changes minimal.

### Pattern 3: fetch_page domain allowlist gate

**Insertion point:** `fetchPage` in `Sources/cellar/Core/Tools/ResearchTools.swift`, lines 145-221. The check goes immediately after URL parsing (line 148) and before `URLRequest` creation (line 151).

```swift
func fetchPage(input: JSONValue) async -> String {
    guard let urlStr = input["url"]?.asString, !urlStr.isEmpty,
          let pageURL = URL(string: urlStr) else {
        return jsonResult(["error": "url is required and must be a valid URL"])
    }

    // ── Domain allowlist check (Phase 45) ──
    guard let host = pageURL.host else {
        return jsonResult(["error": "Domain not in allowlist", "url": urlStr,
                           "hint": "Use search_web to find relevant pages first"])
    }
    let allowed = PolicyResources.shared.fetchPageAllowlist
    let domainAllowed = allowed.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
    guard domainAllowed else {
        return jsonResult(["error": "Domain not in allowlist", "url": urlStr,
                           "hint": "Use search_web to find relevant pages first"])
    }
    // ── end allowlist check ──

    var request = URLRequest(url: pageURL)
    // ... rest unchanged
```

**Domain matching:** `host.hasSuffix(".\(entry)")` handles subdomains. `host == entry` handles exact match. This means `winehq.org` in the allowlist covers `appdb.winehq.org` and `winehq.org` itself.

### Pattern 4: fetch_page_domains.json (plain array, no schema_version)

The CONTEXT.md specifies this follows the `winetricks_verbs.json` pattern — a plain JSON array loaded with a custom `init(from:)` using `singleValueContainer`. The Phase 43/44 `winetricks_verbs.json` code in `PolicyResources.swift` (lines 246-261) is the exact template.

```json
[
  "winehq.org",
  "pcgamingwiki.com",
  "protondb.com",
  "steampowered.com",
  "steamcommunity.com",
  "github.com",
  "githubusercontent.com",
  "reddit.com"
]
```

**Subdomain analysis:**
- `winehq.org` covers `appdb.winehq.org`, `forum.winehq.org`
- `pcgamingwiki.com` covers `www.pcgamingwiki.com`
- `protondb.com` covers `www.protondb.com`
- `github.com` covers `gist.github.com` — but NOT `raw.githubusercontent.com` (different apex domain)
- `githubusercontent.com` must be added separately to cover `raw.githubusercontent.com`
- `reddit.com` covers `www.reddit.com`, `old.reddit.com`, all subreddits
- `steamcommunity.com` covers `steamcommunity.com/app/*/discussions`

**Decision:** Add `githubusercontent.com` as a separate entry. The `github.com` + `githubusercontent.com` pair is needed for full GitHub coverage (raw file viewing is a common research target for Wine config files).

### Pattern 5: PolicyResources extension for fetchPageAllowlist

The `winetricks_verbs.json` loading code (lines 246-261 of `PolicyResources.swift`) is the exact template. A `FetchPageDomainsFile` private struct is NOT needed because it's a plain array — the decoder reads directly to `[String].self`. The property is `fetchPageAllowlist: Set<String>`.

```swift
// In PolicyResources.init():
// 8. fetch_page_domains.json — plain JSON array (no schema_version wrapper)
let fetchDomainsURL = policyDir.appendingPathComponent("fetch_page_domains.json")
guard FileManager.default.fileExists(atPath: fetchDomainsURL.path) else {
    throw PolicyError.missingResource("policy/fetch_page_domains.json")
}
let fetchDomainsData: Data
do {
    fetchDomainsData = try Data(contentsOf: fetchDomainsURL)
} catch {
    throw PolicyError.decodingError(file: "policy/fetch_page_domains.json", underlying: error)
}
do {
    let domainsList = try JSONDecoder().decode([String].self, from: fetchDomainsData)
    self.fetchPageAllowlist = Set(domainsList)
} catch {
    throw PolicyError.decodingError(file: "policy/fetch_page_domains.json", underlying: error)
}
```

---

## Standard Stack

This phase is pure Swift refactoring — no new dependencies.

| Technology | Version | Role |
|------------|---------|------|
| Swift | Current project | Language — class/struct/actor choices |
| Foundation | System | URL host extraction (`url.host`) |
| PolicyResources | Internal | Allowlist loading pattern (Phase 43) |
| Swift Testing | System | Test framework (`@Test`, `#expect`) |

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Domain allowlist loading | Custom loader | Follow `winetricks_verbs.json` pattern in PolicyResources.swift | Pattern already proven, tested, has Bundle fallback |
| Subdomain matching | Custom regex | `host.hasSuffix(".\(entry)")` built-in String method | Correct, no edge cases, readable |
| Session state isolation | Swift actor | final class (reference type) | `draftBuffer` (SessionDraftBuffer) is a class; actor would require all mutations to be async |
| Config value type | Protocol/enum | Plain struct with `let` fields | No polymorphism needed, value semantics are correct |

---

## Common Pitfalls

### Pitfall 1: Actor isolation breaks tool extension call sites
**What goes wrong:** If `AgentSession` is declared as `actor`, every extension method in `ConfigTools.swift`, `LaunchTools.swift`, etc. that writes `self.session.accumulatedEnv` needs `await` or an `isolated` parameter. This cascades into changing `execute()` call dispatch and potentially the `ToolResult` return flow.
**Why it happens:** Swift actors enforce async access to mutable state from outside the actor.
**How to avoid:** Use `final class AgentSession` (not `actor`). The `@unchecked Sendable` on `AgentTools` remains until a proper lock is introduced — that is an explicit deferred concern per CONTEXT.md.
**Warning signs:** Build errors about "actor-isolated property can only be accessed from within the actor" appearing across multiple extension files.

### Pitfall 2: `captureHandoff` and post-loop code in AIService reference state properties directly
**What goes wrong:** `AIService.runAgentLoop` (lines 913-936) directly accesses `tools.pendingActions`, `tools.lastAppliedActions`, `tools.launchCount`, `tools.hasSubstantiveFailure`, `tools.draftBuffer`. After the split, these become `tools.session.pendingActions`, etc.
**Why it happens:** The session state split changes property access paths.
**How to avoid:** Systematic grep for `tools\.` in `AIService.swift` during the split. The `captureHandoff()` method inside `AgentTools.swift` also accesses `accumulatedEnv`, `installedDeps`, `launchCount` directly — these become `session.accumulatedEnv`, etc.
**Warning signs:** Build errors on `tools.launchCount` in AIService post-loop section.

### Pitfall 3: Plain-array JSON vs. versioned JSON — wrong loader
**What goes wrong:** Using `loadVersionedJSON` helper (which probes for `schema_version`) on a plain JSON array like `fetch_page_domains.json` will fail because there is no `schema_version` key.
**Why it happens:** Most policy files use versioned JSON; `winetricks_verbs.json` and the new `fetch_page_domains.json` use plain arrays.
**How to avoid:** Use `JSONDecoder().decode([String].self, from: data)` directly — exactly as done for `winetricks_verbs.json` in PolicyResources.swift lines 257-259. Do NOT use `loadVersionedJSON` or `decodeVersionedData`.
**Warning signs:** Runtime `PolicyError.decodingError` at startup.

### Pitfall 4: Host extraction returns nil for malformed URLs
**What goes wrong:** `URL(string: urlStr)` succeeds but `pageURL.host` returns `nil` for some URL forms (e.g., `javascript:` scheme, data URIs).
**Why it happens:** Swift's `URL.host` is optional and returns nil for schemes without a host component.
**How to avoid:** The guard on `pageURL.host` returning an explicit blocked-URL error (not a crash) handles this correctly. The guard is already shown in the code example above.
**Warning signs:** Agent receives a confusing error for a valid-looking URL.

### Pitfall 5: `draftBuffer` lazy var initialization timing
**What goes wrong:** `draftBuffer` is a `lazy var` on `AgentTools` today (initialised on first access, calling `SessionDraftBuffer(shortId: sessionShortId)`). If it moves to `AgentSession`, the `lazy var` semantics still work — but `sessionShortId` must be initialized before `draftBuffer` can be used. Since both are on the same type (`AgentSession`), `let sessionShortId` initialized first in the type's stored properties satisfies this.
**Why it happens:** Swift guarantees stored properties (`let`) are initialized before computed/lazy properties are accessed.
**How to avoid:** In `AgentSession`, declare `sessionShortId` as a `let` property and `draftBuffer` as `lazy var` — this is the same pattern as today, just moved types.
**Warning signs:** N/A if pattern is copied correctly.

---

## Code Examples

### Full fetchPage allowlist check (insertion point)
```swift
// Source: ResearchTools.swift, after URL guard (line 148), before URLRequest (line 151)
guard let host = pageURL.host else {
    return jsonResult(["error": "Domain not in allowlist", "url": urlStr,
                       "hint": "Use search_web to find relevant pages first"])
}
let domainAllowed = PolicyResources.shared.fetchPageAllowlist
    .contains(where: { host == $0 || host.hasSuffix(".\($0)") })
guard domainAllowed else {
    return jsonResult(["error": "Domain not in allowlist", "url": urlStr,
                       "hint": "Use search_web to find relevant pages first"])
}
```

### PolicyResources fetchPageAllowlist property addition
```swift
// In PolicyResources struct definition:
let fetchPageAllowlist: Set<String>

// In PolicyResources.init(), after winetricks_verbs.json block (line 261):
// 8. fetch_page_domains.json — plain JSON array (no schema_version wrapper)
let fetchDomainsURL = policyDir.appendingPathComponent("fetch_page_domains.json")
guard FileManager.default.fileExists(atPath: fetchDomainsURL.path) else {
    throw PolicyError.missingResource("policy/fetch_page_domains.json")
}
let fetchDomainsData = try Data(contentsOf: fetchDomainsURL)
let domainsList = try JSONDecoder().decode([String].self, from: fetchDomainsData)
self.fetchPageAllowlist = Set(domainsList)
```

### AgentSession class structure
```swift
// New file: Sources/cellar/Core/AgentSession.swift
import Foundation

/// Mutable per-session runtime state for the agent loop.
/// Extracted from AgentTools to isolate accumulated state from injected infrastructure.
final class AgentSession {
    var accumulatedEnv: [String: String] = [:]
    var launchCount: Int = 0
    let maxLaunches: Int = 8
    var installedDeps: Set<String> = []
    var lastLogFile: URL? = nil
    var pendingActions: [String] = []
    var lastAppliedActions: [String] = []
    var previousDiagnostics: WineDiagnostics? = nil
    var hasSubstantiveFailure: Bool = false
    let sessionShortId: String = String(UUID().uuidString.prefix(8)).lowercased()
    lazy var draftBuffer: SessionDraftBuffer = SessionDraftBuffer(shortId: sessionShortId)
}
```

### SessionConfiguration struct
```swift
// New file (or in AgentTools.swift): Sources/cellar/Core/SessionConfiguration.swift
import Foundation

/// Immutable per-session context injected into AgentTools at construction.
/// Replaces the six individual constructor parameters.
struct SessionConfiguration {
    let gameId: String
    let entry: GameEntry
    let executablePath: String
    let bottleURL: URL
    let wineURL: URL
    let wineProcess: WineProcess
}
```

### Tool extension self reference migration (example from ConfigTools)
```swift
// Before (any tool extension accessing session state):
self.accumulatedEnv[key] = value
self.launchCount += 1

// After:
self.session.accumulatedEnv[key] = value
self.session.launchCount += 1

// Injected config access:
// Before: self.gameId, self.bottleURL
// After: self.config.gameId, self.config.bottleURL
```

---

## Call-Site Impact Analysis

### AIService.runAgentLoop (primary construction site)
- **Line 680:** `AgentTools(gameId:, entry:, executablePath:, bottleURL:, wineURL:, wineProcess:)` → `AgentTools(config: SessionConfiguration(...))`
- **Lines 913-936 (post-loop):** `tools.pendingActions` → `tools.session.pendingActions`, `tools.lastAppliedActions` → `tools.session.lastAppliedActions`, `tools.launchCount` → `tools.session.launchCount`, `tools.hasSubstantiveFailure` → `tools.session.hasSubstantiveFailure`, `tools.draftBuffer` → `tools.session.draftBuffer`
- **Line 875:** `tools.draftBuffer.notes` → `tools.session.draftBuffer.notes`

### LaunchController.runAgentLaunch
- Does NOT construct `AgentTools` directly — calls `AIService.runAgentLoop(...)` which constructs it
- `AIService.runAgentLoop` public signature stays unchanged (individual params) if `SessionConfiguration` construction stays internal
- `ActiveAgents` stores `AgentTools` — no change needed there
- `onToolsCreated` callback: `((AgentTools, AgentControl) -> Void)` — unchanged

### AgentTools.captureHandoff
- Accesses `accumulatedEnv`, `installedDeps`, `launchCount` directly → becomes `session.accumulatedEnv`, `session.installedDeps`, `session.launchCount`

### Tool extension files (all in Core/Tools/)
Files requiring mechanical `self.X` → `self.session.X` migration for state properties, and `self.Y` → `self.config.Y` for config properties:
- `ConfigTools.swift` — reads/writes `accumulatedEnv`, `installedDeps`; reads `gameId`, `bottleURL`, `wineURL`
- `LaunchTools.swift` — reads/writes `launchCount`, `accumulatedEnv`, `lastLogFile`, `pendingActions`, `lastAppliedActions`, `previousDiagnostics`; reads `gameId`, `executablePath`, `bottleURL`, `wineURL`, `wineProcess`, `entry`
- `DiagnosticTools.swift` — reads `accumulatedEnv`, `installedDeps`; reads `gameId`, `bottleURL`, `wineURL`
- `SaveTools.swift` — reads `accumulatedEnv`, `installedDeps`, `launchCount`; reads `gameId`, `entry`
- `ResearchTools.swift` — reads `gameId`; writes `draftBuffer` (via `updateWiki`)
- Others: read `gameId`, `bottleURL` etc.

---

## Recommended Plan Structure

Three plans, sequenced to minimize mid-phase breakage:

**P01: fetch_page domain allowlist** (independent, standalone, lowest risk)
1. Add `fetch_page_domains.json` to `Sources/cellar/Resources/policy/`
2. Add `fetchPageAllowlist: Set<String>` property to `PolicyResources` struct + loading in `init()`
3. Insert domain check in `ResearchTools.fetchPage` before `URLRequest`
4. Add test for allowlist loading (follows `PolicyResourcesTests` pattern)
5. Add test for blocked-URL error response

**P02: SessionConfiguration value type** (medium, call-site refactor)
1. Create `SessionConfiguration` struct
2. Update `AgentTools.init` to take `SessionConfiguration`
3. Update construction in `AIService.runAgentLoop` (single site)
4. Update all `self.gameId` → `self.config.gameId` etc. across tool extensions
5. Verify build passes

**P03: AgentSession state split** (largest, mechanical rename)
1. Create `AgentSession` final class with all mutable state properties
2. Add `let session: AgentSession` to `AgentTools`; remove mutable state from `AgentTools`
3. Update `captureHandoff()` in `AgentTools.swift`
4. Migrate all tool extension files: `self.X` → `self.session.X`
5. Update post-loop access in `AIService.runAgentLoop`
6. Verify build passes

---

## State of the Art

| Old Approach | Current Approach | Why Changed |
|--------------|------------------|-------------|
| Monolithic AgentTools (all state + coordinator + tools) | Phase 24: tool logic moved to Core/Tools/ extensions | Decomposition for maintainability |
| Phase 24 result: coordinator + state mixed | Phase 45: session state isolated into AgentSession | Further separation of concerns |
| Hardcoded allowlists in Swift literals | Phase 43: PolicyResources JSON files | No-recompile policy updates |
| No fetch_page restrictions | Phase 45: domain allowlist | Security/focus — agent stays on wine/gaming sources |

---

## Open Questions

1. **Should `AgentTools.runAgentLoop` public signature also change to take `SessionConfiguration`?**
   - What we know: LaunchController calls `AIService.runAgentLoop` with six individual args. The `onToolsCreated` callback receives `AgentTools` (unchanged).
   - What's unclear: Whether making the public interface take `SessionConfiguration` has downstream value.
   - Recommendation: Keep `runAgentLoop` signature unchanged. Only change `AgentTools.init` internally. This confines P02 changes to `AgentTools.swift` + tool extensions only, with zero impact on `LaunchController.swift`.

2. **Should `raw.githubusercontent.com` be in the allowlist, or is `githubusercontent.com` sufficient?**
   - What we know: With suffix matching, `githubusercontent.com` in the allowlist covers `raw.githubusercontent.com` (because `"raw.githubusercontent.com".hasSuffix(".githubusercontent.com")` is true).
   - Recommendation: Use `githubusercontent.com` as the entry; suffix matching handles the subdomain automatically.

3. **After the session state split, can `@unchecked Sendable` be removed from AgentTools?**
   - What we know: `askUserHandler` is `@Sendable` closure (OK). `control` is `AgentControl` which is `Sendable` (OK). `config: SessionConfiguration` is a struct with value types (OK). `session: AgentSession` is a `final class` — not Sendable by default.
   - Recommendation: Removing `@unchecked Sendable` is a follow-up. For Phase 45, keep it. The goal is structural cleanup, not full Sendable correctness in one phase.

---

## Sources

### Primary (HIGH confidence)
- Direct source audit: `Sources/cellar/Core/AgentTools.swift` — complete property inventory
- Direct source audit: `Sources/cellar/Core/PolicyResources.swift` — loading pattern, all 7 current files
- Direct source audit: `Sources/cellar/Core/Tools/ResearchTools.swift` — exact fetchPage insertion point
- Direct source audit: `Sources/cellar/Core/AIService.swift` — construction site (line 680), post-loop access (lines 858-936)
- Direct source audit: `Sources/cellar/Web/Controllers/LaunchController.swift` — confirms no direct AgentTools construction; only calls `AIService.runAgentLoop`
- Direct source audit: `Sources/cellar/Core/AgentControl.swift` — confirms `Sendable` (not `@unchecked`)
- Direct source audit: `Sources/cellar/Core/SessionDraftBuffer.swift` — confirms `final class` (reference type — drives AgentSession being a class, not struct)
- Direct source audit: `Tests/cellarTests/PolicyResourcesTests.swift` — test pattern for new policy file test
- Swift documentation (training): `URL.host`, `String.hasSuffix` semantics — HIGH confidence (stable APIs)

### Secondary (MEDIUM confidence)
- Phase 43 CONTEXT.md decisions on PolicyResources pattern — confirmed by source audit

---

## Metadata

**Confidence breakdown:**
- AgentTools property inventory: HIGH — read directly from source
- Split boundary decision: HIGH — driven by SessionDraftBuffer being a class (verified)
- Call-site impact: HIGH — all construction sites located and verified
- fetchPage insertion point: HIGH — exact line numbers verified
- Domain allowlist initial content: HIGH — confirmed by source (search_web classifies winehq, pcgamingwiki, protondb) + CONTEXT.md locked decision
- Subdomain matching: HIGH — Swift String.hasSuffix is stable API

**Research date:** 2026-05-03
**Valid until:** 2026-06-03 (stable codebase, no fast-moving dependencies)

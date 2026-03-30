# Architecture Research: Cellar v1.2 Collective Agent Memory

**Domain:** macOS CLI Wine game launcher — Git-backed collective memory integration
**Researched:** 2026-03-29
**Confidence:** HIGH (GitHub API flows verified against official docs; integration points from direct codebase inspection)

---

## Context: What This File Is

This file covers the **v1.2 integration architecture only** — specifically how Git-backed collective memory and GitHub App authentication integrate with the existing Cellar codebase. The existing architecture (Swift 6 CLI, AgentLoop, AgentTools, AIService, SuccessDatabase, Vapor web server) is documented in prior research files and the current ARCHITECTURE.md. Do not re-litigate those decisions here.

The two core technical questions for v1.2:
1. How does collective memory (Git-backed shared knowledge base) integrate with the agent loop?
2. How does GitHub App bot token authentication work for agent-initiated pushes?

---

## System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                          CLI / Web Commands                           │
│   LaunchCommand   LaunchController (SSE)   MemoryController (NEW)    │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
┌──────────────────────────────┴───────────────────────────────────────┐
│               AIService.runAgentLoop()  (MODIFY)                      │
│   query collective memory BEFORE first API call                       │
│   push to collective memory AFTER user confirms success               │
└───────┬─────────────────────────────────────────────┬────────────────┘
        │                                             │
┌───────┴──────────┐                    ┌────────────┴────────────────┐
│    AgentLoop     │                    │   CollectiveMemoryClient     │
│  (UNCHANGED)     │                    │   (NEW — Core/)              │
│  API state mach. │                    │   query / push operations    │
└──────────────────┘                    └────────────┬────────────────┘
                                                     │
                                        ┌────────────┴────────────────┐
                                        │   GitHubAppAuth              │
                                        │   (NEW — Core/)              │
                                        │   JWT sign → install token   │
                                        └────────────┬────────────────┘
                                                     │
                                        ┌────────────┴────────────────┐
                                        │   GitHub REST API            │
                                        │   PUT /repos/.../contents/.. │
                                        │   GET /repos/.../contents/.. │
                                        └─────────────────────────────┘

Local persistence (existing, UNCHANGED):
  ~/.cellar/games.json
  ~/.cellar/recipes/<gameId>.json
  ~/.cellar/successdb/<gameId>.json

Remote collective memory (NEW):
  GitHub repo: cellar-community/memory
  path: entries/<gameId>.json
  path: entries/<gameId>/<sha>.json  (versioned — optional)
```

---

## New Components

### Component 1: `CollectiveMemoryClient` (NEW)

**File:** `Sources/cellar/Core/CollectiveMemoryClient.swift`

**Responsibility:** All read/write operations against the remote collective memory Git repo. Wraps the GitHub Contents API. Has no awareness of the agent loop — it is a pure data access layer.

**Operations:**
- `query(gameId:) -> CollectiveMemoryEntry?` — GET the entry for a game; returns nil if not found or network unavailable
- `push(entry:) -> Bool` — PUT an updated entry; returns false on auth failure or network error; never throws (caller handles gracefully)
- `queryAll() -> [CollectiveMemoryEntry]` — list all entries (for web UI); uses GET on the directory listing endpoint

**Key design decisions:**
- Synchronous with DispatchSemaphore — matches the existing `AgentLoop` and `AIService` HTTP pattern; no async/await
- Read operations never require auth — public repo, GET is unauthenticated
- Write operations require a GitHub App installation token (via `GitHubAppAuth`)
- Network failure on read is a soft failure: agent proceeds without collective memory context
- Network failure on write is also a soft failure: agent logs it and doesn't block the session

**What it does NOT own:**
- Authentication (delegated to `GitHubAppAuth`)
- Entry schema construction (delegated to caller — `AIService`)
- Caching beyond the session (reads are always live; no local cache of remote entries)

---

### Component 2: `GitHubAppAuth` (NEW)

**File:** `Sources/cellar/Core/GitHubAppAuth.swift`

**Responsibility:** GitHub App authentication flow. Generates RS256 JWTs from the stored private key, exchanges them for installation access tokens, and provides a valid `Bearer` token for REST API calls.

**Operations:**
- `installationToken() throws -> String` — returns a valid installation access token; re-generates JWT and exchanges if token is expired or not yet obtained

**Auth flow (two-step, verified against GitHub docs):**
```
1. Read private key PEM from ~/.cellar/.env (GITHUB_APP_PRIVATE_KEY) or file path
2. Build JWT claims:
     iat = now - 60s  (clock-drift protection)
     exp = now + 300s (5 minutes, well under 10 minute limit)
     iss = app_id
3. Sign JWT with RS256 using SecKeyCreateSignature(.rsaSignatureMessagePKCS1v15SHA256)
4. POST /app/installations/{installation_id}/access_tokens with JWT in Authorization: Bearer
5. Cache returned token (expires_at - 5 minute buffer) for the session
```

**No new SPM dependency needed.** RS256 JWT signing uses Apple's `Security` framework (`SecKeyCreateSignature`), which is already available on macOS 14+. PEM private key loading strips the `-----BEGIN RSA PRIVATE KEY-----` headers, base64-decodes to DER, and imports via `SecKeyCreateWithData`. This is approximately 60-80 lines of Swift and requires no external library.

**Configuration (stored in `~/.cellar/.env`):**
```
GITHUB_APP_ID=123456
GITHUB_APP_PRIVATE_KEY_PATH=~/.cellar/github-app.pem
GITHUB_APP_INSTALLATION_ID=789012
GITHUB_MEMORY_REPO=cellar-community/memory
```

**Token lifetime:** Installation access tokens expire after 1 hour. `GitHubAppAuth` caches the token with a 5-minute safety buffer and re-authenticates transparently when stale.

---

### Component 3: `CollectiveMemoryEntry` schema (NEW)

**File:** `Sources/cellar/Models/CollectiveMemoryEntry.swift`

**What it stores per game:**
```swift
struct CollectiveMemoryEntry: Codable {
    let schemaVersion: Int           // 1
    let gameId: String
    let gameName: String
    let updatedAt: String            // ISO8601
    let confirmations: Int           // number of agents that confirmed this works
    let workingConfig: WorkingConfig // env vars, DLL overrides, registry, winetricks
    let reasoningChain: String       // agent's narrative of how it solved the game
    let environmentContext: EnvContext // wine version, macOS version, arch at solve time
    let tags: [String]               // engine, graphics api, source (gog, steam)
}

struct WorkingConfig: Codable {
    let environment: [String: String]
    let dllOverrides: [String: String]
    let winetricksVerbs: [String]
    let registryEntries: [RegistryRecord]
    let notes: String?
}

struct EnvContext: Codable {
    let wineVersion: String?
    let macosVersion: String
    let arch: String              // "arm64", "x86_64"
    let cellarVersion: String
}
```

**Relationship to `SuccessRecord`:** `CollectiveMemoryEntry` is derived from `SuccessRecord` but is leaner — it omits file-by-file install details that are machine-specific (paths, SHA hashes) and retains only the transferable configuration (env vars, DLL modes, winetricks verbs, registry). The `reasoningChain` field is new: it is the agent's final `finalText` from `AgentLoopResult`, truncated to ~2000 chars.

**Storage location in Git repo:**
```
entries/
  cossacks-european-wars.json   ← one file per game, content is CollectiveMemoryEntry
  civilization-3.json
  ...
```

Single file per game (not versioned per-solve). Confirmations increment in-place. This keeps the read path simple (one GET per game), avoids merge conflicts across machines (last-write-wins is acceptable for a best-effort knowledge base), and keeps the repo small.

---

### Component 4: `MemoryController` (NEW for web UI)

**File:** `Sources/cellar/Web/Controllers/MemoryController.swift`

**Responsibility:** Vapor routes for the web interface's collective memory view.

**Routes:**
- `GET /memory` — renders Leaf template showing all collective memory entries (name, confirmations, wine version, last updated)
- `GET /memory/:gameId` — renders detail view for a single game's entry (working config, reasoning chain, environment context)

**Integration:** Calls `CollectiveMemoryClient.queryAll()` for the list view. Registered in `WebApp.configure()`.

---

## Modified Components

### `AIService.runAgentLoop()` (MODIFY)

**Current flow:**
1. Detect provider
2. Build system prompt
3. Create `AgentTools`
4. Create `AgentLoop`
5. Call `agentLoop.run()`

**v1.2 flow — two additions:**

**Before the loop (step 2.5 — query):**
```swift
// 2.5: Query collective memory (best-effort, never blocks)
let memoryEntry = CollectiveMemoryClient.query(gameId: gameId)
let memoryContext = memoryEntry.map { entry in
    """
    Collective memory has a working config for this game (\(entry.confirmations) confirmation(s)):
    - Wine env: \(entry.workingConfig.environment)
    - DLL overrides: \(entry.workingConfig.dllOverrides)
    - Winetricks: \(entry.workingConfig.winetricksVerbs)
    - Reasoning: \(entry.reasoningChain.prefix(500))
    - Solved with Wine \(entry.environmentContext.wineVersion ?? "unknown") on macOS \(entry.environmentContext.macosVersion)
    Before applying this config, reason about whether it fits your local environment.
    """
} ?? "No collective memory entry found for this game."
```

This context is injected into the initial user message (not the system prompt), so the agent sees it as part of the task description for this specific game.

**After the loop (step 6 — push on success):**
```swift
// 6: Push to collective memory if agent confirmed success
if result.stopReason == .completed, let successRecord = SuccessDatabase.load(gameId: gameId) {
    let entry = CollectiveMemoryEntry.from(
        successRecord: successRecord,
        reasoningChain: result.finalText,
        existingEntry: memoryEntry  // to increment confirmations
    )
    let pushed = CollectiveMemoryClient.push(entry: entry)
    if !pushed { emit(.status("[Collective memory push skipped — auth not configured or network error]")) }
}
```

**What does NOT change:** `AgentLoop`, `AgentTools`, `BottleManager`, `SuccessDatabase` — none of these are modified. The collective memory integration is entirely in the `AIService` orchestration layer, which already owns the "before" and "after" the loop.

---

### `CellarPaths` (MINOR MODIFY)

Add path for the GitHub App private key file:

```swift
static let githubAppKeyFile: URL = base.appendingPathComponent("github-app.pem")
```

---

### `WebApp.configure()` (MINOR MODIFY)

Register the new `MemoryController` routes:
```swift
try MemoryController.register(app)
```

---

### `CellarConfig` (MINOR MODIFY)

Add GitHub App configuration fields (optional — push is skipped if not configured):
```swift
struct CellarConfig: Codable {
    // ... existing fields ...
    var githubAppId: String?
    var githubInstallationId: String?
    var githubMemoryRepo: String?     // "owner/repo"
    var githubAppKeyPath: String?     // path to .pem file
}
```

These can also be read from `~/.cellar/.env` — environment vars take precedence (matches existing `AIService.loadEnvironment()` pattern).

---

### `SettingsController` (MINOR MODIFY)

Add collective memory configuration fields to the web settings page: GitHub App ID, installation ID, memory repo, key path. Read-only display of whether collective memory is configured and the last push status.

---

## What Does NOT Change

The following existing components require **zero modification** for v1.2:

| Component | Reason |
|-----------|--------|
| `AgentLoop.swift` | Loop knows nothing about collective memory — it just runs iterations |
| `AgentTools.swift` | No new agent tools for collective memory — read/write is orchestration, not agent decision |
| `BottleManager.swift` | Bottle management is local |
| `SuccessDatabase.swift` | Local DB unchanged — collective memory derives from it but doesn't replace it |
| `RecipeEngine.swift` | Recipe layer unchanged |
| `GameEntry.swift` | Model unchanged |
| `LaunchCommand.swift` | Entry point calls `AIService.runAgentLoop()` — no changes needed there |
| `LaunchController.swift` | Same — SSE streaming of agent events unchanged |
| `GameController.swift` | Game CRUD routes unchanged |

The agent does NOT get new tools for reading or writing collective memory. The query and push happen in the `AIService` orchestration layer, not in the agent loop. This preserves the agent's role as a problem-solver (using its tools to diagnose and fix) rather than a data curator (managing knowledge base records). The agent's reasoning chain and final success record are captured automatically after the fact.

---

## Data Flow

### Read path — agent query before session starts

```
cellar launch cossacks-european-wars
      │
      ▼
AIService.runAgentLoop()
      │
      ├─► CollectiveMemoryClient.query("cossacks-european-wars")
      │       │
      │       ├─► GET https://api.github.com/repos/{owner}/{repo}/contents/entries/cossacks-european-wars.json
      │       │   (unauthenticated — public repo)
      │       │
      │       ├─► response: base64-encoded JSON → decode → CollectiveMemoryEntry
      │       │
      │       └─► returns: CollectiveMemoryEntry (or nil if 404 / network error)
      │
      ├─► Inject memory context into initial user message
      │
      └─► AgentLoop.run()
              │
              └─► agent sees: "Collective memory has a working config: ..."
                  agent reasons: "Does this config fit my Wine 9.0 / macOS 15.2 environment?"
                  agent applies or adapts config via existing tools
```

### Write path — push after successful session

```
AgentLoop.run() returns AgentLoopResult (completed=true)
      │
      ▼
AIService.runAgentLoop() — post-loop phase
      │
      ├─► SuccessDatabase.load(gameId)     ← local record written by agent's save_success tool
      │       └─► SuccessRecord (env vars, DLL overrides, reasoning, etc.)
      │
      ├─► CollectiveMemoryEntry.from(successRecord, reasoningChain, existingEntry)
      │       └─► builds entry; if existingEntry exists, increments confirmations
      │
      └─► CollectiveMemoryClient.push(entry)
              │
              ├─► GitHubAppAuth.installationToken()
              │       │
              │       ├─► load PEM key from ~/.cellar/github-app.pem
              │       ├─► sign RS256 JWT with Security framework
              │       ├─► POST /app/installations/{id}/access_tokens
              │       └─► returns: "ghs_xxxx" installation token (1hr expiry)
              │
              ├─► GET current file SHA (needed for update, not for create)
              │   GET /repos/{owner}/{repo}/contents/entries/{gameId}.json
              │   → extract .sha from response (or nil if 404 = new file)
              │
              └─► PUT /repos/{owner}/{repo}/contents/entries/{gameId}.json
                  body: {
                    message: "cellar: update config for cossacks-european-wars",
                    content: base64(JSON.encode(entry)),
                    sha: existing_sha_or_nil,
                    branch: "main"
                  }
                  headers: Authorization: Bearer {installationToken}
```

### Web UI read path

```
Browser → GET /memory
      │
      ▼
MemoryController.index()
      │
      ├─► CollectiveMemoryClient.queryAll()
      │       └─► GET /repos/{owner}/{repo}/contents/entries/
      │           → list of file metadata objects
      │           → parallel GET for each entry file
      │           → decode each CollectiveMemoryEntry
      │
      └─► render memory/index.leaf with entries list
```

---

## Recommended Project Structure

```
Sources/cellar/
├── Commands/                        # UNCHANGED
├── Core/
│   ├── AgentLoop.swift              # UNCHANGED
│   ├── AgentTools.swift             # UNCHANGED
│   ├── AIService.swift              # MODIFY: query before loop, push after loop
│   ├── CollectiveMemoryClient.swift # NEW: GitHub Contents API read/write
│   ├── GitHubAppAuth.swift          # NEW: JWT sign + installation token exchange
│   ├── BottleManager.swift          # UNCHANGED
│   ├── GameEngineDetector.swift     # UNCHANGED
│   ├── ProactiveConfigurator.swift  # UNCHANGED
│   └── SuccessDatabase.swift        # UNCHANGED
├── Models/
│   ├── CollectiveMemoryEntry.swift  # NEW: shared knowledge base entry schema
│   ├── GameEntry.swift              # UNCHANGED
│   ├── Recipe.swift                 # UNCHANGED
│   └── WineResult.swift             # UNCHANGED
├── Persistence/
│   ├── CellarConfig.swift           # MODIFY: add GitHub App config fields
│   ├── CellarPaths.swift            # MODIFY: add github-app.pem path
│   └── CellarStore.swift            # UNCHANGED
└── Web/
    ├── Controllers/
    │   ├── GameController.swift     # UNCHANGED
    │   ├── LaunchController.swift   # UNCHANGED
    │   ├── MemoryController.swift   # NEW: /memory routes
    │   └── SettingsController.swift # MODIFY: add memory config fields
    ├── Services/                    # UNCHANGED
    └── WebApp.swift                 # MODIFY: register MemoryController
```

---

## Architectural Patterns

### Pattern 1: Best-Effort Collective Memory Read

**What:** Query the remote repo before starting the agent loop. If the query fails (network down, repo not configured), the agent proceeds without collective context — it falls back to the same behavior as before v1.2.

**Why this pattern:** Collective memory is an enhancement, not a requirement. The agent was already capable of solving games independently. A hard dependency on network availability would break every offline session and frustrate users who haven't configured GitHub App auth.

**Implementation signal:** `CollectiveMemoryClient.query()` returns `CollectiveMemoryEntry?` (never throws). Nil means "not found or unavailable" — the caller injects a different initial message either way.

**Trade-off:** Agents could theoretically start sessions independently and produce divergent configs. Acceptable — the confirmation count surfaces which configs are broadly verified vs. single-agent findings.

---

### Pattern 2: Post-Loop Push on Success

**What:** Write to collective memory only after the agent loop has completed with `completed = true` AND the user has confirmed success (the `save_success` tool sets `taskState = .savedAfterConfirm` which leads to `stopReason = .completed`). The push happens in `AIService`, not inside the agent loop, not inside any agent tool.

**Why this pattern:** The agent should not manage its own knowledge base contributions during an active session. It would distract from the problem-solving task, use up API budget, and require new tools that would introduce authentication complexity into `AgentTools`. Keeping the push in `AIService` as post-processing is clean and doesn't change the agent's tool surface.

**Trade-off:** If the user kills the process between `AgentLoop.run()` completing and the push finishing, the push is lost. Acceptable — the local `SuccessDatabase` always has the record; the push is best-effort contribution to the collective.

---

### Pattern 3: Incremental Confirmation (No Merge Conflicts)

**What:** When an agent pushes to a game that already has a collective memory entry, it reads the existing entry (getting its `sha` for the update), increments `confirmations`, and writes the new version with the same `sha` (PUT endpoint requires the current `sha` for updates). The new `workingConfig` replaces the old one if the new entry's `confirmations` is higher or if the environment context is more recent.

**Why this pattern:** The GitHub Contents API uses a `sha`-based optimistic locking approach for updates — the caller provides the current blob SHA, and if it has changed since the GET (another agent pushed at the same moment), the PUT returns 409 Conflict. This is extremely unlikely in practice (two agents pushing the same game within seconds). On conflict, the implementation retries once with a fresh GET. This avoids the complexity of a separate conflict-resolution service.

**Trade-off:** Last write wins in normal operation. For the use case (sharing game compatibility configs across users), this is entirely appropriate — minor config differences between solving agents are irrelevant compared to the value of having the entry exist at all.

---

### Pattern 4: Agent Reasons Before Applying Collective Memory

**What:** The agent is explicitly told in the initial message to reason about environment compatibility before applying a remembered config. The config is presented as "this worked for Wine X on macOS Y with these settings" — not as "apply this config now."

**Why this pattern:** A config that worked on Wine 9.0 / macOS 14 / Intel may not work on Wine 10.0 / macOS 15 / ARM. The agent already has inspect_game, read_registry, and query_successdb tools. It should use them to validate fit, not blindly apply a remembered config. The system prompt should reinforce this.

**Implementation:** The initial message includes environment context from the stored entry (wine version, macOS version, arch). The agent's existing reasoning about environment differences (already part of its system prompt) handles the comparison.

---

## Integration Points

### External Services

| Service | Integration Pattern | Auth | Notes |
|---------|---------------------|------|-------|
| GitHub Contents API (read) | Synchronous HTTP GET via DispatchSemaphore (same pattern as `AgentLoop`) | None — public repo | Returns base64-encoded file content |
| GitHub Contents API (write) | Synchronous HTTP PUT via DispatchSemaphore | GitHub App installation token (Bearer) | Requires `sha` of existing file for updates |
| GitHub App authentication | POST /app/installations/{id}/access_tokens | RS256 JWT signed with private key | Token valid 1 hour; cache with 5min buffer |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `AIService` → `CollectiveMemoryClient` | Direct call, returns optional struct | NEW. Both sides synchronous. |
| `CollectiveMemoryClient` → `GitHubAppAuth` | Direct call, returns token string or throws | NEW. Called only on write path. |
| `CollectiveMemoryEntry` ← `SuccessRecord` | Static factory method `CollectiveMemoryEntry.from(successRecord:reasoningChain:existingEntry:)` | NEW. Derives lean entry from rich local record. |
| `AIService` → `SuccessDatabase` | Existing static call unchanged | Used to load success record for push. |
| `MemoryController` → `CollectiveMemoryClient` | Direct call from Vapor route handler | NEW. Web UI only. |

---

## Anti-Patterns

### Anti-Pattern 1: Agent Tools for Collective Memory Read/Write

**What people might do:** Add `query_collective_memory` and `push_collective_memory` as agent tools so the agent can decide when to query or contribute.

**Why it's wrong:** The agent should not make authentication calls or manage knowledge base writes during an active problem-solving session. Agent tool invocations consume API budget and iterations. Collective memory is infrastructure supporting the agent, not a tool the agent wields. It also unnecessarily exposes GitHub App credentials to the agent's reasoning context.

**Do this instead:** `AIService.runAgentLoop()` owns the query (before the loop) and the push (after the loop). The agent sees the query result as context in its initial message and never needs to know that a push happened.

---

### Anti-Pattern 2: Git CLI for Collective Memory Operations

**What people might do:** Clone the memory repo to disk, write files, and push using `git` command-line via `Foundation.Process`.

**Why it's wrong:** This requires a local clone of the memory repo (disk space, sync complexity, stale clone management), a git credential helper for authentication (complex on macOS for non-interactive processes), and git CLI availability (not guaranteed). The GitHub Contents API is purpose-built for reading and writing individual files via authenticated HTTP — exactly what's needed here.

**Do this instead:** GitHub Contents API (`GET /repos/.../contents/...` and `PUT /repos/.../contents/...`) handles read and write of single files with SHA-based optimistic locking. No local clone needed.

---

### Anti-Pattern 3: Storing Collective Memory in the Main Cellar Repo

**What people might do:** Store collective memory entries as files committed to the main `cellar` GitHub repository alongside the source code.

**Why it's wrong:** Mixing user-contributed game configs with application source creates merge conflict noise in PRs, makes the repo history hard to read, and requires human review of PRs for content that should be machine-contributed. Community members contributing to the source code should not have to wade through game config auto-commits.

**Do this instead:** A dedicated `cellar-community/memory` repository (separate from the source repo). The GitHub App is installed on that repo only, with `contents: write` permission scoped to it. Source code and community configs remain cleanly separated.

---

### Anti-Pattern 4: Blocking the Agent on Memory Push Failure

**What people might do:** Treat a failed memory push as an error that surfaces to the user ("Collective memory push failed — check your GitHub App credentials").

**Why it's wrong:** The primary value of a session is that the game launched successfully. A failed push to the community knowledge base is a background failure that should be logged but not surfaced as a user-facing error. Users who haven't configured GitHub App auth at all (the majority, at first) should not see scary errors.

**Do this instead:** `CollectiveMemoryClient.push()` returns `Bool` (never throws). `AIService` logs a status event on failure (visible in agent logs, not as a UI error). The game still launched — that's the success.

---

### Anti-Pattern 5: Caching Remote Entries Locally

**What people might do:** Cache queried collective memory entries in `~/.cellar/` to speed up subsequent queries.

**Why it's wrong:** Collective memory entries are expected to be updated by other agents between sessions. A stale local cache is worse than no cache — it tells the current agent that config X works when the community has since discovered it doesn't on newer Wine versions. The value of collective memory is its freshness.

**Do this instead:** Always query live at the start of each session. The query is a single HTTP GET and completes in under 500ms on a normal connection. If the network is unavailable, `CollectiveMemoryClient.query()` returns nil and the agent proceeds without the context — same as pre-v1.2 behavior.

---

## Build Order

Dependencies determine order. Items at the same level can be built in parallel.

```
Level 1 — no Cellar dependencies:
  ├─ GitHubAppAuth.swift
  │      Security framework JWT generation + installation token exchange
  │      Can be unit-tested standalone before anything else
  │
  └─ CollectiveMemoryEntry.swift  (model only)
         Codable struct, no behavior, no dependencies

Level 2 — depends on Level 1:
  ├─ CollectiveMemoryClient.swift
  │      Uses GitHubAppAuth for write path
  │      Uses CollectiveMemoryEntry as return/input type
  │      Integration tests: real GitHub API with test repo
  │
  └─ CellarPaths + CellarConfig modifications
         Add github-app.pem path, config fields
         Trivial — can be done in parallel with Level 1

Level 3 — depends on Level 2:
  ├─ AIService.runAgentLoop() modifications
  │      Query before loop (uses CollectiveMemoryClient)
  │      Push after loop (uses CollectiveMemoryClient + SuccessDatabase)
  │      This is the primary integration point
  │
  └─ CollectiveMemoryEntry.from(successRecord:...) factory method
         Derives entry from SuccessRecord; needs both types

Level 4 — depends on Level 3:
  └─ MemoryController + web UI Leaf templates
         GET /memory, GET /memory/:gameId
         Uses CollectiveMemoryClient.queryAll()
         Register in WebApp.configure()

Level 5 — integration and validation:
  └─ End-to-end test: solve a game, confirm success, verify push to test repo,
         launch again, verify agent sees the memory context in initial message
```

### Recommended Delivery Sequence

| Phase | Builds | Rationale |
|-------|--------|-----------|
| 1 | `GitHubAppAuth` | Cryptographic auth is the critical path and most unknown. Build and validate against real GitHub API before anything else. |
| 2 | `CollectiveMemoryClient` (read path only) | Validate GET works before adding write complexity. |
| 3 | `AIService` — query integration | Inject memory context into initial message. Test that agent reasoning incorporates it. |
| 4 | `CollectiveMemoryClient` (write path) + push integration in `AIService` | Write path requires auth. Build on validated read path. |
| 5 | Web UI `MemoryController` | Lower risk, depends on all core pieces. Can ship after CLI push is working. |
| 6 | End-to-end: solve game → push → new session sees context | Full flow validation across two agent sessions. |

---

## Scaling Considerations

This is a single-user CLI tool. Scaling considerations are limited to the shared GitHub repo:

| Concern | Impact | Approach |
|---------|--------|----------|
| Multiple agents pushing the same game simultaneously | 409 Conflict on PUT | Retry once with fresh GET to resolve SHA mismatch |
| Large memory repo (100s of games) | `queryAll()` becomes slow | Lazy: `queryAll()` only for web UI; `query(gameId:)` for CLI sessions |
| GitHub API rate limits (unauthenticated GET) | 60 requests/hour per IP | Collective memory queries are one GET per session — effectively no concern |
| GitHub API rate limits (authenticated PUT) | 5000 requests/hour per installation token | Push is at most one per successful session — effectively no concern |

---

## Sources

- [GitHub REST API: Repository Contents (PUT endpoint)](https://docs.github.com/en/rest/repos/contents) — verified March 2026; `PUT /repos/{owner}/{repo}/contents/{path}` requires `message`, `content` (base64), optional `sha` for updates
- [GitHub REST API: GitHub Apps — Installation Tokens](https://docs.github.com/en/rest/apps/apps) — verified March 2026; `POST /app/installations/{id}/access_tokens` returns token valid 1 hour; `contents: write` permission required for file writes
- [GitHub Docs: Generating a JWT for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app) — verified March 2026; RS256, iat=now-60s, exp=now+300s, iss=app_id
- [Apple Security framework: SecKeyCreateSignature](https://developer.apple.com/documentation/security/seckeycreatesignature(_:_:_:_:)) — `.rsaSignatureMessagePKCS1v15SHA256` for RS256 signing; no CryptoKit required for RSA
- Direct inspection of `AIService.swift`, `AgentLoop.swift`, `AgentTools.swift`, `SuccessDatabase.swift`, `CellarPaths.swift`, `CellarConfig.swift`, `WebApp.swift`, `LaunchController.swift` (2026-03-29)
- Direct inspection of `Package.swift` — confirmed current dependencies: ArgumentParser, SwiftSoup, Vapor, Leaf (no JWT library present; Security framework approach avoids adding one)
- [Letta: Git-backed memory for coding agents](https://www.letta.com/blog/context-repositories) — design pattern context for Git as agent memory backing store
- [GitHub Blog: Building an agentic memory system](https://github.blog/ai-and-ml/github-copilot/building-an-agentic-memory-system-for-github-copilot/) — collective knowledge sharing patterns

---
*Architecture research for: Cellar v1.2 Collective Agent Memory*
*Researched: 2026-03-29*

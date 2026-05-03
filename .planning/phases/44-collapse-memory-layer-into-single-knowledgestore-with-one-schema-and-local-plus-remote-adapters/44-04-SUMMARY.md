---
phase: 44
plan: 04
subsystem: memory-layer
tags: [knowledge-store, wiring, thin-wrappers, migration, agent-loop]
depends_on:
  - 44-01
  - 44-03
dependency_graph:
  requires:
    - KnowledgeStore protocol (44-01)
    - KnowledgeStoreRemote adapter (44-03)
    - PolicyResources.winetricksVerbAllowlist (43-01)
  provides:
    - KnowledgeStoreContainer.shared as live read+write path
    - Four legacy services as thin wrappers (safe to call, delegate to store)
    - No allowlist duplication (winetricks verbs in PolicyResources only)
  affects:
    - AIService.runAgentLoop (all five memory call sites)
    - ResearchTools.queryWiki (routes through store)
    - WikiIngestService.ingest (writes via store)
tech_stack:
  added: []
  patterns:
    - Single-writer-at-startup pattern (KnowledgeStoreContainer, matches PolicyResources)
    - Thin wrapper pattern (legacy services preserve public API, delegate body to store)
    - Actor-based StubKnowledgeStore for integration tests (.serialized suite)
key_files:
  created:
    - Tests/cellarTests/KnowledgeStoreIntegrationTests.swift
  modified:
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Core/AgentTools.swift
    - Sources/cellar/Core/KnowledgeStore.swift
    - Sources/cellar/Core/CollectiveMemoryService.swift
    - Sources/cellar/Core/CollectiveMemoryWriteService.swift
    - Sources/cellar/Core/WikiService.swift
    - Sources/cellar/Core/WikiIngestService.swift
    - Sources/cellar/Core/Tools/ResearchTools.swift
decisions:
  - NoOpKnowledgeStore promoted from private to internal — required for `is NoOpKnowledgeStore` startup guard in AIService
  - KnowledgeStoreRemote registered at runAgentLoop entry (not app init) — matches PolicyResources.shared pattern; idempotent guard prevents double-init
  - agentValidWinetricksVerbs literal deleted; replaced with computed var delegating to PolicyResources.shared.winetricksVerbAllowlist — callers (ConfigTools, CollectiveMemoryService) unchanged
  - CollectiveMemoryService keeps sanitizeEntry and private helpers — sanitizeEntry is tested by SecurityTests and must remain for the security test suite
  - WikiService keeps formatSessionEntry/formatFailureEntry/scrubPaths helpers — extracted as internal static shims (sessionLogFilename, formatSuccessSessionBody, formatFailureSessionBody, buildIngestedGamePage) so AIService can build typed KnowledgeEntry values
  - Integration tests use .serialized suite — prevents race conditions on nonisolated(unsafe) KnowledgeStoreContainer.shared
  - WikiService.search always returns String (never nil) — preserves RESEARCH.md pitfall #7 contract; returns "No relevant wiki pages found for '...'" on empty results
metrics:
  duration: 622 seconds (~10 min)
  completed_date: "2026-05-03"
  tasks: 2
  files_modified: 8
  files_created: 1
---

# Phase 44 Plan 04: Wire Cutover — AIService + Legacy Wrappers Summary

KnowledgeStoreContainer.shared is now the single live data path for all game knowledge reads and writes. Four legacy services (CollectiveMemoryService, CollectiveMemoryWriteService, WikiService, WikiIngestService) are thin wrappers that delegate to the store. The hardcoded `agentValidWinetricksVerbs` Set literal is deleted; all callers read `PolicyResources.shared.winetricksVerbAllowlist`.

## What Was Built

### Task 1: Startup wiring + AIService rewire + agentValidWinetricksVerbs deletion

**Startup registration** (`AIService.runAgentLoop` line ~673):
```swift
if KnowledgeStoreContainer.shared is NoOpKnowledgeStore {
    KnowledgeStoreContainer.shared = KnowledgeStoreRemote()
}
```
NoOpKnowledgeStore was promoted from `private` to `internal` to allow this type check.

**Five AIService call sites rewired:**

1. **fetchContext** (line ~779): `WikiService.fetchContext(engine:)` → `KnowledgeStoreContainer.shared.fetchContext(for:environment:)`
2. **gamePage write** (success path ~853): `WikiService.ingest(record:)` → `KnowledgeStoreContainer.shared.write(.gamePage(...))`
3. **sessionLog write** (success path ~868): `WikiService.postSessionLog(...)` → `KnowledgeStoreContainer.shared.write(.sessionLog(...))`
4. **failure sessionLog write** (failure path ~903): `WikiService.postFailureSessionLog(...)` → `KnowledgeStoreContainer.shared.write(.sessionLog(...))`
5. **config write** (handleContributionIfNeeded ~983): `CollectiveMemoryWriteService.push(...)` → `KnowledgeStoreContainer.shared.write(.config(...))`

**agentValidWinetricksVerbs:** `static let ... = Set<String> = [...]` deleted. Replaced with:
```swift
static var agentValidWinetricksVerbs: Set<String> {
    PolicyResources.shared.winetricksVerbAllowlist
}
```
All callers (ConfigTools, CollectiveMemoryService) continue to compile unchanged.

**Internal static shims added** (so AIService compiles without Task 2 wrappers):
- `WikiService.sessionLogFilename(record:)`, `failureSessionLogFilename(gameId:)`
- `WikiService.formatSuccessSessionBody(...)`, `formatFailureSessionBody(...)`
- `WikiService.buildIngestedGamePage(record:) -> GamePageEntry?`
- `CollectiveMemoryWriteService.buildConfigEntry(record:gameName:wineURL:) -> CollectiveMemoryEntry?`
- `CollectiveMemoryService.detectWineVersionInternal(wineURL:)`, `detectWineFlavorInternal(wineURL:)`
- `AIService.fetchKnowledgeContext(gameName:wineURL:) async -> String?` (internal test seam)

### Task 2: Four legacy services converted to thin wrappers + ResearchTools rewired

**CollectiveMemoryService.fetchBestEntry** — body replaced with:
```swift
let env = EnvironmentFingerprint.current(...)
return await KnowledgeStoreContainer.shared.fetchContext(for: gameName, environment: env)
```
Kept: `sanitizeEntry` (heavily tested by SecurityTests), private Wine detection helpers, `majorVersion`/`macosMajorVersion` (still referenced by remaining helpers).

**CollectiveMemoryWriteService.push** — body replaced with:
```swift
guard let entry = buildConfigEntry(...) else { return }
await KnowledgeStoreContainer.shared.write(.config(entry))
```
`syncAll` continues to work (calls `push` which delegates). `postToProxy` kept as dead private code (future deletion phase).

**WikiService.fetchContext** — delegates to `KnowledgeStoreContainer.shared.fetchContext`.
**WikiService.search** — delegates to `KnowledgeStoreContainer.shared.list + fetchContext`. ALWAYS returns non-nil String.
**WikiService.postSessionLog** — builds `SessionLogEntry` using `sessionLogFilename`/`formatSuccessSessionBody` shims, writes via store.
**WikiService.postFailureSessionLog** — same pattern for failure.
**WikiService.ingest** — calls `buildIngestedGamePage` then `KnowledgeStoreContainer.shared.write(.gamePage(...))`.
**WikiIngestService.ingest** — final `WikiService.postWikiAppend(...)` call replaced with `KnowledgeStoreContainer.shared.write(.gamePage(entry))`.
**ResearchTools.queryWiki** — replaced `WikiService.search(query:)` with direct `KnowledgeStoreContainer.shared.list(filter:)` + `fetchContext` calls, plus `formatQueryWikiResult` helper.

## Final Shape of Each Thin Wrapper

| Service | Public body lines | Remaining helpers |
|---------|-------------------|-------------------|
| CollectiveMemoryService | ~6 lines | sanitizeEntry (tested), Wine detection, formatConfigBlock, formatMemoryContext |
| CollectiveMemoryWriteService | ~5 lines | buildConfigEntry, detectWineVersion/Flavor, logPushEvent, postToProxy (dead) |
| WikiService | ~8 lines per method | All formatters (sessionLogFilename, formatSuccessSessionBody, etc.) |
| WikiIngestService | 1 changed line | TTL check, source aggregation, formatGamePage (all kept) |

## KnowledgeStoreContainer.shared Initialization

**File:** `Sources/cellar/Core/AIService.swift`
**Location:** First 5 lines of `runAgentLoop` method body (before `systemPrompt` construction)
**Pattern:** `if KnowledgeStoreContainer.shared is NoOpKnowledgeStore { ... }` (idempotent guard)

## Final Grep Counts

| Pattern | Count |
|---------|-------|
| `agentValidWinetricksVerbs` literal Set definition | 0 (deleted) |
| `agentValidWinetricksVerbs` computed var (delegates to PolicyResources) | 1 |
| `KnowledgeStoreContainer.shared` in Sources/cellar/Core/ | 34 |
| `WikiService.postSessionLog` live call in AIService.swift | 0 |
| `WikiService.postFailureSessionLog` live call in AIService.swift | 0 |
| `CollectiveMemoryWriteService.push` live call in AIService.swift | 0 |

## Test Results

- **Total tests:** 232 (219 pre-existing + 13 new integration tests)
- **Failures:** 1 (pre-existing: "Kimi default model is moonshot-v1-128k" — unrelated to this plan)
- **New tests file:** `Tests/cellarTests/KnowledgeStoreIntegrationTests.swift`
  - `StubKnowledgeStore` actor records fetchContextCalls, writeCalls, listCalls
  - `.serialized` suite prevents race conditions on nonisolated(unsafe) shared singleton
  - 7 Task 1 tests + 6 Task 2 wrapper delegation tests = 13 total

## Smoke Tests

Smoke tests deferred to phase verification (require running `cellar serve` with a live game):
- `cellar serve` + launch game: context built via KnowledgeStoreContainer.shared.fetchContext; session log written via write(.sessionLog)
- `cellar wiki ingest <game>`: GamePageEntry built in WikiIngestService, written via write(.gamePage), fenced merge active in Worker (Plan 02)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing functionality] NoOpKnowledgeStore visibility**
- **Found during:** Task 1 startup wiring
- **Issue:** `private struct NoOpKnowledgeStore` could not be used in `is NoOpKnowledgeStore` type check from AIService
- **Fix:** Promoted to `internal struct NoOpKnowledgeStore`
- **Files modified:** `Sources/cellar/Core/KnowledgeStore.swift`
- **Commit:** eded7ff

**2. [Rule 1 - Bug] Integration test race condition**
- **Found during:** Task 1 test development
- **Issue:** Tests using a non-serialized `withStub` closure had race conditions against the nonisolated(unsafe) singleton, causing `calls.count == 0` failures
- **Fix:** Switched to `.serialized` suite attribute + direct `defer { KnowledgeStoreContainer.shared = original }` pattern per test
- **Files modified:** `Tests/cellarTests/KnowledgeStoreIntegrationTests.swift`
- **Commit:** eded7ff

## Notes for Future Deletion Phase

**Safe to delete (no unique logic):**
- `CollectiveMemoryWriteService.push` — now 3 lines, only calls `buildConfigEntry` + `KnowledgeStoreContainer.shared.write`
- `WikiService.fetchContext`, `WikiService.search`, `WikiService.ingest`, `WikiService.postSessionLog`, `WikiService.postFailureSessionLog` — all 3-8 line wrappers
- `CollectiveMemoryService.fetchBestEntry` — 3 line wrapper
- `WikiIngestService` — could be simplified further now that the POST is one line

**Still have unique helpers (must migrate before deletion):**
- `CollectiveMemoryService.sanitizeEntry` — tested by SecurityTests; should move to KnowledgeStoreRemote's sanitizer (already reimplemented there) or standalone sanitizer type
- `WikiService.buildIngestedGamePage`, `formatSuccessSessionBody`, `formatFailureSessionBody` — body-building logic needed by AIService call sites; move to KnowledgeEntry factory methods or AIService directly
- `CollectiveMemoryWriteService.buildConfigEntry` — needed by AIService; move to KnowledgeEntry factory or AIService
- `WikiIngestService` TTL check, source aggregation, `formatGamePage` — unique ingest pipeline; move inline to IngestCommand or a new WikiPageBuilder type

## Self-Check: PASSED

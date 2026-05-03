---
phase: 44-collapse-memory-layer-into-single-knowledgestore-with-one-schema-and-local-plus-remote-adapters
plan: 01
subsystem: memory
tags: [swift, knowledge-store, codable, cache, policy-resources, winetricks]

# Dependency graph
requires:
  - phase: 43-extract-agent-policy-data-to-versioned-resources-and-achieve-provider-parity-for-tool-use-across-anthropic-deepseek-and-kimi
    provides: PolicyResources Bundle.module dual-layout pattern; AgentToolCall struct; provider parity

provides:
  - KnowledgeEntry discriminated union (config/gamePage/sessionLog) with Codable {kind, entry} wire format
  - KnowledgeStore protocol with fetchContext/write/list methods
  - KnowledgeStoreContainer.shared (NoOp default; replaced in Plan 04)
  - KnowledgeCache struct with TTL fresh/stale/missing file behavior
  - KnowledgeWriteRequest outer envelope matching Worker API wire shape
  - PolicyResources.shared.winetricksVerbAllowlist backed by winetricks_verbs.json

affects:
  - 44-02: Worker endpoint for knowledge writes (consumes KnowledgeEntry wire format)
  - 44-03: KnowledgeStoreRemote and KnowledgeStoreLocal adapters (implement KnowledgeStore protocol, use KnowledgeCache)
  - 44-04: AIService wiring (sets KnowledgeStoreContainer.shared at startup, deletes AgentTools winetricks literal)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Discriminated-union Codable via CodingKeys{kind, entry} — unknown kinds throw DecodingError, no silent default"
    - "KnowledgeStoreContainer enum with nonisolated(unsafe) static var — single-writer-at-startup, same as PolicyResources"
    - "KnowledgeCache key-as-path convention — / in key creates subdirectories under cacheDir"
    - "typealias ConfigEntry = CollectiveMemoryEntry — zero schema duplication, clean type alias"

key-files:
  created:
    - Sources/cellar/Core/KnowledgeEntry.swift
    - Sources/cellar/Core/KnowledgeStore.swift
    - Sources/cellar/Core/KnowledgeCache.swift
    - Sources/cellar/Resources/policy/winetricks_verbs.json
    - Tests/cellarTests/KnowledgeEntryTests.swift
    - Tests/cellarTests/KnowledgeCacheTests.swift
  modified:
    - Sources/cellar/Core/PolicyResources.swift
    - Tests/cellarTests/PolicyResourcesTests.swift

key-decisions:
  - "winetricks_verbs.json is a plain JSON array (no schema_version wrapper) — simpler than versioned format since verbs don't need migration path; loaded with JSONDecoder().decode([String].self)"
  - "typealias ConfigEntry = CollectiveMemoryEntry chosen over wrapper struct — zero schema duplication, type identity preserved"
  - "KnowledgeCache key-as-path convention: '/' in key creates subdirectories — matches how CollectiveMemoryService caches memory/{slug}.json"
  - "KnowledgeWriteRequest delegates to KnowledgeEntry.encode(to:) — reuses existing {kind, entry} shape rather than wrapping it"
  - "NoOpKnowledgeStore is private to KnowledgeStore.swift — callers must go through KnowledgeStoreContainer.shared, reducing accidental direct instantiation"

patterns-established:
  - "KnowledgeStore.fetchContext(for:environment:) — EnvironmentFingerprint parameter matches existing CollectiveMemoryService scoring approach"
  - "readStale(key:) never deletes — stale-on-failure resilience pattern from CollectiveMemoryService preserved"

requirements-completed: [KS-FOUNDATION, KS-POLICY-WINETRICKS]

# Metrics
duration: 5min
completed: 2026-05-03
---

# Phase 44 Plan 01: KnowledgeStore Foundation Summary

**KnowledgeEntry discriminated union, KnowledgeStore protocol, KnowledgeCache TTL helper, and winetricks verbs moved to PolicyResources — all tested with 19 new passing tests**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-03T23:16:18Z
- **Completed:** 2026-05-03T23:20:49Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- `winetricks_verbs.json` policy resource created with exact 22-verb set; `PolicyResources.shared.winetricksVerbAllowlist` available and proven equal to `AIService.agentValidWinetricksVerbs` (loss-free move)
- `KnowledgeEntry` enum encodes/decodes all three kinds (config/gamePage/sessionLog) with `{"kind":"...","entry":{...}}` wire shape; unknown kind throws `DecodingError` with no silent fallback
- `KnowledgeStore` protocol + `KnowledgeStoreContainer.shared` (NoOp default) + `KnowledgeCache` struct with TTL-based fresh/stale/missing logic — all compile-clean with zero changes to existing services

## Task Commits

Each task was committed atomically:

1. **Task 1: Move winetricks verbs to PolicyResources** - `1c72152` (feat)
2. **Task 2: Define KnowledgeEntry + KnowledgeStore + KnowledgeCache** - `94f5c49` (feat)

**Plan metadata:** (added in final commit)

_Note: Both tasks used TDD (RED → GREEN). No separate REFACTOR commits were needed._

## Files Created/Modified

- `Sources/cellar/Core/KnowledgeEntry.swift` — KnowledgeEntry enum, GamePageEntry, SessionLogEntry, KnowledgeWriteRequest, KnowledgeListFilter, KnowledgeEntryMeta
- `Sources/cellar/Core/KnowledgeStore.swift` — KnowledgeStore protocol, KnowledgeStoreContainer, NoOpKnowledgeStore
- `Sources/cellar/Core/KnowledgeCache.swift` — KnowledgeCache struct with read/readStale/write/isFresh/fileURL
- `Sources/cellar/Resources/policy/winetricks_verbs.json` — plain JSON array of 22 winetricks verbs
- `Sources/cellar/Core/PolicyResources.swift` — added `winetricksVerbAllowlist: Set<String>` field + loading code
- `Tests/cellarTests/KnowledgeEntryTests.swift` — 7 tests covering all 3 Codable kinds, unknown kind error, wire shape, kind/slug properties
- `Tests/cellarTests/KnowledgeCacheTests.swift` — 5 tests covering nil-on-missing, write/read round-trip, isFresh within TTL, isFresh expired TTL, readStale
- `Tests/cellarTests/PolicyResourcesTests.swift` — 3 new tests: non-empty, equality to AgentTools literal, Bundle lookup

## Decisions Made

- `winetricks_verbs.json` is a plain JSON array (no `schema_version` wrapper) — simpler to load since the verb list has no migration path requirement
- `typealias ConfigEntry = CollectiveMemoryEntry` chosen over a wrapper struct — zero schema duplication
- `KnowledgeWriteRequest` delegates encode to `KnowledgeEntry.encode(to:)` — reuses the `{kind, entry}` shape
- `KnowledgeCache` key-as-path: `/` in key creates subdirectories; convention for Plan 03: `~/.cellar/cache/knowledge/{kind}/{slug}`

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. The 1 pre-existing test failure (`Kimi default model is moonshot-v1-128k`) was already documented in STATE.md as unrelated to this work.

## Note for Plan 03 Author

Cache directory convention chosen: `KnowledgeCache` treats `/` in keys as subdirectory separators. Suggested convention:
- Config entries: `config/{slug}` → `~/.cellar/cache/knowledge/config/{slug}`
- Game pages: `gamePage/{slug}` → `~/.cellar/cache/knowledge/gamePage/{slug}`
- Session logs: `sessionLog/{slug}` → `~/.cellar/cache/knowledge/sessionLog/{slug}`

The `KnowledgeStoreContainer.shared` is currently a `NoOpKnowledgeStore`. Plan 04 replaces it with `KnowledgeStoreRemote` (or local adapter) at AIService startup.

## Next Phase Readiness

- KnowledgeStore protocol locked — Plan 02 (Worker) and Plan 03 (adapters) can implement against it
- KnowledgeEntry wire format defined — Worker can implement `/api/knowledge/write` endpoint
- winetricksVerbAllowlist on PolicyResources — Plan 04 can delete `AIService.agentValidWinetricksVerbs` literal without risk
- All 201 tests green (1 pre-existing Kimi model name failure unrelated)

---
*Phase: 44-collapse-memory-layer-into-single-knowledgestore-with-one-schema-and-local-plus-remote-adapters*
*Completed: 2026-05-03*

## Self-Check: PASSED

All created files verified present. Both task commits (1c72152, 94f5c49) verified in git log.

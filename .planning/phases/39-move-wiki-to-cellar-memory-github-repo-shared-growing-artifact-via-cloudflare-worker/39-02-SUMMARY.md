---
phase: 39-move-wiki-to-cellar-memory
plan: 02
subsystem: wiki
tags: [wiki, cloudflare-worker, async-await, post-proxy]

# Dependency graph
requires:
  - phase: 39-P01
    provides: WikiService async read path (fetchContext/search via GitHub raw)
  - phase: 39-P03
    provides: POST /api/wiki/append Worker endpoint contract
  - phase: 38-rebuild-memory-layer
    provides: WikiService.ingest derivation logic (pitfalls/engine/DLL overrides/log.md)
provides:
  - WikiService.ingest async — POSTs each derived update to Cloudflare Worker wiki endpoint
  - WikiAppendPayload Encodable struct inside WikiService
  - postWikiAppend(page:entry:commitMessage:) private helper
  - CELLAR_WIKI_PROXY_URL env var override support
affects:
  - phase-39-P04 (SPM bundle cleanup — Bundle.module now fully removed from ingest path)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "wikiProxyURL reuses cellar-memory-proxy.sook40.workers.dev host, changes path to /api/wiki/append"
    - "postWikiAppend mirrors CollectiveMemoryWriteService.postToProxy: URLRequest, 10s timeout, fputs stderr on non-2xx"
    - "ingest() is async, best-effort, never throws — matches CollectiveMemoryWriteService.push semantics"
    - "No local dedup in ingest — Worker handles substring dedup server-side (P03)"

key-files:
  created: []
  modified:
    - Sources/cellar/Core/WikiService.swift
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "wikiProxyURL host copied verbatim from CollectiveMemoryWriteService (sook40.workers.dev) — only path changes to /api/wiki/append"
  - "log.md entry POSTed unconditionally (not gated on pagesUpdated) — Worker handles dedup; simpler ingest flow"
  - "findBestMatch return type changed from String? to String (always returns at least crash-on-launch) — removes optional unwrap inside ingest loop"

requirements-completed: []

# Metrics
duration: ~3 min
completed: 2026-04-11
---

# Phase 39 Plan 02: WikiService Ingest Write Path via Worker Summary

**WikiService.ingest rewritten as async function that POSTs each derived wiki update to the Cloudflare Worker wiki-append endpoint instead of writing to local Bundle.module paths**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-11T01:58:00Z
- **Completed:** 2026-04-11T02:01:57Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Removed all `appendIfNew`, `FileHandle`, and `Bundle.module` local write code from WikiService.ingest
- Added `WikiAppendPayload` Encodable struct, `wikiProxyURL` computed var, and `postWikiAppend` async helper mirroring CollectiveMemoryWriteService pattern
- `ingest(record:)` is now `async`, fires POSTs for pitfalls / engine pages / DLL overrides / log.md entry
- `CELLAR_WIKI_PROXY_URL` env var allows override of production Worker URL
- AIService call site updated to `await WikiService.ingest(record:)` — adjacent to `CollectiveMemoryWriteService.push`
- `swift build` succeeds with zero errors; no remaining synchronous `WikiService.ingest` call sites

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite WikiService.ingest to POST via Cloudflare Worker** - `1c92d65` (feat)
2. **Task 2: Await WikiService.ingest in AIService didSave block** - `de8ba0b` (feat)

## Files Created/Modified

- `Sources/cellar/Core/WikiService.swift` — Removed appendIfNew/FileHandle/Bundle.module from ingest; added WikiAppendPayload, wikiProxyURL, postWikiAppend; ingest is now async
- `Sources/cellar/Core/AIService.swift` — Added `await` to WikiService.ingest call inside post-save block

## Decisions Made

- `wikiProxyURL` host copied verbatim from `CollectiveMemoryWriteService.proxyURL` (`cellar-memory-proxy.sook40.workers.dev`); only the path changes to `/api/wiki/append`. No invented hostname.
- `log.md` entry is POSTed unconditionally (not gated on whether other pages were updated) — the Worker's substring dedup prevents duplicate log entries; simpler ingest flow.
- `findBestMatch` return type narrowed from `String?` to `String` — it already fell back to `"symptoms/crash-on-launch.md"` and the caller always unwrapped it, so removing the optional is cleaner.

## Deviations from Plan

None — plan executed exactly as written.

The plan's code sketch showed `wikiProxyURL` host as `cellar-memory-proxy.lasermaze.workers.dev`; the IMPORTANT note in the plan explicitly instructed to read CollectiveMemoryWriteService.swift and copy the host verbatim. The actual host (`sook40.workers.dev`) was used instead of the sketch placeholder — this is the intended behavior per the plan note.

## Issues Encountered

None.

## User Setup Required

None — CELLAR_WIKI_PROXY_URL is optional; the default production Worker URL is used automatically.

## Next Phase Readiness

- Write path is complete: every confirmed save by the agent fires wiki append POSTs to the shared Worker endpoint
- P04 can now safely remove `Sources/cellar/wiki/` directory and `.copy("wiki")` from Package.swift — no code references Bundle.module wiki bundle anymore

---
*Phase: 39-move-wiki-to-cellar-memory*
*Completed: 2026-04-11*

## Self-Check: PASSED

All files present and task commits verified.

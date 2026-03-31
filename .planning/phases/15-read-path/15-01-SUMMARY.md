---
phase: 15-read-path
plan: 01
status: complete
started: "2026-03-30"
completed: "2026-03-30"
---

# Plan 15-01 Summary: CollectiveMemoryService

## What was built
Created `CollectiveMemoryService` — a stateless service that fetches a game's collective memory entry from the GitHub repo, filters by arch compatibility, ranks by confirmations (tiebreak by Wine version proximity), assesses staleness and flavor mismatch, and formats a human-readable context block.

## Key files

### Created
- `Sources/cellar/Core/CollectiveMemoryService.swift` — Full service with `fetchBestEntry(for:wineURL:)` public API

## Technical decisions
- All errors swallowed — returns nil for any failure (auth, network, decode, empty results)
- Synchronous fetch via DispatchSemaphore pattern (matches GitHubAuthService)
- 5-second timeout on GitHub API request
- Arch filtering is hard incompatible (entries dropped entirely)
- Staleness threshold: localMajor - entryMajor > 1

## Deviations
None.

## Self-Check: PASSED
- CollectiveMemoryService.swift exists with fetchBestEntry public static method
- Arch filtering, ranking, staleness, flavor mismatch all implemented
- Project compiles cleanly with `swift build`

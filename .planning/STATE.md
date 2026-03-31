---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Collective Agent Memory
status: unknown
last_updated: "2026-03-31T20:15:51.960Z"
progress:
  total_phases: 21
  completed_phases: 19
  total_plans: 47
  completed_plans: 47
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-30)

**Core value:** Any user can go from "I have these old game files" to "the game launches and works" without manually configuring Wine.
**Current focus:** Phase 14 — Collective Memory Read Path (next)

## Current Position

Phase: 19 of 21 (Import Lutris and ProtonDB Compatibility Databases) — Complete
Plan: 2 of 2 complete
Status: Phase 19 complete — CompatibilityService data layer + agent integration (auto-inject + query_compatibility tool + system prompt guidance).
Last activity: 2026-03-31 — Phase 19 Plan 02: Agent integration

Progress: [████████████████████] ~55% (13 of ~22 phases complete across all milestones)

## Performance Metrics

**Velocity (v1.1 reference):**
- Total plans completed: 13 (phases 8–12)
- Average duration: ~3.5 min/plan

**v1.1 by phase:**

| Phase | Plans | Avg/Plan |
|-------|-------|----------|
| Phase 8 | 2 | 1.5 min |
| Phase 9 | 2 | 3.5 min |
| Phase 10 | 2 | 2.5 min |
| Phase 11 | 3 | 2.3 min |
| Phase 12 | 4 | 5.8 min |

*Updated after each plan completion*
| Phase 13-github-app-authentication P01 | 1 | 2 tasks | 4 files |
| Phase 13-github-app-authentication P02 | 2 | 2 tasks | 1 files |
| Phase 18-deepseek-api-support P01 | 12 | 2 tasks | 3 files |
| Phase 14-memory-entry-schema P01 | 3 | 2 tasks | 2 files |
| Phase 15-read-path P02 | 5 | 1 tasks | 1 files |
| Phase 16-write-path P01 | 3 | 2 tasks | 3 files |
| Phase 16-write-path P02 | 1 | 1 tasks | 2 files |
| Phase 17-web-memory-ui P01 | 6 | 2 tasks | 6 files |
| Phase 19-import-lutris-and-protondb-compatibility-databases P01 | 2 | 2 tasks | 2 files |
| Phase 19-import-lutris-and-protondb-compatibility-databases P02 | 8 | 2 tasks | 2 files |

## Accumulated Context

### Decisions

- [v1.2 roadmap]: No new SPM dependencies — Security.framework for RS256 JWT; URLSession already handles all API calls
- [v1.2 roadmap]: GitHub App private key ships with CLI (accepted risk, rotate if abused — token proxy deferred to v1.3)
- [v1.2 roadmap]: One JSON file per game in collective memory repo: entries/{game-id}.json
- [v1.2 roadmap]: Integration point is AIService.runAgentLoop() — agent tools (AgentLoop, AgentTools) stay untouched
- [v1.2 roadmap]: Read path before write path — validate concept before committing to public repo
- [v1.2 roadmap]: Opt-in contribution prompt on first run; preference saved in CellarConfig
- [Phase 12-04]: SSE event types: status, log, iteration, tool, cost, error, complete for granular UI updates
- [Phase 13-01]: GitHubAppConfig.appID uses String to accept both numeric App IDs and string Client IDs
- [Phase 13-01]: Placeholder credentials use empty strings — loader returns .unavailable rather than crashing
- [Phase 13-01]: CellarPaths.defaultMemoryRepo centralizes the collective memory repo slug
- [Phase 13-github-app-authentication]: @unchecked Sendable on GitHubAuthService — NSLock provides external synchronization for Swift 6 mutable global state
- [Phase 13-github-app-authentication]: JWT iat=now-60 (clock skew buffer) and exp=now+510 (8.5-min window under GitHub 10-min max) per GitHub recommendations
- [Phase 18-deepseek-api-support]: deepseek-chat as default Deepseek model (deepseek-reasoner excluded — no function calling support)
- [Phase 18-deepseek-api-support]: AgentLoopProvider protocol owns message array — AgentLoop never holds provider-specific message types
- [Phase 18-02]: Provider created after systemPrompt is built (late binding) to avoid placeholder pattern
- [Phase 18-02]: Budget warning injection uses appendUserMessage() after appendToolResults() for cross-provider clean abstraction
- [Phase 14-memory-entry-schema]: Default synthesized Codable on CollectiveMemoryEntry types — unknown future JSON fields silently ignored without custom init(from:)
- [Phase 14-memory-entry-schema]: slugify() uses unicodeScalars for locale-independent slug generation
- [Phase 14-memory-entry-schema]: EnvironmentFingerprint canonicalString uses sorted keys for hash stability; CryptoKit (system framework) for SHA-256 with no new SPM dependency
- [Phase 15-read-path]: Memory context injected as prefix to launchInstruction in initialMessage — agent sees community config before any tool calls
- [Phase 15-read-path]: fetchBestEntry placed after AgentTools creation (wineURL available) but before initialMessage construction — no changes to AgentTools or AgentLoop
- [Phase 16-write-path]: isWebContext flag passed to handleContributionIfNeeded since askUserHandler always has a default value in AgentTools
- [Phase 16-write-path]: CollectiveMemoryWriteService uses GET+merge+PUT pattern with 409 retry; all failures logged to memory-push.log
- [Phase 16-write-path P02]: Separate POST /settings/config from /settings/keys — config.json and .env have distinct persistence layers
- [Phase 17-web-memory-ui]: MemoryStats.isAvailable: false when auth unavailable — template shows Settings guidance instead of error
- [Phase 17-web-memory-ui]: fetchGameDetail(slug:) returns nil on any failure — MemoryController passes nil to template for graceful empty state
- [Phase 19-import-lutris-and-protondb-compatibility-databases]: ExtractedEnvVar/DLL/Verb/Registry use context field (not source) — matched actual PageParser.swift struct fields
- [Phase 19-01]: CompatibilityService.fetchReport returns nil for empty report — caller never receives useless data
- [Phase 19-02]: Compatibility data position in contextParts: after collective memory (higher confidence), before session handoff and launch instruction
- [Phase 19-02]: query_compatibility returns plain string on no-match (not JSON error) — keeps agent context human-readable

### Roadmap Evolution

- Phase 18 added (2026-03-30): Deepseek API Support — alternative AI provider alongside Claude
- Phase 19 added (2026-03-31): Import Lutris and ProtonDB compatibility databases
- Phase 20 added (2026-03-31): Smarter Wine log parsing and structured diagnostics
- Phase 21 added (2026-03-31): Pre-flight dependency check from PE imports

### Pending Todos

None.

### Blockers/Concerns

- Phase 13: Token proxy architecture deferred — CLI ships the GitHub App private key directly. Document rotation procedure before Phase 13 ships.
- Phase 14: Collective memory repo org/name (assumed cellar-community/memory) and GitHub App ID/installation ID need a concrete decision before Phase 13 auth code is finalized.
- Phase 16: Confidence deduplication mechanism (per-environment-hash, stored in entry JSON) needs concrete design before Phase 16 begins.

## Session Continuity

Last session: 2026-03-31
Stopped at: Completed 19-02-PLAN.md — Agent integration: auto-inject compatibility data into initial message, query_compatibility tool, system prompt guidance.

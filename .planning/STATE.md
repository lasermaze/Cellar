---
gsd_state_version: 1.0
milestone: v1.3
milestone_name: Agent Loop Rewrite
status: unknown
last_updated: "2026-04-11T01:59:28.868Z"
progress:
  total_phases: 39
  completed_phases: 36
  total_plans: 85
  completed_plans: 83
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-03)

**Core value:** Any user can go from "I have these old game files" to "the game launches and works" without manually configuring Wine.
**Current focus:** v1.3 — Agent Loop Rewrite (bug fixes + architecture modernization)

## Current Position

Phase: 39 (Move Wiki to cellar-memory GitHub repo) — P01 complete
Plan: P01 complete — WikiService read path migrated to async cache+GitHub-raw; all callers awaited
Status: Phase 39 P01 complete — swift build zero errors; fetchContext/search async; ~/.cellar/wiki/ cache path
Last activity: 2026-04-11 — P01 complete: WikiService.fetchContext and .search are async; cache at ~/.cellar/wiki/; stale-on-failure; AIService/ResearchTools/AgentTools callers awaited

Progress: [█████░░░░░░░░░░░░░░░] 25% (Phase 39 — P01 read path async+cache complete)

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
| Phase 20-smarter-wine-log-parsing-and-structured-diagnostics P01 | 15 | 2 tasks | 6 files |
| Phase 20-smarter-wine-log-parsing-and-structured-diagnostics P02 | 10 | 2 tasks | 2 files |
| Phase 22-seamless-macos-ux P01 | 82 | 2 tasks | 5 files |
| Phase 22-seamless-macos-ux P02 | 2 | 2 tasks | 4 files |
| Phase 22-seamless-macos-ux P03 | 4 | 2 tasks | 2 files |
| Phase 23-homebrew-tap-distribution-with-launcher-app P02 | 1 | 2 tasks | 2 files |
| Phase 23-homebrew-tap-distribution-with-launcher-app P01 | 1 | 2 tasks | 2 files |
| Phase 24-architecture-code-quality-cleanup P03 | 15 | 2 tasks | 4 files |
| Phase 24-architecture-code-quality-cleanup P02 | 19 | 2 tasks | 6 files |
| Phase 25-kimi-model-support P02 | 3 | 2 tasks | 2 files |
| Phase 26-iso-disc-image-support-for-game-installation P01 | 2 | 1 tasks | 1 files |
| Phase 26-iso-disc-image-support-for-game-installation P02 | 4 | 1 tasks | 1 files |
| Phase 27-distribution-github-releases-install-script P01 | 1 | 1 tasks | 1 files |
| Phase 27-distribution-github-releases-install-script P02 | 1 | 1 tasks | 1 files |
| Phase 28-fix-collective-memory-prompt-injection-vulnerability P02 | 174 | 2 tasks | 3 files |
| Phase 28-fix-collective-memory-prompt-injection-vulnerability P01 | 4 | 2 tasks | 2 files |
| Phase 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key P01 | 2 | 2 tasks | 4 files |
| Phase 29 P02 | 8 | 2 tasks | 3 files |
| Phase 29 P03 | 8 | 2 tasks | 7 files |
| Phase 31-new-types P02 | 2 | 1 tasks | 2 files |
| Phase 31 PP01 | 101 | 2 tasks | 1 files |
| Phase 32-middleware-system P01 | 2 | 2 tasks | 1 files |
| Phase 32-middleware-system P02 | 1 | 2 tasks | 2 files |
| Phase 33-rewrite-the-loop P01 | 134 | 2 tasks | 1 files |
| Phase 34-update-agenttools P01 | 8 | 2 tasks | 1 files |
| Phase 35-wire-it-together PP01 | 2 | 2 tasks | 4 files |
| Phase 36-event-log-resume P01 | 8 | 2 tasks | 2 files |
| Phase 36-event-log-resume P01 | 8 | 2 tasks | 2 files |
| Phase 37-supporting-win32-apps P01 | 8 | 2 tasks | 5 files |
| Phase 37-supporting-win32-apps P02 | 2 | 2 tasks | 4 files |
| Phase 38-rebuild-memory-layer P01 | 5 | 2 tasks | 13 files |
| Phase 38-rebuild-memory-layer P03 | 4 | 2 tasks | 2 files |
| Phase 38-rebuild-memory-layer-shared-wiki-for-agents-based-on-karpathy-principles P02 | 8 | 2 tasks | 3 files |
| Phase 39-move-wiki-to-cellar-memory P03 | 2 | 2 tasks | 1 files |
| Phase 39-move-wiki-to-cellar-memory P01 | 2 | 3 tasks | 5 files |

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
- [Phase 20-01]: parseLegacy() wraps parse() for backward compat — callers using [WineError] array migrate without logic changes
- [Phase 20-01]: Causal chains detected in a post-pass after all lines parsed — avoids ordering sensitivity
- [Phase 20-01]: filteredLog() derives subsystem membership from WineDiagnostics fields, not re-parsing stderr
- [Phase 20-02]: Action tracking appended in execute() dispatch after tool call returns — single instrumentation point covers all tools without modifying each handler
- [Phase 20-02]: DiagnosticRecord injected into initial message only when previousSession is nil — avoids doubling context when SessionHandoff already provides last-session summary
- [Phase 22-seamless-macos-ux]: PermissionChecker uses CGPreflightScreenCaptureAccess() — advisory only, never blocks launch
- [Phase 22-seamless-macos-ux]: Only Screen Recording checked — Accessibility deferred (no current code uses Accessibility API per research)
- [Phase 22-seamless-macos-ux]: GameRemover always does full cleanup regardless of cleanBottle parameter — web delete now always removes all artifacts
- [Phase 22-seamless-macos-ux]: games.json removal is critical (throws on failure); artifact deletions use try? so missing files are silently skipped
- [Phase 22-seamless-macos-ux]: AddCommand re-checks DependencyStatus after each install step; winetricks not installed inline (only needed per-game); LaunchCommand falls back to first discovered exe when recipe name not matched
- [Phase 23-homebrew-tap-distribution-with-launcher-app]: Binary resolved via (path as NSString).resolvingSymlinksInPath to follow Homebrew symlinks; app path derived as ../libexec/Cellar.app relative to bin dir — no brew --prefix subprocess needed
- [Phase 23-homebrew-tap-distribution-with-launcher-app]: Use cellar-community/homebrew-cellar as placeholder tap org — user updates before first release
- [Phase 23-homebrew-tap-distribution-with-launcher-app]: Formula .app pattern: create in libexec, copy to ~/Applications via cellar install-app subcommand
- [Phase 23-homebrew-tap-distribution-with-launcher-app]: CellarLauncher polls 20x0.5s for port 8080 (not fixed sleep) and uses opt_bin DSL path (not hardcoded prefix)
- [Phase 24-architecture-code-quality-cleanup]: fputs(message, stderr) used for service error logging — keeps agent stdout clean while exposing GitHub API failures via terminal
- [Phase 24-architecture-code-quality-cleanup]: 404 and auth-unavailable paths not logged in collective memory services — expected graceful degradation, not errors
- [Phase 24-architecture-code-quality-cleanup]: AgentTools.swift keeps only coordinator code (state, init, captureHandoff, toolDefinitions, execute(), jsonResult()) — all tool implementations moved to Core/Tools/ extension files
- [Phase 24-architecture-code-quality-cleanup]: searchWeb/fetchPage migrated from DispatchSemaphore+ResultBox to URLSession async/await during AgentTools decomposition
- [Phase 25-kimi-model-support]: Followed deepseekKey pattern exactly for Kimi settings — same masking, .env write/delete logic, struct field placement
- [Phase 26-iso-disc-image-support-for-game-installation]: Separate DiscImageHandler struct (not inlined in AddCommand) — follows GuidedInstaller/WinetricksRunner isolation pattern
- [Phase 26-iso-disc-image-support-for-game-installation]: CRawDiskImage attempted first for .bin; convert to CDR only as fallback — avoids unnecessary temp files
- [Phase 26-iso-disc-image-support-for-game-installation]: effectiveInstallerURL shadows installerURL for pipeline — no conditional branches needed in downstream code
- [Phase 27-distribution-github-releases-install-script]: Homebrew formula update step removed from release workflow — formula update is now a separate manual or tap-side concern
- [Phase 27-distribution-github-releases-install-script]: Checksum generated as separate .sha256 file so install.sh can download and verify independently
- [Phase 27-distribution-github-releases-install-script]: xattr -rd ... || true is critical in install.sh — xattr exits 1 when no quarantine attribute exists, which would abort under set -e
- [Phase 27-distribution-github-releases-install-script]: install.sh shasum verification uses cd into TMPDIR first so relative filename in .sha256 resolves correctly
- [Phase 28-02]: OriginCheckMiddleware uses [HTTPMethod] array instead of Set — HTTPMethod does not conform to Hashable in Vapor
- [Phase 28-02]: OriginCheckMiddleware registered before FileMiddleware so CSRF check runs before any route handler
- [Phase 28-02]: chmod return value ignored — best-effort inside a throwing function context
- [Phase 28-fix-collective-memory-prompt-injection-vulnerability]: AgentTools.allowedEnvKeys defined as static let on AgentTools extension — shared between setEnvironment() write path and CollectiveMemoryService.sanitizeEntry() read path
- [Phase 28-fix-collective-memory-prompt-injection-vulnerability]: reasoning field preserved in CollectiveMemoryEntry struct but never injected into agent prompt lines — sanitizeEntry() strips all WorkingConfig injection vectors before formatMemoryContext() runs
- [Phase 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key]: CELLAR_MEMORY_REPO default lasermaze/cellar-memory in wrangler.toml [vars] — overridable without code changes
- [Phase 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key]: Worker rate limiting uses in-memory Map (resets on restart) — acceptable at this scale, avoids KV billing
- [Phase 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key]: makeJWT() strips both PKCS8 and PKCS1 PEM headers — resilient to key format from wrangler secret
- [Phase 29-02]: CellarPaths.memoryRepo reads CELLAR_MEMORY_REPO env var with defaultMemoryRepo fallback — consistent with existing CellarPaths pattern
- [Phase 29-02]: Stale cache served on 403/429 and network failure — rate-limit resilience more important than freshness for read path
- [Phase 29-02]: decodeAndFormat() helper shared between cache-hit and network-200 paths — avoids duplicating decode/rank/format pipeline
- [Phase 29-03]: CELLAR_MEMORY_PROXY_URL env var overrides production Worker URL — consistent with other CellarPaths env var patterns
- [Phase 29-03]: ProxyPayload wrapper struct encodes {"entry": ...} matching Worker's expected request body shape
- [v1.3 roadmap]: Tool implementations (SaveTools, DiagnosticTools, etc.) unchanged — ToolResult wrapping happens in AgentTools.execute(), not in tool files
- [v1.3 roadmap]: AgentLoopProvider protocol and all provider implementations (Anthropic/Deepseek/Kimi) unchanged — loop mechanics change, not provider contract
- [v1.3 roadmap]: OSAllocatedUnfairLock used in AgentControl — Swift 6 concurrency-safe, no new SPM dependency
- [v1.3 roadmap]: Post-loop save is the single save path — shouldAbort closure fire-and-forget pattern eliminated entirely
- [v1.3 roadmap]: Event log at ~/.cellar/logs/<gameId>-<timestamp>.jsonl — JSONL format for append-only streaming writes
- [Phase 31-new-types]: import os required explicitly for OSAllocatedUnfairLock — Foundation does not re-export it in current Swift toolchain
- [Phase 31-new-types]: AgentControl pattern: private State struct + OSAllocatedUnfairLock(initialState:) for lock-protected mutable state without @unchecked Sendable
- [Phase 31-P01]: ToolResult placed at file scope after AgentEvent — consistent with other top-level type definitions
- [Phase 31-P01]: LoopState is private file-scope struct before AgentLoop — accessible by AgentLoop but not public API
- [Phase 31-P01]: StopReason sub-enum uses .userConfirmedWorking (not .userConfirmed) to distinguish from AgentStopReason.userConfirmed
- [Phase 32-middleware-system]: MiddlewareContext is a final class (reference type) so all middleware share mutation across a single step
- [Phase 32-middleware-system]: ISO8601 colons replaced with dashes in log filename to avoid filesystem issues on macOS
- [Phase 32-middleware-system]: summarizeForResume() only collects toolInvoked/envChanged/gameLaunched — other entries are metrics, not resume-relevant
- [Phase 32-middleware-system]: EventLogger.afterTool prefixes 200-char result with STOP:/ERROR: to distinguish result types in the JSONL log
- [Phase 33-rewrite-the-loop]: LoopState changed from private to file-internal so PrepareStepHook typealias can reference it
- [Phase 33-rewrite-the-loop]: endTurn returns immediately — no tug-of-war, canStop, or consecutiveContinuations
- [Phase 33-rewrite-the-loop]: Middleware hooks (beforeTool/afterTool/afterStep) called in executeTools helper — budget/spin logic fully extracted
- [Phase 34-update-agenttools]: execute() returns .stop(reason: .userConfirmedWorking) on userForceConfirmed — actual save deferred to post-loop in AIService (Phase 35)
- [Phase 34-update-agenttools]: TaskState enum fully removed from AgentTools — loop control is now entirely via ToolResult return values and AgentControl
- [Phase 35]: if case pattern matching used for AgentStopReason equality — enum has associated values, no Equatable conformance
- [Phase 36-event-log-resume]: findMostRecent(gameId:) scans logsDir, filters by prefix/suffix, sorts descending by filename — ISO8601 timestamps sort correctly lexicographically without date parsing
- [Phase 36-event-log-resume]: Event log preferred over SessionHandoff for resume: richer context (tool history, env changes, launch outcomes). DiagnosticRecord guard checks both are nil to prevent double context injection
- [Phase 37-supporting-win32-apps]: bottleArch is informational only — WINEARCH not passed to WineProcess (macOS Wine WoW64 mode only)
- [Phase 37-supporting-win32-apps]: PEReader reads e_lfanew as 4-byte DWORD (fixing DiagnosticTools 2-byte bug); unknown machine types return nil (fixing DiagnosticTools treating all non-AMD64 as 32-bit)
- [Phase 37-02]: inspect_game keeps exe_type for backward compat and adds bottle_arch as canonical arch field
- [Phase 37-02]: arch query param omitted from redirect URL when auto/nil — clean URLs for default case
- [Phase 37-02]: bottleArch in GameEntry uses arch override first, falls back to PE auto-detection from installer
- [Phase 38-01]: Wiki stored as SPM bundled resource (.copy("wiki")) — ships with binary via brew upgrade, not in ~/.cellar/
- [Phase 38-01]: WikiService.fetchContext returns nil (not empty string) on wiki absence — graceful degradation per research pitfall #5
- [Phase 38-01]: WikiService.search returns plain String (never nil) for agent tool use — human-readable no-match response
- [Phase 38-01]: maxContentLength=4000 and maxPages=3 cap wiki context injection — avoids context bloat per pitfall #2
- [Phase 38-01]: games/ directory reserved for future per-game pages from ingest — not seeded manually
- [Phase 38-03]: DLLOverrideRecord.source is optional (String?) — nil check required before lowercased() comparison in WikiService.ingest
- [Phase 38-03]: WikiService.ingest call placed inside didSave block — wiki only grows from confirmed saves, not partial completions
- [Phase 38-02]: query_wiki dispatch is non-async — WikiService.search is synchronous file I/O, no await needed
- [Phase 38-02]: Wiki context injected after collective memory and before compatibility data — synthesized pattern knowledge is higher-level than raw compat reports
- [Phase 39-03]: isRateLimited() helper shared for /api/wiki/append — single 10/hr/IP bucket covers both contribute and wiki append
- [Phase 39-03]: WIKI_PAGE_PATTERN allows engines/|symptoms/|environments/|games/ subdirs plus log.md and index.md at root — path prefix wiki/ applied inside writeWikiPage
- [Phase 39-01]: fetchContext parameter renamed from 'for gameName: String' to 'engine: String?' to match planned P01 interface; AIService call updated accordingly
- [Phase 39-01]: Bundle.module left in ingest() body — P02 will replace entire ingest function body
- [Phase 39-01]: queryWiki made async in ResearchTools — execute() in AgentTools was already async, no control flow change needed

### Roadmap Evolution

- Phase 18 added (2026-03-30): Deepseek API Support — alternative AI provider alongside Claude
- Phase 19 added (2026-03-31): Import Lutris and ProtonDB compatibility databases
- Phase 20 added (2026-03-31): Smarter Wine log parsing and structured diagnostics
- Phase 21 added (2026-03-31): Pre-flight dependency check from PE imports
- Phase 23 added (2026-04-02): Homebrew tap distribution with launcher .app — zero-friction install via brew, CI-built binary, post-install .app wrapper
- Phase 22 added (2026-04-01): Seamless macOS UX — pre-flight permissions, game removal, actionable errors, first-run setup
- Phase 24 added (2026-04-02): Architecture & Code Quality Cleanup — async/await migration, AgentTools decomposition, KnownDLLRegistry expansion, error reporting, dependency audit
- Phase 25 added (2026-04-02): Kimi model support — add Kimi (Moonshot AI) as AI provider alongside Claude and Deepseek
- Phase 26 added (2026-04-02): ISO disc image support — mount .iso/.bin/.cue in cellar add, detect installer, run through existing pipeline
- Phase 27 added (2026-04-02): Distribution — GitHub Releases + Install Script — single-command install via curl|bash, release CI cleanup
- Phase 28 added (2026-04-02): Fix Collective Memory Prompt Injection — remove reasoning from prompt, allowlist env/registry, sanitize fields, CSRF protection, .env permissions
- Phase 29 added (2026-04-03): Secure collective memory — Cloudflare Worker write proxy, remove bundled private key, anonymous public reads, server-side validation
- Phases 31–36 added (2026-04-03): v1.3 Agent Loop Rewrite — typed results, thread-safe control, middleware system, JSONL event log, clean endTurn semantics
- Phase 37 added: Supporting Win32 apps — decide when to use win32 vs win64 bottle
- Phase 38 added: Rebuild memory layer — shared wiki for agents based on Karpathy principles
- Phase 39 added (2026-04-10): Move wiki to cellar-memory GitHub repo — bundled wiki is read-only on signed apps, no cross-user sharing. Reuse existing Cloudflare Worker write proxy for authenticated wiki writes, local cache at ~/.cellar/wiki/

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-04-10
Stopped at: Phase 38 P03 complete — WikiService.ingest added, AIService calls ingest after successful save, all 173 tests pass

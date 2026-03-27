---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
last_updated: "2026-03-27T20:34:44.316Z"
progress:
  total_phases: 5
  completed_phases: 5
  total_plans: 14
  completed_plans: 14
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Any user can go from "I have these old game files" to "the game launches and works" without manually configuring Wine.
**Current focus:** Phase 1 — Cossacks Launches

## Current Position

Phase: 03.1-expand-ai-repair-system (Phase 3.1)
Plan: 2 of 2 complete (03.1-02 complete — PHASE COMPLETE)
Status: Phase 03.1 Complete
Last activity: 2026-03-27 — Plan 03.1-02 complete: Progressive AI prompts (3 escalation levels), graduated LaunchCommand repair loop, WineActionExecutor as single fix dispatcher, Cossacks cnc-ddraw recipe variant, expanded winetricks allowlist.

Progress: [██████████] Phase 01 complete; Phase 01.1 complete; Phase 02 complete; Phase 03 complete; Phase 03.1 in progress (1/2)

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: 4.5 min
- Total execution time: 0.15 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-cossacks-launches | 2 | 9 min | 4.5 min |

**Recent Trend:**
- Last 5 plans: 7 min, 2 min
- Trend: faster

*Updated after each plan completion*
| Phase 03.1-expand-ai-repair-system P01 | 8min | 2 tasks | 8 files |
| Phase 01-cossacks-launches P03 | 2 | 2 tasks | 4 files |
| Phase 01-cossacks-launches P04 | 3min | 2 tasks | 6 files |
| Phase 01-cossacks-launches P05 | 7 | 2 tasks | 9 files |
| Phase 01-cossacks-launches P06 | 7 | 2 tasks | 5 files |
| Phase 01.1-reactive-dependencies P01 | 2min | 2 tasks | 4 files |
| Phase 01.1-reactive-dependencies P02 | 6 | 2 tasks | 2 files |
| Phase 02-ai-intelligence P01 | 3min | 2 tasks | 4 files |
| Phase 02-ai-intelligence P02 | 3min | 2 tasks | 2 files |
| Phase 03-repair-loop P01 | 8min | 2 tasks | 4 files |
| Phase 03-repair-loop P02 | 1 | 2 tasks | 1 files |
| Phase 03.1-expand-ai-repair-system P01 | 8min | 2 tasks | 8 files |
| Phase 03.1-expand-ai-repair-system P02 | 6min | 2 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Pre-planning: Wine via Gcenx tap (not bundled) — wine-stable deprecated Sep 2026
- Pre-planning: wined3d/OpenGL for DX8/DX9 — only viable path for old-game wedge
- Pre-planning: API-first AI — simpler than local inference for MVP
- Pre-planning: Cossacks: European Wars as flagship test game
- 2026-03-25: Roadmap restructured from horizontal layers to vertical functional slices — Phase 1 delivers the full pipeline for one game rather than foundation infrastructure only
- 2026-03-27 (01-01): macOS 14 minimum required for Swift Testing framework on Command Line Tools
- 2026-03-27 (01-01): DependencyChecker uses testable init(existingPaths:) pattern instead of protocol injection — simpler, avoids Sendable complexity in Swift 6
- 2026-03-27 (01-01): swift test requires -Xswiftc -F flag to find Testing.framework on Command Line Tools
- 2026-03-27 (01-02): installHomebrew() uses /bin/bash -c directly; brew binary doesn't exist yet at that stage
- 2026-03-27 (01-02): installWine() resolves brew path via DependencyChecker().detectHomebrew() for ARM/Intel correctness
- 2026-03-27 (01-02): StatusCommand re-checks DependencyChecker after each install attempt for accurate updated status
- [Phase 01-03]: logHandle captured as let constant — Swift 6 Sendable requires let binding for values captured in concurrently-executing closures like readabilityHandler
- [Phase 01-03]: RecipeEngine.findBundledRecipe uses Bundle.main first then CWD fallback — covers both release bundle and swift run development workflow
- [Phase 01-04]: GOG install path hardcoded as drive_c/GOG Games/Cossacks - European Wars/ — predictable GOG behavior, trivial fix if it differs in practice
- [Phase 01-04]: SIGINT handler kills wineserver (-k) rather than Process.terminate() — WineProcess.run() is synchronous and doesn't expose the underlying Process; wineserver -k is Wine-aware termination for all prefix processes
- [Phase 01-04]: slugify() produces stable game IDs from directory names: lowercase + spaces-to-hyphens + strip non-alphanumeric — e.g., Cossacks European Wars -> cossacks-european-wars
- [Phase 01-05]: StderrCapture uses NSLock wrapper class for Swift 6 Sendable compliance in WineProcess readabilityHandler
- [Phase 01-05]: allRequired now requires winetricks — DependencyStatus and guided install flow updated
- [Phase 01-05]: GuidedInstaller.installWine() uses plain brew install with xattr fallback — no --no-quarantine flag
- [Phase 01-06]: ValidationPrompt.run() returns Bool? (reachedMenu) instead of LaunchResult — LaunchCommand constructs full result with attemptCount and diagnosis
- [Phase 01-06]: Retry loop capped at min(envConfigs.count, 3) — if no retryVariants, only 1 attempt made (no pointless identical retries)
- [Phase 01-06]: Legacy backward compat: entries without executablePath fall back to hardcoded GOG path + recipe.executable
- [Phase 01.1-01]: WinetricksRunner always passes -q for unattended (no-dialog) winetricks mode
- [Phase 01.1-01]: Stale-output timeout is 5 minutes — no output for 5 min = process assumed hung, kill + wineserver cleanup
- [Phase 01.1-01]: OutputMonitor reuses NSLock + @unchecked Sendable pattern from WineProcess.StderrCapture for Swift 6 compliance
- [Phase 01.1-reactive-dependencies]: setup_deps semantic change: from must-pre-install to known-fixes-if-needed — eliminates 30+ min dotnet48 upfront install
- [Phase 01.1-reactive-dependencies]: LaunchCommand while-loop retry retries same envConfig after dep install (configIndex not advanced on dep install)
- [Phase 01.1-reactive-dependencies]: maxTotalAttempts=5 replaces old min(count,3) cap — covers both dep installs and variant cycling
- 2026-03-27 (02-01): detectProvider() checks ANTHROPIC_API_KEY first — prefer Claude if both keys set
- 2026-03-27 (02-01): URLSession.shared used exclusively (not custom session) to prevent semaphore deadlock on background delegate queue
- 2026-03-27 (02-01): ResultBox @unchecked Sendable class used for URLSession dataTask result capture — avoids Swift 6 captured-var mutation warning
- 2026-03-27 (02-01): Winetricks verb validation against known-safe allowlist prevents AI hallucinated verb names
- 2026-03-27 (02-01): AIResult<T> named to avoid shadowing Swift.Result
- 2026-03-27 (02-02): LaunchCommand AI diagnosis is silent on .unavailable — no API key is not an error during launch
- 2026-03-27 (02-02): AI fix application in LaunchCommand reuses depInstalled flag to prevent configIndex advance, keeping retry-loop semantics
- 2026-03-27 (02-02): var activeRecipe = recipe pattern in AddCommand lets recipe stay let-bound from store while AI augmentation is mutable
- 2026-03-27 (02-02): AI recipe generation only triggers when recipe == nil — bundled recipes always take precedence
- [Phase 03-repair-loop]: generateVariants prompt explicitly prohibits registry edits and winetricks — env vars and WINEDLLOVERRIDES only
- [Phase 03-repair-loop]: Attempt history error summaries capped at 500 chars per entry to prevent prompt token explosion
- [Phase 03-repair-loop]: maxTotalAttempts raised from 5 to 10 to accommodate AI variant budget
- [Phase 03-repair-loop]: AI variant injection uses same loop body as bundled variants — no code duplication
- [Phase 03-repair-loop]: Exhaustion condition broadened to include timedOut — hung launches that exhaust attempt budget trigger repair report
- [Phase 03.1-01]: cnc-ddraw only in KnownDLLRegistry v1 — dgVoodoo2 excluded (does not work on Wine)
- [Phase 03.1-01]: DLLDownloader download failures non-fatal: WineActionExecutor continues on failure, prints warning
- [Phase 03.1-01]: placeDLL auto-applies requiredOverrides from KnownDLLRegistry (cnc-ddraw needs WINEDLLOVERRIDES=ddraw=n,b)
- [Phase 03.1-02]: AIVariant (runtime, parsed [WineFix]) distinct from RetryVariant (Codable) — two structs for two contexts
- [Phase 03.1-02]: WineActionExecutor.execute() tuple updated to include actions field — consistent across all callers
- [Phase 03.1-02]: Escalation loop uses continue (not break+call) when level produces no variants — immediately tries next
- [Phase 03.1-02]: parseWineFix(from:) made internal for LaunchCommand recipe-action parsing at load time
- [Phase 03.1-02]: Winning config serializes WineFix actions back to [[String:String]] for RetryVariant.actions persistence

### Pending Todos

None.

### Roadmap Evolution

- Phase 03.1 inserted after Phase 03: Expand AI repair system to support DLL replacements and advanced fixes beyond env vars (URGENT)

### Blockers/Concerns

- Swift TUI ecosystem is weak — v1 is CLI-only (TUI deferred to v2), but raw ANSI may be needed for good UX
- Gcenx tap is a single-maintainer dependency — worth monitoring
- macOS OpenGL is deprecated — only DX8/DX9 path, could break in a future macOS version
- `swift test` requires framework search path flag for Swift Testing — future plans should document this or configure it in Package.swift

## Session Continuity

Last session: 2026-03-27
Stopped at: Completed 03.1-02 — progressive AI prompts (3 escalation levels), graduated LaunchCommand repair loop, WineActionExecutor as single fix dispatcher, Cossacks cnc-ddraw recipe variant. Phase 03.1 complete.

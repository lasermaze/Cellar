---
phase: 03-repair-loop
verified: 2026-03-27T19:30:00Z
status: passed
score: 12/12 must-haves verified
re_verification: false
---

# Phase 3: Repair Loop Verification Report

**Phase Goal:** When a launch fails, Cellar automatically retries with AI-suggested variant configurations before declaring failure. The system queries Claude for variant configurations, retries with AI-suggested settings, saves successful recipes, and writes repair reports on exhaustion.

**Verified:** 2026-03-27T19:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | WineProcess.run() kills process + wineserver after 5 min of no stdout/stderr output, returns timedOut=true | VERIFIED | WineProcess.swift:93-105 — polling loop with 300s staleTimeout, terminate() + killWineserver() on threshold, returns `timedOut: didTimeout` at line 136 |
| 2 | AIService.generateVariants() returns AIResult<AIVariantResult> containing up to 3 RetryVariant values and a reasoning string | VERIFIED | AIService.swift:258-273 — public entry point with correct signature; parseVariantsResponse uses .prefix(3) at line 364; returns AIVariantResult with variants + reasoning |
| 3 | AIService.generateVariants() returns .unavailable when no API key is configured | VERIFIED | AIService.swift:264-267 — detectProvider() check, early return .unavailable when provider is .unavailable |
| 4 | AI prompt constrains output to environment variables and DLL overrides only (no registry edits, no winetricks) | VERIFIED | AIService.swift:285 — "Output MUST use environment variables and WINEDLLOVERRIDES ONLY. Do NOT suggest registry edits. Do NOT suggest winetricks installs." |
| 5 | CellarPaths.repairReportFile(for:timestamp:) returns URL under ~/.cellar/logs/{gameId}/ | VERIFIED | CellarPaths.swift:37-42 — calls logDir(for: gameId) and appends "repair-report-{timestamp}.txt" |
| 6 | When bundled variants exhausted, AI injection block calls generateVariants() once and appends to envConfigs — same loop body handles them | VERIFIED | LaunchCommand.swift:89-122 — single while loop, AI injection at top of body, variants appended to envConfigs |
| 7 | AI variant generation happens at most once per launch (aiVariantsGenerated flag) | VERIFIED | LaunchCommand.swift:85,92 — flag set to false before loop, set to true on first entry into injection block |
| 8 | While loop condition allows entry for AI injection when bundled variants exhausted | VERIFIED | LaunchCommand.swift:89 — `(configIndex < envConfigs.count || !aiVariantsGenerated) && totalAttempts < maxTotalAttempts` |
| 9 | AI reasoning printed inline before AI variant attempts | VERIFIED | LaunchCommand.swift:107 — `print("\nAI analysis: \(aiResult.reasoning)")` inside the .success case |
| 10 | Winning AI variant config is auto-saved as user recipe via RecipeEngine.saveUserRecipe() | VERIFIED | LaunchCommand.swift:389-430 — two branches: with baseRecipe (merged env) and without (minimal recipe); both call saveUserRecipe() |
| 11 | On exhaustion, structured repair report written to CellarPaths.repairReportFile() with all attempts, configs, errors | VERIFIED | LaunchCommand.swift:317-365 — report written with attempt history, per-attempt environments, errors, best diagnosis, log directory |
| 12 | Hung launches (timedOut) treated as failed attempts, advancing to next variant | VERIFIED | LaunchCommand.swift:167-175 — timedOut check before success check, errors parsed, allAttempts appended, configIndex incremented |

**Score:** 12/12 truths verified

---

## Required Artifacts

| Artifact | Provides | Exists | Substantive | Wired | Status |
|----------|----------|--------|-------------|-------|--------|
| `Sources/cellar/Core/WineProcess.swift` | OutputMonitor + stale-output polling loop | Yes | Yes — 214 lines, polling loop lines 93-105, NSLock/@unchecked Sendable class at lines 8-13 | Yes — called in run(), timedOut result consumed by LaunchCommand | VERIFIED |
| `Sources/cellar/Core/AIService.swift` | generateVariants method | Yes | Yes — generateVariants() public entry at line 258, _generateVariants() private impl at line 275, parseVariantsResponse() at line 349 | Yes — called in LaunchCommand.swift line 100 | VERIFIED |
| `Sources/cellar/Models/AIModels.swift` | AIVariantResult struct | Yes | Yes — struct at lines 29-32, `variants: [RetryVariant]` and `reasoning: String` fields | Yes — returned by generateVariants(), consumed in LaunchCommand | VERIFIED |
| `Sources/cellar/Persistence/CellarPaths.swift` | repairReportFile helper | Yes | Yes — static func at lines 37-42, uses logDir(), appends filename with timestamp | Yes — called in LaunchCommand.swift line 319 | VERIFIED |
| `Sources/cellar/Commands/LaunchCommand.swift` | Extended retry loop with AI variant stage, recipe save, repair report | Yes | Yes — 445 lines, full integration of all Phase 3 capabilities | Yes — single entry point for launch pipeline | VERIFIED |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| WineProcess.run() | OutputMonitor | NSLock/@unchecked Sendable | WIRED | WineProcess.swift:8-13 declares class, line 67 creates instance, lines 74+83 call touch() |
| WineProcess.run() | timedOut: didTimeout | var didTimeout = false | WIRED | WineProcess.swift:94 declares var, line 103 sets true on timeout, line 136 passes to WineResult |
| LaunchCommand | AIService.generateVariants() | direct static call | WIRED | LaunchCommand.swift:100-116 — switch on AIService.generateVariants() with all three cases handled |
| LaunchCommand | WineResult.timedOut | result.timedOut check | WIRED | LaunchCommand.swift:167 — `if result.timedOut` guard before success check |
| LaunchCommand | RecipeEngine.saveUserRecipe() | direct call after reachedMenu | WIRED | LaunchCommand.swift:414 and 430 — two call sites |
| LaunchCommand | CellarPaths.repairReportFile() | called in exhaustion block | WIRED | LaunchCommand.swift:319 — `let reportURL = CellarPaths.repairReportFile(for: game, timestamp: reportTimestamp)` |
| AIVariantResult | RetryVariant | variants: [RetryVariant] field | WIRED | AIModels.swift:30 — field type is [RetryVariant]; RetryVariant defined in Recipe.swift |
| generateVariants attempt history | 500-char cap | String.prefix(500) | WIRED | AIService.swift:330 — `let cappedError = String(attempt.errorSummary.prefix(500))` |

---

## Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| RECIPE-04 | 03-01-PLAN.md, 03-02-PLAN.md | Cellar can try multiple recipe variants when a launch fails | SATISFIED | LaunchCommand implements single-loop AI variant injection; bundled variants + AI-generated variants tried in sequence; working variant saved as recipe; exhaustion writes repair report |

**Orphaned requirements check:** REQUIREMENTS.md traceability table lists only RECIPE-04 for Phase 3. Both plans claim RECIPE-04. No orphaned requirements.

---

## Anti-Patterns Found

No anti-patterns found in phase-modified files.

Files scanned:
- `Sources/cellar/Core/WineProcess.swift` — no TODOs, no stubs, no placeholder returns
- `Sources/cellar/Core/AIService.swift` — no TODOs, no stubs, generateVariants fully implemented
- `Sources/cellar/Models/AIModels.swift` — no TODOs, struct fully defined
- `Sources/cellar/Persistence/CellarPaths.swift` — no TODOs, helper fully implemented
- `Sources/cellar/Commands/LaunchCommand.swift` — no TODOs, all branches implemented

Three `return []` instances found in unrelated files (CellarStore.swift, BottleScanner.swift, WineErrorParser.swift) — these are legitimate empty-collection returns in utility functions, not stubs.

---

## Build Verification

`swift build` output: **Build complete!** (0.10s) — no errors, no warnings.

---

## Commit Verification

All four commits cited in summaries verified present in git history:

| Commit | Message | Plan |
|--------|---------|------|
| `b00822d` | feat(03-01): WineProcess stale-output hang detection, AIVariantResult model, CellarPaths repair helper | 03-01 Task 1 |
| `5f95b9e` | feat(03-01): AIService.generateVariants() method for AI-driven repair variants | 03-01 Task 2 |
| `88c4c37` | feat(03-02): extend retry loop with AI variant injection and hung-launch handling | 03-02 Task 1 |
| `66eeccc` | feat(03-02): recipe save on success and repair report on exhaustion | 03-02 Task 2 |
| `4de164b` | fix(03-02): single-loop AI injection, fix entry.name non-optional, explicit allAttempts callsites | 03-02 post-commit fix |

---

## Human Verification Required

The following behaviors require a running environment to verify but are structurally complete in the code:

### 1. End-to-End Repair Loop Execution

**Test:** Configure an `ANTHROPIC_API_KEY`, launch a game that fails all bundled variants, and observe the AI injection stage.
**Expected:** AI analysis reasoning printed, 1-3 additional variant attempts made, each labeled with description.
**Why human:** Requires a real Wine environment and game binary; AI API call returns dynamic content.

### 2. Winning Config Recipe Save

**Test:** With a working AI variant, answer "y" to the menu validation prompt.
**Expected:** "Saving winning configuration: KEY=VALUE" printed, recipe file created at `~/.cellar/recipes/{gameId}.json` with merged environment.
**Why human:** Requires game to actually launch successfully via an AI-generated variant.

### 3. Repair Report Completeness

**Test:** Exhaust all attempts (10 total) without success.
**Expected:** `~/.cellar/logs/{gameId}/repair-report-{timestamp}.txt` created with attempt history, environments, error details, and log directory path.
**Why human:** Requires exercising the exhaustion path; file content quality is a human judgment.

### 4. Retry Attempt Labels

**Test:** Observe terminal output during a multi-attempt launch.
**Expected:** "Attempt 2: ...", "Attempt 3: ..." labels printed; AI variants distinguished from bundled variants by description text.
**Why human:** ROADMAP Success Criterion 2 — "user sees each retry attempt labeled" requires visual observation.

---

## Gaps Summary

None. All 12 must-have truths verified. Phase goal achieved.

The phase delivers all components of the AI-driven repair loop:
- Infrastructure (Plan 01): stale-output hang detection, AIVariantResult model, repairReportFile path helper, generateVariants() with cumulative history and prompt constraints
- Integration (Plan 02): single-loop AI injection, hung-launch handling, winning config recipe save, exhaustion repair report

The three ROADMAP Success Criteria for Phase 3 are satisfied:
1. When a launch fails, AI generates alternative variants and retries automatically (LaunchCommand AI injection block)
2. User sees each retry labeled (LaunchCommand prints attempt number and config description per iteration)
3. After exhaustion, what was tried and best diagnosis are reported (exhaustion block + repair report file)

---

_Verified: 2026-03-27T19:30:00Z_
_Verifier: Claude (gsd-verifier)_

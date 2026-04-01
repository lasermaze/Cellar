---
phase: 20-smarter-wine-log-parsing-and-structured-diagnostics
verified: 2026-03-31T22:00:00Z
status: passed
score: 16/16 must-haves verified
re_verification: false
human_verification:
  - test: "Launch a game and inspect the tool result JSON"
    expected: "diagnostics key present with subsystem-grouped errors/successes, changes_since_last key with last_actions/new_errors/resolved_errors/persistent_errors"
    why_human: "Cannot exercise the full Wine launch path programmatically in verification"
  - test: "Run a second launch after applying set_environment or install_winetricks"
    expected: "changes_since_last.last_actions contains the tool name(param) string; resolved_errors shows any errors that disappeared"
    why_human: "Requires live agent loop execution across two launches"
---

# Phase 20: Smarter Wine Log Parsing and Structured Diagnostics — Verification Report

**Phase Goal:** Upgrade Wine log parsing from basic regex pattern matching (~5 patterns) to a structured, subsystem-grouped diagnostic system with broader error coverage (audio, input, font, memory), positive success signals, causal chain detection, noise filtering, and cross-launch trend tracking.
**Verified:** 2026-03-31T22:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | WineErrorParser.parse() returns WineDiagnostics with errors and successes grouped by subsystem | VERIFIED | `WineErrorParser.swift` line 100: `static func parse(_ stderr: String) -> WineDiagnostics` |
| 2 | Audio, input, font, and memory subsystem errors are detected | VERIFIED | `WineErrorParser.swift`: Audio (lines 204-254), Input (259-281), Font (286-309), Memory (314-349) — 8 distinct patterns across 4 new subsystems |
| 3 | Positive success signals (DirectDraw init, audio device opened) are extracted | VERIFIED | `WineErrorParser.swift` lines 353-376: 4 success signals for graphics (DirectDraw, Direct3D), audio (device opened), input (device acquired) |
| 4 | Causal chains link root cause (missing DLL) to downstream effects | VERIFIED | `WineErrorParser.swift` lines 379-406: post-pass using `dllToChannelMap` builds `CausalChain` structs |
| 5 | fixme: lines are filtered unless their subsystem has a matching detected error | VERIFIED | `WineErrorParser.swift` lines 118-124: `subsystemsWithErrors` set checked before including fixme line |
| 6 | Known-harmless macOS warn: lines are filtered | VERIFIED | `WineErrorParser.swift` lines 109-115: 6-phrase `harmlessWarnPhrases` allowlist applied per line |
| 7 | WineDiagnostics produces a summary header with error/success/filtered counts | VERIFIED | `WineDiagnostics.swift` lines 44-83: `summaryLine` computed property formats "N errors (subsystems), M successes, K fixme lines filtered" |
| 8 | WineDiagnostics.asDictionary() produces JSON shape for agent tool results | VERIFIED | `WineDiagnostics.swift` lines 152-210: emits `summary`, per-subsystem `errors`/`successes`, `causal_chains`, `filtered_fixme_count` |
| 9 | launch_game results contain 'diagnostics' key instead of 'detected_errors' | VERIFIED | `AgentTools.swift` line 1396: `"diagnostics": diagnostics.asDictionary()` — no `detected_errors` found anywhere in file |
| 10 | trace_launch results contain same 'diagnostics' key | VERIFIED | `AgentTools.swift` line 1698: `"diagnostics": diagnostics.asDictionary()` |
| 11 | read_log returns filtered/structured output with diagnostics and filtered_log | VERIFIED | `AgentTools.swift` lines 925-931: `"diagnostics": diagnostics.asDictionary()`, `"filtered_log": String(filtered.suffix(8000))` |
| 12 | launch_game and trace_launch include 'changes_since_last' | VERIFIED | `AgentTools.swift` lines 1397, 1699: `"changes_since_last": changesDiff` |
| 13 | Agent actions between launches are tracked in pendingActions | VERIFIED | `AgentTools.swift` lines 624-648: execute() appends to `pendingActions` for set_environment, set_registry, install_winetricks, place_dll, write_game_file |
| 14 | DiagnosticRecord is persisted to disk after each launch | VERIFIED | `AgentTools.swift` lines 1362-1363, 1692-1693: `DiagnosticRecord.from(...)` + `DiagnosticRecord.write(record)` in both launchGame and traceLaunch |
| 15 | Previous diagnostic data is injected into initial message when no SessionHandoff | VERIFIED | `AIService.swift` lines 880-885: `if previousSession == nil, let diagRecord = DiagnosticRecord.readLatest(gameId:) { contextParts.append(diagRecord.formatForAgent()) }` |
| 16 | Agent system prompt documents the new diagnostic output format | VERIFIED | `AIService.swift` lines 684-710: "## Structured Diagnostics" section covering diagnostics object, changes_since_last, read_log output; no `detected_errors` references remain |

**Score:** 16/16 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Core/WineDiagnostics.swift` | WineDiagnostics, SubsystemDiagnostic, WineSuccess, CausalChain types | VERIFIED | 251 lines; all types present with asDictionary(), summaryLine, addError(), addSuccess(), allErrors(), allSuccesses() |
| `Sources/cellar/Core/DiagnosticRecord.swift` | Codable persistence model | VERIFIED | 107 lines; Codable, write(), readLatest(), formatForAgent(), from(diagnostics:) all implemented |
| `Sources/cellar/Core/WineErrorParser.swift` | Expanded parser returning WineDiagnostics | VERIFIED | 513 lines; parse() returns WineDiagnostics, parseLegacy() for compat, filteredLog() for read_log; 4 new categories in WineErrorCategory enum |
| `Sources/cellar/Core/AgentTools.swift` | Integrated diagnostics + action tracking | VERIFIED | pendingActions/lastAppliedActions/previousDiagnostics state present; computeChangesDiff() helper at line 1449 |
| `Sources/cellar/Core/AIService.swift` | Previous-session injection + system prompt | VERIFIED | DiagnosticRecord.readLatest injection at lines 882-884; Structured Diagnostics section in system prompt |
| `Sources/cellar/Persistence/CellarPaths.swift` | diagnosticsDir/diagnosticFile helpers | VERIFIED | Lines 127-135: diagnosticsDir static let, diagnosticsDir(for:) and diagnosticFile(for:) functions |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `WineErrorParser.swift` | `WineDiagnostics.swift` | parse() returns WineDiagnostics | WIRED | `-> WineDiagnostics` at line 100 |
| `WineDiagnostics.swift` | `WineErrorParser.swift` | WineError and WineErrorCategory used in SubsystemDiagnostic | WIRED | SubsystemDiagnostic.errors: [WineError]; WineErrorCategory cases in addError() switch |
| `AgentTools.swift` | `WineErrorParser.swift` | WineErrorParser.parse() in launchGame/traceLaunch/readLog | WIRED | Lines 925, 1349, 1682: WineErrorParser.parse() calls confirmed |
| `AgentTools.swift` | `WineDiagnostics.swift` | asDictionary() in tool results | WIRED | Lines 928, 1396, 1698: diagnostics.asDictionary() confirmed |
| `AgentTools.swift` | `DiagnosticRecord.swift` | DiagnosticRecord.write() after launch, from() factory | WIRED | Lines 1362-1363, 1692-1693 confirmed |
| `AIService.swift` | `DiagnosticRecord.swift` | readLatest() + formatForAgent() for previous session injection | WIRED | Lines 882-884 confirmed |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| DIAG-01 | 20-01, 20-02 | Referenced in ROADMAP.md Phase 20 | TRACEABILITY DISCREPANCY | DIAG-01 in REQUIREMENTS.md refers to Phase 10 dialog detection (trace_launch +msgbox parsing) — a different feature already marked Complete. The ROADMAP.md reuses this ID for Phase 20 log parsing. |
| DIAG-02 | 20-01, 20-02 | Referenced in ROADMAP.md Phase 20 | TRACEABILITY DISCREPANCY | REQUIREMENTS.md defines DIAG-02 as CGWindowListCopyWindowInfo window detection (Phase 10). ID reuse in ROADMAP is incorrect. |
| DIAG-03 | 20-01, 20-02 | Referenced in ROADMAP.md Phase 20 | TRACEABILITY DISCREPANCY | REQUIREMENTS.md defines DIAG-03 as hybrid dialog detection (Phase 10). |
| DIAG-04 | 20-02 | Referenced in ROADMAP.md Phase 20 | ORPHANED | DIAG-04 does not exist anywhere in REQUIREMENTS.md — no definition and no traceability table entry. |

**Finding:** The goal was fully achieved. The requirement IDs assigned to Phase 20 in ROADMAP.md collide with Phase 10 dialog detection IDs already marked Complete, and DIAG-04 is undefined. The implementation is correct and complete — REQUIREMENTS.md was never updated to define new IDs for Phase 20's scope.

**Recommendation:** Add new requirement entries to REQUIREMENTS.md for Phase 20 scope (e.g., WLOG-01 through WLOG-04 covering subsystem grouping, success signals, causal chains, and cross-launch tracking) and add rows to the traceability table. Update ROADMAP.md Phase 20 Requirements field to reference the new IDs.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `AgentLoop.swift` | 130 | Pre-existing compile error: `maxOutputTokensLimit` not found on `any AgentLoopProvider` | Blocker (pre-existing) | Documented in both Plan 01 and Plan 02 summaries as pre-existing before Phase 20. Not introduced by this phase. |

No Phase 20 anti-patterns found. All new files use pre-compiled NSRegularExpression static lets, proper Swift structs, silent-failure persistence following the established SessionHandoff pattern, and no placeholder implementations.

---

### Human Verification Required

#### 1. Full Agent Diagnostic Loop

**Test:** Launch a game with the agent. After a fast crash, inspect the tool result shown in the agent loop output.
**Expected:** Tool result JSON contains `diagnostics` with `summary`, per-subsystem entries (whichever fired), and `changes_since_last` with `note: "First launch — no previous data for comparison"` on the first run.
**Why human:** Cannot exercise live Wine launch in automated verification.

#### 2. Cross-Launch Action Tracking

**Test:** Run the agent, have it call `install_winetricks` or `set_environment`, then call `launch_game` again.
**Expected:** `changes_since_last.last_actions` contains the tool name(param) string. If the action resolved an error, it appears in `resolved_errors`.
**Why human:** Requires two sequential live launches within one agent session.

#### 3. Previous-Session Diagnostic Injection

**Test:** After a completed agent session (game exits, agent stops), start a new session for the same game without a pending SessionHandoff.
**Expected:** The initial message to the agent contains the `--- PREVIOUS SESSION DIAGNOSTICS ---` block with error counts and last actions from the prior session.
**Why human:** Requires live SessionHandoff absence + existing DiagnosticRecord on disk.

---

### Gaps Summary

No implementation gaps. All 16 must-haves verified. The diagnostic system is fully implemented: WineDiagnostics type with 9 subsystems, DiagnosticRecord persistence, WineErrorParser expanded from 5 to 14+ patterns, all three agent tools (launch_game, trace_launch, read_log) returning structured diagnostics, cross-launch diff tracking, and previous-session injection in AIService.

The only issue found is a requirements traceability problem: ROADMAP.md Phase 20 incorrectly references DIAG-01/02/03 (already assigned to Phase 10 dialog detection) and DIAG-04 (undefined). This is a documentation gap only — the implementation fully delivers the stated phase goal.

---

_Verified: 2026-03-31T22:00:00Z_
_Verifier: Claude (gsd-verifier)_

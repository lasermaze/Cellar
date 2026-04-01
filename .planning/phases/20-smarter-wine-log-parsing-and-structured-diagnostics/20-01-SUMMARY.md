---
phase: 20-smarter-wine-log-parsing-and-structured-diagnostics
plan: 01
subsystem: diagnostics
tags: [wine, stderr, parsing, diagnostics, causal-chains, noise-filtering]

# Dependency graph
requires:
  - phase: 19-import-lutris-and-protondb-compatibility-databases
    provides: CompatibilityService and agent integration patterns
provides:
  - WineDiagnostics struct with subsystem-grouped errors, success signals, causal chains, filtering counts
  - DiagnosticRecord Codable persistence model for cross-launch tracking
  - WineErrorParser.parse() returning WineDiagnostics with 8+ subsystem coverage
  - WineErrorParser.parseLegacy() for backward compatibility
  - WineErrorParser.filteredLog() for read_log integration
affects:
  - 20-02 (plan 02 — read_log and agent tool integration uses WineDiagnostics/filteredLog)
  - 21-pre-flight-dependency-check-from-pe-imports (agent diagnostics enrichment)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Pre-compiled NSRegularExpression patterns as static lets in parsers
    - Subsystem-routing via mutating addError/addSuccess helpers
    - Post-pass causal chain detection using DLL-to-channel mapping
    - Codable persistence following SessionHandoff pattern

key-files:
  created:
    - Sources/cellar/Core/WineDiagnostics.swift
    - Sources/cellar/Core/DiagnosticRecord.swift
  modified:
    - Sources/cellar/Core/WineErrorParser.swift
    - Sources/cellar/Persistence/CellarPaths.swift
    - Sources/cellar/Commands/AddCommand.swift
    - Sources/cellar/Core/AgentTools.swift

key-decisions:
  - "parseLegacy() wraps parse() for backward compat — callers using [WineError] array migrate without logic changes"
  - "Causal chains detected in a post-pass after all lines parsed — avoids ordering sensitivity"
  - "filteredLog() uses subsystem membership derived from WineDiagnostics, not re-parsed from stderr"

patterns-established:
  - "Parse line-by-line for 50K+ line log performance, using continue to skip noise lines early"
  - "Subsystem routing via mutating addError/addSuccess on WineDiagnostics struct"
  - "Pre-compile NSRegularExpression as private static let with try! — patterns are compile-time constants"

requirements-completed: [DIAG-01, DIAG-02, DIAG-03]

# Metrics
duration: 15min
completed: 2026-03-31
---

# Phase 20 Plan 01: Structured Wine Diagnostics Data Model Summary

**WineDiagnostics type with 8-subsystem grouping (graphics/audio/input/font/memory/config/missingDLL/crash), causal chain detection, success signal extraction, fixme/harmless-warn noise filtering, and DiagnosticRecord Codable persistence**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-31T20:07:32Z
- **Completed:** 2026-03-31T20:22:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Created WineDiagnostics.swift with SubsystemDiagnostic, WineSuccess, CausalChain, and WineDiagnostics types including asDictionary() for JSON agent output
- Expanded WineErrorParser from 5 patterns to 14+ patterns across 8 subsystems with line-by-line parsing for large log performance
- Added success signal detection for graphics (DirectDraw, Direct3D), audio (device opened), and input (device acquired)
- Built causal chain detection linking missing DLLs (d3d9, ddraw, dsound, dinput) to downstream errors
- Added noise filtering: fixme lines selectively kept/filtered per subsystem, 6 macOS harmless warn phrases filtered
- Created DiagnosticRecord Codable persistence at ~/.cellar/diagnostics/<gameId>/latest.json
- Added CellarPaths.diagnosticsDir/diagnosticFile helpers

## Task Commits

Each task was committed atomically:

1. **Task 1: Create WineDiagnostics and DiagnosticRecord types** - `ec41eef` (feat)
2. **Task 2: Expand WineErrorParser with new subsystems, success signals, causal chains, and noise filtering** - `4f63956` (feat)

## Files Created/Modified
- `Sources/cellar/Core/WineDiagnostics.swift` - WineDiagnostics, SubsystemDiagnostic, WineSuccess, CausalChain types with asDictionary() JSON serialization
- `Sources/cellar/Core/DiagnosticRecord.swift` - Codable persistence model following SessionHandoff pattern, with from(diagnostics:) factory and formatForAgent()
- `Sources/cellar/Core/WineErrorParser.swift` - Rewritten parse() returning WineDiagnostics; 14+ patterns, 3 success signals, causal chains, noise filtering, parseLegacy(), filteredLog()
- `Sources/cellar/Persistence/CellarPaths.swift` - Added diagnosticsDir, diagnosticsDir(for:), diagnosticFile(for:)
- `Sources/cellar/Commands/AddCommand.swift` - Updated to parseLegacy() for backward compat
- `Sources/cellar/Core/AgentTools.swift` - Updated to parseLegacy() for backward compat

## Decisions Made
- parseLegacy() wraps parse() for backward compat — existing callers (AddCommand, AgentTools) get zero-diff migration using the flat [WineError] array
- Causal chains detected in a post-pass after all lines parsed — avoids ordering sensitivity (missing DLL line may appear after downstream error)
- filteredLog() derives subsystem membership from WineDiagnostics fields (not re-parsing stderr) — consistent with parse() output

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated callers from parse() to parseLegacy()**
- **Found during:** Task 2 (expanding WineErrorParser)
- **Issue:** parse() return type changed from [WineError] to WineDiagnostics; AddCommand.swift and AgentTools.swift called parse() and iterated over the result as [WineError]
- **Fix:** Changed both call sites to use parseLegacy() — the compatibility wrapper that returns [WineError] via allErrors()
- **Files modified:** Sources/cellar/Commands/AddCommand.swift, Sources/cellar/Core/AgentTools.swift
- **Verification:** Type-check passes with no errors
- **Committed in:** 4f63956 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** Necessary for the return type change. Plan anticipated this via parseLegacy() design.

## Issues Encountered
- Pre-existing root-owned plugin cache (.build/plugins/cache/) from a prior sudo run causes `swift build` to report an emit-module error unrelated to our code. All new Swift files type-check cleanly. This issue pre-dates this phase.

## Next Phase Readiness
- Plan 02 (read_log integration) can immediately use WineErrorParser.parse() and filteredLog()
- DiagnosticRecord.write() and readLatest() ready for agent loop integration
- WineDiagnostics.asDictionary() produces the JSON shape needed for agent tool results
- parseLegacy() ensures zero-regression for existing error-handling code paths

---
*Phase: 20-smarter-wine-log-parsing-and-structured-diagnostics*
*Completed: 2026-03-31*

---
phase: 01-cossacks-launches
plan: 03
subsystem: core
tags: [swift, wine, wineprefix, wineboot, regedit, json, codable, foundation-process]

# Dependency graph
requires:
  - phase: 01-01
    provides: Recipe model with CodingKeys, CellarPaths with bottleDir helper
affects: [01-04, 01-05]

provides:
  - WineProcess struct: reusable Wine subprocess with WINEPREFIX scoping, real-time streaming, and log file capture
  - BottleManager struct: isolated WINEPREFIX creation per game at ~/.cellar/bottles/{id}/ via wineboot --init
  - RecipeEngine struct: JSON recipe loading and transparent application (registry + env vars) with full line-by-line output
  - recipes/cossacks-european-wars.json: bundled Cossacks recipe with WINE_CPU_TOPOLOGY=1:0, ddraw=n,b, 1024x768 windowed registry entry

# Tech tracking
tech-stack:
  added: []
  patterns:
    - WineProcess wraps Foundation.Process — WINEPREFIX set on every Wine invocation without exception
    - readabilityHandler for real-time streaming + post-exit drain to handle EOF bug (RESEARCH Pitfall 4)
    - logHandle captured as let constant (not var) to satisfy Swift 6 Sendable closure capture requirements
    - wineboot --init with WINEDLLOVERRIDES=mscoree,mshtml= to suppress Gecko/Mono dialogs
    - RecipeEngine.findBundledRecipe: Bundle.main with CWD fallback for development via swift run
    - Temp UUID .reg files for registry application, deleted after use

key-files:
  created:
    - Sources/cellar/Core/WineProcess.swift
    - Sources/cellar/Core/BottleManager.swift
    - Sources/cellar/Core/RecipeEngine.swift
    - recipes/cossacks-european-wars.json
  modified: []

key-decisions:
  - "logHandle captured as let constant (not var) — Swift 6 Sendable rules prohibit capturing mutable vars in concurrently-executing closures; restructured to assign nil branch explicitly for let binding"
  - "RecipeEngine.findBundledRecipe uses Bundle.main first then CWD fallback — covers both release bundle and swift run development workflow without branching on build configuration"
  - "BottleManager.bottleExists checks isDirectory flag — ensures path exists AND is a directory, not a stale file"

patterns-established:
  - "WINEPREFIX scoping: every Wine invocation (run, initPrefix, killWineserver) sets WINEPREFIX from winePrefix.path — never relies on ambient environment"
  - "Post-exit drain: readDataToEndOfFile() called after waitUntilExit() on both stdout and stderr pipes to catch bytes missed by readabilityHandler EOF"
  - "Transparent recipe application: each registry entry and env var printed to stdout before being applied"
  - "Temp reg files: UUID-named .reg files in NSTemporaryDirectory, deleted after use"

requirements-completed: [BOTTLE-01, RECIPE-01, RECIPE-02]

# Metrics
duration: 2min
completed: 2026-03-27
---

# Phase 1 Plan 03: WineProcess, BottleManager, RecipeEngine, and Cossacks Recipe Summary

**Foundation.Process-based Wine subprocess helper with WINEPREFIX isolation, bottle creation via wineboot --init, and transparent recipe application via wine regedit — plus bundled Cossacks JSON recipe with WINE_CPU_TOPOLOGY=1:0 and ddraw override**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-27T01:04:40Z
- **Completed:** 2026-03-27T01:06:37Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- WineProcess: reusable Foundation.Process wrapper that sets WINEPREFIX on every invocation, streams stdout/stderr in real-time, optionally captures to log file, and drains remaining pipe data after exit
- BottleManager: creates isolated `~/.cellar/bottles/{gameId}/` directory then runs wineboot --init with Gecko/Mono suppression
- RecipeEngine: loads JSON recipes via JSONDecoder, finds bundled recipes from Bundle.main or CWD fallback, applies registry entries via wine regedit with line-by-line transparency printing
- Cossacks recipe JSON: contains WINE_CPU_TOPOLOGY=1:0 (single-CPU fix), ddraw=n,b DLL override, 1024x768 windowed registry entry

## Task Commits

Each task was committed atomically:

1. **Task 1: WineProcess helper and BottleManager** - `eb2d94a` (feat)
2. **Task 2: RecipeEngine and Cossacks recipe JSON** - `e3aa775` (feat)

## Files Created/Modified

- `Sources/cellar/Core/WineProcess.swift` - Reusable Wine subprocess with WINEPREFIX scoping, stdout/stderr streaming, log capture, wineboot init, regedit, wineserver kill
- `Sources/cellar/Core/BottleManager.swift` - Creates isolated bottles at ~/.cellar/bottles/{id}/ via wineboot --init; bottleExists directory check
- `Sources/cellar/Core/RecipeEngine.swift` - JSON recipe loader, bundled recipe finder (Bundle.main + CWD fallback), transparent recipe application with per-entry printing
- `recipes/cossacks-european-wars.json` - Cossacks: European Wars recipe (GOG 2.1.0.13) with environment, registry, and launch config

## Decisions Made

- `logHandle` in `WineProcess.run()` is declared as `let` with an explicit `nil` branch instead of `var`. Swift 6 Sendable rules prohibit capturing mutable vars in concurrently-executing closures (`readabilityHandler` runs on a background thread). The fix is to assign both the "has log file" and "no log file" branches to a single `let` binding before the closures.
- `RecipeEngine.findBundledRecipe` uses `Bundle.main.url(forResource:withExtension:subdirectory:)` first, falling back to `FileManager.currentDirectoryPath + "/recipes/{gameId}.json"`. This pattern covers release builds (bundle) and `swift run` during development (CWD) without any build-configuration branching.
- `BottleManager.bottleExists` uses `fileExists(atPath:isDirectory:)` with the `isDirectory` ObjCBool output parameter to ensure the path is a directory, not just any filesystem entry.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 Sendable closure capture error for mutable logHandle**
- **Found during:** Task 1 (WineProcess.run() implementation)
- **Issue:** `var logHandle: FileHandle?` captured in `readabilityHandler` closures triggered Swift 6 Sendable error: "reference to captured var in concurrently-executing code"
- **Fix:** Changed `var logHandle: FileHandle?` to `let logHandle: FileHandle?` with explicit `nil` branch for the no-log-file case
- **Files modified:** Sources/cellar/Core/WineProcess.swift
- **Verification:** `swift build` succeeds with no errors
- **Committed in:** `eb2d94a` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Swift 6 compiler correctness)
**Impact on plan:** Required fix for compilation under Swift 6 strict concurrency. No behavioral change — logHandle was effectively the same value, just declared as let instead of var.

## Issues Encountered

- Swift 6 strict concurrency is enforced by the compiler; any mutable capture in a handler closure that runs concurrently is an error. Pattern established: always declare values captured in readabilityHandler closures as `let`, even if they start as optional.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- WineProcess is ready for use by AddCommand (GOG installer via wine setup.exe) and LaunchCommand (game launch)
- BottleManager.createBottle() and bottleExists() provide the bottle lifecycle API AddCommand needs
- RecipeEngine.apply() returns the environment dict ready to be merged into the game launch process
- Cossacks recipe is bundled and loadable via RecipeEngine.findBundledRecipe(for: "cossacks-european-wars")
- All three Core components compile and build; no external dependencies added

---
*Phase: 01-cossacks-launches*
*Completed: 2026-03-27*

## Self-Check: PASSED

- Sources/cellar/Core/WineProcess.swift: FOUND
- Sources/cellar/Core/BottleManager.swift: FOUND
- Sources/cellar/Core/RecipeEngine.swift: FOUND
- recipes/cossacks-european-wars.json: FOUND
- .planning/phases/01-cossacks-launches/01-03-SUMMARY.md: FOUND
- Commit eb2d94a (Task 1): FOUND
- Commit e3aa775 (Task 2): FOUND

---
phase: 01-cossacks-launches
plan: 01
subsystem: infra
tags: [swift, swift-argument-parser, wine, homebrew, codable, cli]

# Dependency graph
requires: []
provides:
  - Swift 6 CLI package with ArgumentParser (status, add, launch subcommands)
  - Codable Recipe model with explicit CodingKeys for snake_case JSON schema
  - Codable GameEntry and LaunchResult models for game library persistence
  - CellarPaths struct with all ~/.cellar/ path constants and helper functions
  - DependencyChecker detecting Homebrew (ARM/Intel), Wine (wine64/wine), and GPTK
  - DependencyStatus with allRequired computed property
  - 16 Swift Testing tests verifying dependency detection logic
affects: [01-02, 01-03, 01-04, 01-05]

# Tech tracking
tech-stack:
  added:
    - swift-argument-parser 1.7.1 (Swift Argument Parser, Apple)
    - Swift Testing framework (Command Line Tools, requires -F flag for test runs)
  patterns:
    - DependencyChecker with testable init(existingPaths:) for mock filesystem injection
    - ParsableCommand stubs for commands not yet implemented
    - CodingKeys enums for mapping Swift camelCase to JSON snake_case
    - URL-based path constants via FileManager.homeDirectoryForCurrentUser

key-files:
  created:
    - Package.swift
    - Sources/cellar/Cellar.swift
    - Sources/cellar/Commands/StatusCommand.swift
    - Sources/cellar/Commands/AddCommand.swift
    - Sources/cellar/Commands/LaunchCommand.swift
    - Sources/cellar/Models/Recipe.swift
    - Sources/cellar/Models/GameEntry.swift
    - Sources/cellar/Models/LaunchResult.swift
    - Sources/cellar/Persistence/CellarPaths.swift
    - Sources/cellar/Core/DependencyChecker.swift
    - Tests/cellarTests/DependencyCheckerTests.swift
  modified: []

key-decisions:
  - "macOS 14 minimum (up from 13) required to use Swift Testing framework from Command Line Tools"
  - "DependencyChecker uses testable init(existingPaths:) for dependency injection instead of a separate protocol — simpler and avoids Sendable complexity"
  - "Test file cannot import Foundation alongside Swift Testing on Command Line Tools (causes _Testing_Foundation module error); tests use DependencyChecker return values (URL?) directly instead of constructing URL literals"
  - "Swift Testing requires -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks flag at test run time"

patterns-established:
  - "Testable init pattern: production init() uses real FileManager; test init(existingPaths:) injects mock path set"
  - "ARM-before-Intel path ordering in all Homebrew detection code"
  - "wine64-before-wine preference in Wine binary resolution"
  - "URL path constants via FileManager.homeDirectoryForCurrentUser (never hardcoded ~ strings)"

requirements-completed: [SETUP-01, SETUP-02, SETUP-05]

# Metrics
duration: 7min
completed: 2026-03-27
---

# Phase 1 Plan 01: Package Scaffold and Dependency Detection Summary

**Swift 6 CLI package with ArgumentParser entry point, Codable models, and testable DependencyChecker detecting Homebrew (ARM/Intel), Wine (wine64/wine), and GPTK**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-27T00:54:14Z
- **Completed:** 2026-03-27T01:02:05Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- Buildable Swift 6 package with ArgumentParser CLI (`cellar status`, `cellar add`, `cellar launch` subcommands)
- Full Codable model layer: Recipe (with snake_case CodingKeys), GameEntry, LaunchResult
- CellarPaths struct providing all `~/.cellar/` path constants (games.json, bottles/, logs/) with per-game helpers
- DependencyChecker with production and testable initializers; correctly detects Homebrew ARM-before-Intel and Wine wine64-before-wine
- 16 Swift Testing tests passing for all detection logic paths

## Task Commits

Each task was committed atomically:

1. **Task 1: Swift package scaffold with models and path constants** - `d1d4f1f` (feat)
2. **Task 2: RED - failing DependencyChecker tests** - `489c756` (test)
3. **Task 2: GREEN - DependencyChecker implementation** - `a19908a` (feat)

_Note: TDD task has two commits (test RED then feat GREEN)_

## Files Created/Modified

- `Package.swift` - Swift 6.0 tools version, ArgumentParser 1.7.x, macOS 14 floor, test target
- `Sources/cellar/Cellar.swift` - @main ParsableCommand with status/add/launch subcommands
- `Sources/cellar/Commands/StatusCommand.swift` - Stub ParsableCommand (to be implemented in 01-02)
- `Sources/cellar/Commands/AddCommand.swift` - Stub ParsableCommand with installerPath argument
- `Sources/cellar/Commands/LaunchCommand.swift` - Stub ParsableCommand with game argument
- `Sources/cellar/Models/Recipe.swift` - Codable Recipe + RegistryEntry with explicit CodingKeys
- `Sources/cellar/Models/GameEntry.swift` - Codable game library entry with LaunchResult reference
- `Sources/cellar/Models/LaunchResult.swift` - Codable timestamp + reachedMenu result struct
- `Sources/cellar/Persistence/CellarPaths.swift` - Static URL constants and logFile(for:timestamp:) helper
- `Sources/cellar/Core/DependencyChecker.swift` - DependencyChecker + DependencyStatus
- `Tests/cellarTests/DependencyCheckerTests.swift` - 16 Swift Testing tests

## Decisions Made

- macOS 14 minimum required to use the Swift Testing framework available in Command Line Tools. Plan specified macOS 13, raised to 14 — no functionality impact since the project is greenfield.
- DependencyChecker uses a testable `init(existingPaths:)` injecting a `Set<String>` instead of a protocol with a mock. Simpler, avoids Sendable protocol conformance complexity in Swift 6.
- Swift Testing's `import Testing` cannot coexist with `import Foundation` in the test target when using Command Line Tools (causes `_Testing_Foundation` module import error). Tests avoid constructing `URL` literals directly; instead they obtain URLs through `DependencyChecker.detectHomebrew()` return values, which comes from the `@testable import cellar` module that already imports Foundation.
- Running tests requires `-Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks` flag. This should be documented for the team.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Raised macOS platform floor from 13 to 14**
- **Found during:** Task 2 (DependencyChecker TDD)
- **Issue:** Swift Testing framework requires macOS 14+; test compilation failed with "no such module 'Testing'" on macOS 13 platform setting
- **Fix:** Updated Package.swift `.macOS(.v13)` to `.macOS(.v14)`
- **Files modified:** Package.swift
- **Verification:** `swift test` compiles and runs all 16 tests
- **Committed in:** `489c756` (TDD RED commit)

**2. [Rule 1 - Bug] Restructured tests to avoid Foundation import conflict with Swift Testing**
- **Found during:** Task 2 (DependencyChecker TDD GREEN)
- **Issue:** `import Testing` + `import Foundation` in same file triggers `no such module '_Testing_Foundation'` error on Command Line Tools
- **Fix:** Removed `import Foundation` from test file; redesigned DependencyStatus tests to use `checkAll()` return values obtained through `@testable import cellar` (which re-exports Foundation types)
- **Files modified:** Tests/cellarTests/DependencyCheckerTests.swift
- **Verification:** All 16 tests pass
- **Committed in:** `a19908a` (implementation commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 - environmental bugs)
**Impact on plan:** Both fixes were required for compilation. macOS 14 floor is a safe raise for a greenfield project. Test restructuring preserved all planned coverage. No scope creep.

## Issues Encountered

- Swift Testing on Command Line Tools (without full Xcode) has constraints: requires framework search path flag and cannot coexist with `import Foundation`. `swift test` invocations in this project require `-Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks` flags.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Package scaffold complete; all subsequent plans can add to Sources/cellar/
- Model types provide the data contract for recipe loading, game persistence, and launch recording
- DependencyChecker is the first callable production function; 01-02 (StatusCommand) can use it immediately
- CellarPaths provides consistent path resolution for all persistence operations

---
*Phase: 01-cossacks-launches*
*Completed: 2026-03-27*

---
phase: 01-cossacks-launches
plan: "05"
subsystem: core-infrastructure
tags: [wine, recipe-schema, error-parsing, dependency-detection, bottle-scanning]
dependency_graph:
  requires: ["01-04"]
  provides: [WineResult, WineErrorParser, BottleScanner, winetricks-detection, recipe-schema-v2]
  affects: ["01-06"]
tech_stack:
  added: []
  patterns: [StderrCapture-class-wrapper-for-Swift6-Sendable, NSRegularExpression-pattern-matching]
key_files:
  created:
    - Sources/cellar/Models/WineResult.swift
    - Sources/cellar/Core/WineErrorParser.swift
    - Sources/cellar/Core/BottleScanner.swift
  modified:
    - Sources/cellar/Models/Recipe.swift
    - Sources/cellar/Core/WineProcess.swift
    - Sources/cellar/Core/DependencyChecker.swift
    - Sources/cellar/Core/GuidedInstaller.swift
    - Sources/cellar/Commands/StatusCommand.swift
    - recipes/cossacks-european-wars.json
decisions:
  - "StderrCapture uses NSLock wrapper class (not nonisolated(unsafe)) for Swift 6 Sendable compliance — consistent with existing logHandle pattern"
  - "allRequired now requires winetricks — if winetricks is absent, status command guides install"
  - "GuidedInstaller removes --no-quarantine and uses xattr fallback after install if wine binary not detected"
metrics:
  duration: "7 min"
  completed: "2026-03-26"
  tasks: 2
  files_changed: 9
---

# Phase 1 Plan 05: Agentic Infrastructure Layer Summary

**One-liner:** Extended Recipe schema with setup_deps/install_dir/retry_variants, added WineResult with stderr capture, WineErrorParser with 4 error categories, BottleScanner for post-install exe discovery, and winetricks as a required dependency with xattr quarantine fallback.

## Tasks Completed

| # | Task | Commit | Key Files |
|---|------|--------|-----------|
| 1 | Extend Recipe schema, create WineResult, WineErrorParser | 8817fc7 | Recipe.swift, WineResult.swift, WineErrorParser.swift, WineProcess.swift, cossacks-european-wars.json |
| 2 | BottleScanner, winetricks dependency, quarantine fix | 657ccbf | BottleScanner.swift, DependencyChecker.swift, GuidedInstaller.swift, StatusCommand.swift |

## Verification

- `swift build` passes with no errors
- Recipe struct has `setupDeps: [String]?`, `installDir: String?`, `retryVariants: [RetryVariant]?` — all optional, backward-compatible
- Cossacks recipe JSON has `setup_deps`, `install_dir`, and 2 `retry_variants`
- WineProcess.run() returns WineResult while still streaming stdout/stderr to terminal in real-time
- WineErrorParser handles: missing DLL, crash, graphics, configuration errors
- BottleScanner.scanForExecutables() returns .exe files excluding system dirs (windows, programdata, users) and non-game exes
- DependencyStatus.allRequired now requires winetricks
- No --no-quarantine flag anywhere in the codebase

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- [x] WineResult.swift exists
- [x] WineErrorParser.swift exists
- [x] BottleScanner.swift exists
- [x] Recipe.swift has setupDeps/installDir/retryVariants
- [x] DependencyChecker.swift has winetricks detection and allRequired includes it
- [x] GuidedInstaller.swift has installWinetricks() and no --no-quarantine
- [x] StatusCommand.swift shows winetricks status and guides install
- [x] swift build passes

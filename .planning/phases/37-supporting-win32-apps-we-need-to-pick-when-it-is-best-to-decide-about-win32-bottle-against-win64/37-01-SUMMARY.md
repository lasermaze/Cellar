---
phase: 37-supporting-win32-apps
plan: "01"
subsystem: core
tags: [pe-detection, game-entry, cli, win32, architecture]
dependency_graph:
  requires: []
  provides: [PEReader, GameEntry.bottleArch, AddCommand.arch]
  affects: [GameEntry, AddCommand, DiagnosticTools]
tech_stack:
  added: []
  patterns: [TDD, struct-utility, swift-argument-parser-option]
key_files:
  created:
    - Sources/cellar/Core/PEReader.swift
    - Tests/cellarTests/PEReaderTests.swift
  modified:
    - Sources/cellar/Models/GameEntry.swift
    - Sources/cellar/Commands/AddCommand.swift
    - Tests/cellarTests/GameEntryTests.swift
decisions:
  - bottleArch is informational only — WINEARCH not passed to WineProcess (macOS Wine WoW64 mode only)
  - PEReader reads 1024 bytes (not 512) — safety margin for large DOS stubs
  - Unknown machine types return nil (fixes DiagnosticTools bug treating all non-0x8664 as 32-bit)
  - e_lfanew read as 4-byte DWORD at offset 0x3C (fixes DiagnosticTools 2-byte bug)
  - GameEntry.bottleArch is String? — optional so legacy JSON without field decodes as nil (no migration)
metrics:
  duration_min: 8
  completed_date: "2026-04-06"
  tasks_completed: 2
  files_changed: 5
---

# Phase 37 Plan 01: PE Header Detection and bottleArch Foundation Summary

**One-liner:** PEReader utility extracts installer arch (PE32/PE32+) at add time; GameEntry stores bottleArch; AddCommand accepts --arch override.

## What Was Built

### PEReader (`Sources/cellar/Core/PEReader.swift`)

Shared PE header detection utility extracted from (and fixing bugs in) `DiagnosticTools.swift`.

- `PEReader.Arch` enum: `.win32` (rawValue "win32") and `.win64` (rawValue "win64")
- `PEReader.detectArch(fileURL:)` reads first 1024 bytes from a file:
  - Checks MZ magic bytes (0x4D, 0x5A) at offset 0
  - Reads `e_lfanew` as 4-byte LE DWORD at offset 0x3C (bug fix: DiagnosticTools read only 2 bytes)
  - Validates PE signature `PE\0\0` at the e_lfanew offset
  - Reads machine type (2-byte LE WORD at PE offset + 4)
  - Returns `.win32` for 0x014C (i386), `.win64` for 0x8664 (AMD64), `nil` for all others (bug fix: DiagnosticTools treated all non-0x8664 as 32-bit)

### GameEntry update (`Sources/cellar/Models/GameEntry.swift`)

Added `var bottleArch: String?` after `executablePath`. The field is optional so:
- Existing JSON records without the field decode with `nil` (no migration needed)
- New records from `cellar add` get "win32" or "win64" (or nil if detection fails)

### AddCommand update (`Sources/cellar/Commands/AddCommand.swift`)

- `@Option(name: .long) var arch: String? = nil` — `--arch win32` or `--arch win64`
- Early validation: invalid arch value prints error and throws ExitCode.failure
- After disc image handling (effectiveInstallerURL resolved): runs `PEReader.detectArch`
- Prints "Detected installer architecture: win32/win64" when detection succeeds
- Prints "Architecture override: win32/win64" when --arch is set
- `bottleArch` = arch override ?? detected arch (nil if both absent)
- GameEntry constructor updated to include `bottleArch: bottleArch`

## Tests

### PEReaderTests (8 tests, all new)

| Test | Result |
|------|--------|
| Detects PE32 (i386 / 0x014C) as .win32 | Pass |
| Detects PE32+ (AMD64 / 0x8664) as .win64 | Pass |
| Returns nil for unknown machine type (ARM64 0xAA64) | Pass |
| Returns nil for plain text file | Pass |
| Returns nil for empty file | Pass |
| Returns nil for truncated MZ header | Pass |
| e_lfanew read as 4-byte DWORD (not 2 bytes) | Pass |
| Arch enum raw values are string literals | Pass |

### GameEntryTests (updated)

- `fullRoundTrip` now includes `bottleArch: "win32"` and asserts round-trip
- `nilOptionals` asserts `bottleArch == nil` for legacy JSON without the field

**Total test count:** 173 (up from 165 — 8 new PEReader tests)

## Deviations from Plan

### Auto-fixed Issues

None.

### Notes

- Both `GameController.swift` and `AddCommand.swift` call the GameEntry memberwise init without `bottleArch:` — Swift correctly defaults the optional to `nil` for callers that don't provide it, so no changes required for GameController.
- The plan mentioned fixing DiagnosticTools.swift bugs — these are fixed in PEReader (the authoritative implementation). DiagnosticTools.swift was not modified (it uses its own inline logic for diagnostics output only; PEReader is the shared utility for arch decisions).

## Commits

| Hash | Message |
|------|---------|
| 0b486fd | test(37-01): add failing PEReader tests (TDD red) |
| 4f140a5 | feat(37-01): add PEReader utility and bottleArch field to GameEntry |
| e5c256d | feat(37-01): integrate PE detection and --arch flag into AddCommand |

## Self-Check: PASSED

- Sources/cellar/Core/PEReader.swift — EXISTS
- Sources/cellar/Models/GameEntry.swift contains `var bottleArch: String?` — EXISTS
- Sources/cellar/Commands/AddCommand.swift contains `PEReader.detectArch` — EXISTS
- Tests/cellarTests/PEReaderTests.swift (111 lines, 8 tests) — EXISTS
- `swift test` passes 173/173 tests — PASSED
- `swift build` succeeds — PASSED

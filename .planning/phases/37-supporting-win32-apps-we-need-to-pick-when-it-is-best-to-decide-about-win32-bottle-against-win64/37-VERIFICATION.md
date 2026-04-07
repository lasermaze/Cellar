---
phase: 37-supporting-win32-apps
verified: 2026-04-06T02:00:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
---

# Phase 37: Supporting Win32 Apps — Verification Report

**Phase Goal:** PE arch detection utility, GameEntry arch storage, agent prompt awareness, CLI --arch flag, web UI arch override. All bottles remain WoW64 -- WINEARCH=win32 is not supported on macOS Wine.
**Verified:** 2026-04-06
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | PEReader.detectArch returns .win32 for 32-bit PE files and .win64 for 64-bit PE files | VERIFIED | PEReaderTests "Detects PE32 (i386 / 0x014C)" and "Detects PE32+ (AMD64 / 0x8664)" pass; PEReader.swift returns .win32 for 0x014C, .win64 for 0x8664 |
| 2 | PEReader.detectArch returns nil for non-PE files (scripts, corrupted headers, ARM binaries) | VERIFIED | Tests for empty file, plain text, truncated MZ header, unknown machine type (0xAA64) all pass |
| 3 | GameEntry with bottleArch round-trips through JSON (including nil for legacy records) | VERIFIED | GameEntryTests: fullRoundTrip includes bottleArch: "win32" and asserts decode; nilOptionals asserts bottleArch == nil for legacy JSON |
| 4 | cellar add detects installer PE arch and stores it in GameEntry | VERIFIED | AddCommand.swift calls PEReader.detectArch after effectiveInstallerURL is resolved; bottleArch passed to GameEntry constructor at line 337 |
| 5 | cellar add --arch win32 overrides PE detection | VERIFIED | AddCommand has @Option var arch: String? = nil; early validation; bottleArch: String? = arch ?? detectedArch |
| 6 | inspect_game tool output includes bottle_arch field showing win32/win64/unknown | VERIFIED | DiagnosticTools.swift adds "bottle_arch": detectedArch?.rawValue ?? "unknown" to jsonResult dictionary |
| 7 | Agent system prompt contains arch-aware DLL placement guidance | VERIFIED | AIService.swift system prompt at line 877-881 contains 5 bullets covering bottle_arch, win32 DLL placement in syswow64, WoW64 nature, prohibition on re-creating bottles |
| 8 | DiagnosticTools uses PEReader instead of inline PE parsing | VERIFIED | DiagnosticTools.swift line 15: PEReader.detectArch(fileURL: URL(fileURLWithPath: executablePath)) replaces former inline block |
| 9 | Web UI add-game form has architecture override dropdown and arch threads through redirect chain into GameEntry | VERIFIED | add-game.leaf has select#arch with auto/win32/win64 options; GameController threads arch param POST->redirect->GET install->SSE stream; runInstall() detects arch and passes to GameEntry constructor at line 365 |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Core/PEReader.swift` | Shared PE header detection utility exporting PEReader and PEReader.Arch | VERIFIED | Exists, 58 lines, exports struct PEReader with nested enum Arch: String { case win32, win64 } and static func detectArch(fileURL:) |
| `Sources/cellar/Models/GameEntry.swift` | GameEntry with bottleArch field | VERIFIED | Contains `var bottleArch: String?` at line 8 with comment "win32" or "win64"; nil = unknown |
| `Sources/cellar/Commands/AddCommand.swift` | AddCommand with --arch flag and PE detection | VERIFIED | Contains @Option var arch: String? = nil; PEReader.detectArch call; bottleArch: bottleArch in GameEntry constructor |
| `Tests/cellarTests/PEReaderTests.swift` | Unit tests for PE detection (min 30 lines) | VERIFIED | 111 lines, 8 tests covering PE32, PE32+, ARM64 nil, text nil, empty nil, truncated nil, 4-byte DWORD, raw values |
| `Sources/cellar/Core/Tools/DiagnosticTools.swift` | inspect_game with bottle_arch field using PEReader | VERIFIED | PEReader.detectArch call at line 15; "bottle_arch" key in jsonResult |
| `Sources/cellar/Core/AIService.swift` | System prompt with arch-aware guidance | VERIFIED | Lines 877-881 contain 5 arch-aware bullets including bottle_arch field description |
| `Sources/cellar/Web/Controllers/GameController.swift` | Web install flow with arch override support | VERIFIED | AddGameInput.arch field; archParam threading in POST, GET install, GET stream; bottleArch in GameEntry constructor |
| `Sources/cellar/Resources/Views/add-game.leaf` | Add game form with arch dropdown | VERIFIED | select#arch with auto/win32/win64 options and form-hint text |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| AddCommand.swift | PEReader.swift | PEReader.detectArch(fileURL:) | WIRED | Line 61: `let detectedArch = PEReader.detectArch(fileURL: effectiveInstallerURL)?.rawValue` |
| AddCommand.swift | GameEntry.swift | bottleArch: in GameEntry constructor | WIRED | Line 337: `bottleArch: bottleArch` in GameEntry(...) call |
| DiagnosticTools.swift | PEReader.swift | PEReader.detectArch replacing inline PE parsing | WIRED | Line 15: `PEReader.detectArch(fileURL: URL(fileURLWithPath: executablePath))` |
| GameController.swift | GameEntry.swift | bottleArch in GameEntry constructor and redirect params | WIRED | archParam in POST redirect (line 70-72); arch threaded through GET install (line 83-84) and stream (line 99); bottleArch: bottleArch in GameEntry at line 365 |

### Requirements Coverage

Requirements PE-01 through PE-06 are referenced in ROADMAP.md (line 479) but are NOT formally defined in REQUIREMENTS.md. REQUIREMENTS.md ends with v1.3 requirements (last updated 2026-04-03, covering phases up to 36), and was not updated to include Phase 37 PE requirements. The PE-01 through PE-06 IDs exist only in ROADMAP.md and the plan frontmatter.

Despite the absence of formal requirement definitions, the implementation fully satisfies the ROADMAP goal and plan must_haves:

| Requirement ID | Plan | Satisfied By | Status |
|----------------|------|--------------|--------|
| PE-01 | 37-01 | PEReader.swift: detectArch returns correct arch enum for PE32/PE32+ files | SATISFIED (inferred) |
| PE-02 | 37-01 | GameEntry.bottleArch: String? field with backward-compatible nil for legacy JSON | SATISFIED (inferred) |
| PE-03 | 37-01 | AddCommand --arch flag with PE detection and override logic | SATISFIED (inferred) |
| PE-04 | 37-02 | DiagnosticTools uses PEReader; inspect_game output includes bottle_arch field | SATISFIED (inferred) |
| PE-05 | 37-02 | AIService system prompt contains arch-aware DLL placement guidance (5 bullets) | SATISFIED (inferred) |
| PE-06 | 37-02 | Web UI arch dropdown + full threading through redirect chain into GameEntry | SATISFIED (inferred) |

**Note:** PE-01 through PE-06 are orphaned requirement IDs — they are referenced in ROADMAP.md and plan frontmatter but have no definitions in REQUIREMENTS.md. REQUIREMENTS.md should be updated to formally define these requirements and mark them complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| add-game.leaf | 10 | `placeholder=` | Info | HTML input placeholder attribute — not a stub, expected behavior |

No stub patterns, no TODO/FIXME comments, no empty implementations, no WINEARCH injection found in any modified file.

### Human Verification Required

None — all observable truths are verifiable from code. The key behaviors (PE detection, arch storage, system prompt content, redirect chain) are fully inspectable. No visual, real-time, or external service dependencies need human testing for this phase.

### Build and Test Results

- `swift build`: Build complete (0.27s) — no errors
- `swift test --filter "PEReaderTests|GameEntryTests"`: 12/12 tests passed
- All 5 commits verified: 0b486fd, 4f140a5, e5c256d, 975731e, 91c2b31

### WoW64 Constraint Compliance

Verified that WINEARCH is not set in any modified file. bottleArch is informational only and is not passed to WineProcess or createBottle. All bottles remain WoW64 as required.

### Gaps Summary

No gaps. All 9 observable truths are verified. All artifacts exist, are substantive, and are wired. All key links are confirmed. The only administrative note is that PE-01 through PE-06 requirement IDs are not formally defined in REQUIREMENTS.md — this is a documentation gap, not an implementation gap.

---

_Verified: 2026-04-06_
_Verifier: Claude (gsd-verifier)_

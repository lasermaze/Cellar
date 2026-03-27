# Phase 1: Cossacks Launches - Requirements

**Phase Goal:** Cossacks: European Wars launches end-to-end through a self-healing agentic pipeline on a fresh Mac, with no manual Wine configuration required. The system handles errors, diagnoses failures, and retries automatically.

## Existing Requirements (Plans 01-01 through 01-04 — IMPLEMENTED)

| ID | Description | Status |
|----|-------------|--------|
| SETUP-01 | Cellar detects whether Homebrew is installed (ARM and Intel paths) | Done |
| SETUP-02 | Cellar detects whether Wine is installed via Gcenx Homebrew tap | Done |
| SETUP-03 | Cellar guides user through installing Homebrew if missing | Done |
| SETUP-04 | Cellar guides user through installing Wine (Gcenx tap) if missing | Done (needs --no-quarantine removal) |
| SETUP-05 | Cellar detects whether GPTK is installed on the system | Done |
| BOTTLE-01 | Cellar creates an isolated WINEPREFIX per game automatically | Done |
| RECIPE-01 | Cellar ships with a bundled recipe for Cossacks: European Wars | Done (schema needs extension) |
| RECIPE-02 | Recipes auto-apply on launch (registry edits, DLL overrides, env vars) | Done |
| LAUNCH-01 | User can launch a game via Wine with correct WINEPREFIX and recipe flags | Done (needs retry loop) |
| LAUNCH-02 | Cellar captures Wine stdout/stderr to per-launch log files | Done (needs structured result) |
| LAUNCH-03 | After launch, Cellar asks user if the game reached the menu | Done |

## New Agentic Requirements (Plans 01-05, 01-06)

### Dependency Automation

| ID | Description | Acceptance Criteria |
|----|-------------|-------------------|
| AGENT-01 | Cellar detects and installs winetricks as a required dependency | `winetricks` binary detected alongside Wine; installed via `brew install winetricks` if missing; DependencyChecker and GuidedInstaller updated |
| AGENT-02 | Recipe specifies setup dependencies (winetricks verbs) to install before the game installer | Recipe schema includes `setup_deps: [String]` field; `cellar add` installs each dep into the bottle via `winetricks` before running the installer |
| AGENT-03 | Cellar removes Homebrew `--no-quarantine` flag usage and uses `xattr` fallback if Gatekeeper flags Wine | GuidedInstaller uses plain `brew install`; if Wine binary fails quarantine check, runs `xattr -rd com.apple.quarantine` on the cask path |

### Intelligent Installation

| ID | Description | Acceptance Criteria |
|----|-------------|-------------------|
| AGENT-04 | After installer finishes, Cellar scans the bottle for installed executables | BottleScanner recursively scans `drive_c/`, skips Wine system dirs and known non-game exes, returns discovered `.exe` paths |
| AGENT-05 | Cellar validates that game installation succeeded by checking for expected files | Post-install validation checks recipe's `install_dir` (if specified) or uses BottleScanner results; fails with actionable message if no game files found |
| AGENT-06 | GameEntry stores discovered executable path instead of empty/hardcoded path | `GameEntry.executablePath` populated from BottleScanner discovery or recipe `executable` field matched against scan results |

### Error Diagnosis

| ID | Description | Acceptance Criteria |
|----|-------------|-------------------|
| AGENT-07 | WineProcess.run() returns structured WineResult (exit code, captured stderr, elapsed time, log path) | Existing streaming behavior preserved; stderr additionally captured to string for error parsing; WineResult struct returned |
| AGENT-08 | WineErrorParser pattern-matches Wine stderr for known error categories | Parses: missing DLL (`err:module:import_dll`), crash (`virtual_setup_exception`), graphics errors, config errors; returns structured `WineError` with category + detail + suggested fix |

### Self-Healing Launch Loop

| ID | Description | Acceptance Criteria |
|----|-------------|-------------------|
| AGENT-09 | LaunchCommand retries with variant configurations when launch fails | On failure: parse errors → apply suggested fix → retry; max 3 attempts; each attempt labeled ("Trying variant 2/3...") |
| AGENT-10 | Recipe schema includes `retry_variants` — alternative env configurations to cycle through on failure | Recipe JSON includes `retry_variants: [{environment: {...}, description: "..."}]`; LaunchCommand cycles through variants before exhausting retries |
| AGENT-11 | After exhausting retries, Cellar reports what was tried and the best diagnosis | Final output lists each attempt, what was tried, and the parsed error diagnosis; user gets actionable information, not raw Wine output |

### Recipe Schema Extension

| ID | Description | Acceptance Criteria |
|----|-------------|-------------------|
| AGENT-12 | Recipe schema extended with `setup_deps`, `install_dir`, `retry_variants` fields | Backward-compatible — new fields are optional; existing recipe loads without error; Cossacks recipe updated with `setup_deps: ["dotnet48"]` and at least 2 retry variants |

## Requirement Dependencies

```
AGENT-01 → AGENT-02 (winetricks must exist before setup_deps can be installed)
AGENT-04 → AGENT-05, AGENT-06 (scanner feeds validation and GameEntry)
AGENT-07 → AGENT-08 → AGENT-09 (structured result → parsing → retry loop)
AGENT-10 → AGENT-09 (variants feed into retry loop)
AGENT-12 → AGENT-02, AGENT-10 (schema must exist before features consume it)
```

## Suggested Plan Grouping

**Plan 01-05: Agentic Infrastructure**
- AGENT-01 (wiretricks detection/install)
- AGENT-03 (--no-quarantine fix)
- AGENT-04 (BottleScanner)
- AGENT-07 (WineResult structured output)
- AGENT-08 (WineErrorParser)
- AGENT-12 (Recipe schema extension)

**Plan 01-06: Agentic Commands**
- AGENT-02 (wiretricks setup_deps in `cellar add`)
- AGENT-05 (post-install validation)
- AGENT-06 (executable discovery in GameEntry)
- AGENT-09 (retry loop in LaunchCommand)
- AGENT-10 (retry_variants cycling)
- AGENT-11 (exhaustion report)

---
*Created: 2026-03-26*
*Updated: 2026-03-26 — agentic requirements added based on human testing discoveries*

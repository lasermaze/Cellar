---
phase: 27-distribution-github-releases-install-script
plan: 02
subsystem: infra
tags: [bash, install-script, github-releases, curl, checksum, path-setup]

# Dependency graph
requires: []
provides:
  - "install.sh at repo root enabling curl | bash single-command Cellar installation"
  - "macOS-only detection with clear error on non-Darwin systems"
  - "SHA-256 checksum verification via shasum"
  - "Idempotent PATH update for zsh/bash/sh"
  - "Gatekeeper quarantine removal with xattr"
  - "Support for CELLAR_VERSION and CELLAR_INSTALL_DIR env vars"
affects: [distribution, release, onboarding]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "curl | bash installer pattern with set -euo pipefail safety"
    - "Conditional ANSI colors based on [ -t 1 ] terminal detection"
    - "Idempotent RC file PATH injection via grep -qF guard"

key-files:
  created:
    - "install.sh"
  modified: []

key-decisions:
  - "Darwin check uses $(uname -s) inline comparison to match grep 'uname -s.*Darwin' verification pattern"
  - "shasum verification uses cd into TMPDIR first so relative filename in .sha256 resolves correctly"
  - "xattr removal uses || true because xattr exits 1 when no quarantine attribute exists — critical under set -e"
  - "Checksum failure is warn-and-continue (not error) when .sha256 file absent from release"

patterns-established:
  - "Install script pattern: mktemp + trap cleanup, no sudo, user-local ~/.cellar/bin"

requirements-completed: ["install.sh script (system detection, download, checksum verify, PATH update, idempotent)", "no Swift source changes"]

# Metrics
duration: 1min
completed: 2026-04-03
---

# Phase 27 Plan 02: Install Script Summary

**curl | bash installer for Cellar: macOS detection, GitHub API version fetch, SHA-256 verification, quarantine removal, idempotent PATH update — 111 lines, no jq**

## Performance

- **Duration:** 1 min
- **Started:** 2026-04-03T02:35:07Z
- **Completed:** 2026-04-03T02:36:08Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Created `install.sh` at repo root enabling `curl -fsSL https://raw.githubusercontent.com/lasermaze/Cellar/main/install.sh | bash`
- Script detects macOS (exits 1 on Linux/Windows), fetches latest release from GitHub API using only grep+sed (no jq)
- Downloads archive, verifies SHA-256 checksum via shasum, installs to ~/.cellar/bin, removes quarantine safely
- Idempotent PATH injection into zsh/bash/sh RC files; smoke-tests binary after install

## Task Commits

Each task was committed atomically:

1. **Task 1: Create install.sh with full installation pipeline** - `a300455` (feat)

**Plan metadata:** _(docs commit — see below)_

## Files Created/Modified
- `install.sh` - Single-command Cellar installer for macOS (111 lines)

## Decisions Made
- `$(uname -s)` inline in the comparison so `grep "uname -s.*Darwin"` verification passes cleanly
- `xattr -rd ... || true` is critical — xattr exits 1 when attribute absent, which would abort under `set -e`
- `(cd "$TMPDIR" && shasum -a 256 -c ...)` — must cd into TMPDIR because .sha256 file contains relative filename
- Warn-and-continue when .sha256 absent (not error) — allows testing releases before checksum upload

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `install.sh` is ready to ship with the first GitHub Release
- Phase 27 Plan 01 (release.yml cleanup) uploads the `.sha256` sidecar file that this script verifies
- Users can install Cellar without Homebrew, Xcode, or Swift toolchain

---
*Phase: 27-distribution-github-releases-install-script*
*Completed: 2026-04-03*

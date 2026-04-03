---
phase: 27-distribution-github-releases-install-script
plan: "01"
subsystem: infra
tags: [github-actions, ci, release, checksum, sha256]

requires: []
provides:
  - Release workflow with SHA-256 checksum file alongside archive
  - Smoke test step (cellar --help) before upload
  - Both archive and .sha256 uploaded to GitHub Releases
  - Automatic release notes via generate_release_notes: true
  - Homebrew formula update step removed
affects: [27-02]

tech-stack:
  added: []
  patterns: ["shasum -a 256 generates .sha256 alongside archive for install script verification"]

key-files:
  created: []
  modified: [".github/workflows/release.yml"]

key-decisions:
  - "Homebrew formula update step removed — formula update is now a separate manual or tap-side concern"
  - "Smoke test runs cellar --help against the built binary before upload — catches broken builds early"
  - "Checksum generated as separate .sha256 file (not inline) so install.sh can download and verify independently"

patterns-established:
  - "Release artifacts: archive + .sha256 pair uploaded together so consumers can always verify"

requirements-completed: ["Release workflow cleanup (checksum + smoke test)"]

duration: 1min
completed: 2026-04-03
---

# Phase 27 Plan 01: Release Workflow Cleanup Summary

**Release CI workflow updated: Homebrew step removed, smoke test + SHA-256 checksum added, both archive and .sha256 uploaded with auto-generated release notes**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-04-03T02:35:03Z
- **Completed:** 2026-04-03T02:36:15Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Removed "Update Homebrew formula" step that was pushing commits to main (no longer needed)
- Added "Smoke test" step running `.build/apple/Products/Release/cellar --help` before any upload
- Added "Generate checksum" step producing `${ARCHIVE}.sha256` via `shasum -a 256`
- Updated upload step to include both `${{ env.ARCHIVE }}` and `${{ env.ARCHIVE }}.sha256`
- Enabled `generate_release_notes: true` on `softprops/action-gh-release@v2`

## Task Commits

1. **Task 1: Remove Homebrew step, add smoke test and checksum, enable release notes** - `96ae569` (feat)

**Plan metadata:** _(pending docs commit)_

## Files Created/Modified

- `.github/workflows/release.yml` - 5-step workflow: checkout, build, smoke test, checksum, upload (no Homebrew step)

## Decisions Made

- Homebrew formula update step removed — formula update is now a separate manual or tap-side concern
- Smoke test runs `cellar --help` against the built binary before upload — catches broken builds early
- Checksum generated as separate `.sha256` file (not inline) so `install.sh` can download and verify independently

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Release workflow is ready: publishes `cellar-X.Y.Z-macos.tar.gz` + `cellar-X.Y.Z-macos.tar.gz.sha256` to GitHub Releases
- Plan 27-02 (install.sh script) can now reference the `.sha256` URL pattern for verification
- No blockers

---
*Phase: 27-distribution-github-releases-install-script*
*Completed: 2026-04-03*

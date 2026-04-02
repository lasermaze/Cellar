---
phase: 23-homebrew-tap-distribution-with-launcher-app
plan: 01
subsystem: infra
tags: [homebrew, github-actions, ci-cd, swift, universal-binary, macos-app-bundle, distribution]

# Dependency graph
requires: []
provides:
  - GitHub Actions release workflow that builds universal binary on v* tag push
  - Homebrew tap formula template with post_install .app bundle creation
  - Formula stores Cellar.app in libexec with CellarLauncher shell script
affects: [homebrew-tap-repo, future-release-process, cellar-install-app-command]

# Tech tracking
tech-stack:
  added:
    - softprops/action-gh-release@v2 (GitHub Actions: upload release artifacts)
    - NSHipster/update-homebrew-formula-action@main (GitHub Actions: update tap formula sha256)
  patterns:
    - Universal binary via `swift build -c release --arch x86_64 --arch arm64` (single step, no lipo)
    - Formula stores .app in libexec, exposes via `cellar install-app` subcommand + caveats
    - Ad-hoc codesign in post_install for Apple Silicon Gatekeeper compatibility
    - opt_bin path interpolation (not hardcoded prefix) for cross-architecture .app launcher

key-files:
  created:
    - .github/workflows/release.yml
    - Formula/cellar.rb
  modified: []

key-decisions:
  - "Use cellar-community/homebrew-cellar as placeholder tap org — user updates before first release"
  - "bottle do uses cellar :any_skip_relocation — binary has no dynamic library dependencies"
  - "CellarLauncher polls 20x0.5s for port 8080 instead of fixed sleep — more reliable startup detection"
  - "Cellar.app placed in libexec, copied to ~/Applications via cellar install-app — avoids sudo requirement"

patterns-established:
  - "Formula .app pattern: create in libexec/Formula.app, copy to ~/Applications via subcommand, announce via caveats"
  - "Release workflow: build -> archive -> upload to Releases -> update tap formula sha256 atomically"

requirements-completed: [DIST-01, DIST-02]

# Metrics
duration: 1min
completed: 2026-04-02
---

# Phase 23 Plan 01: Homebrew Tap Distribution Summary

**GitHub Actions release workflow + Homebrew formula that builds a universal binary on tag push, uploads to GitHub Releases, and creates a minimal Cellar.app launcher in libexec via post_install**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-04-02T06:29:52Z
- **Completed:** 2026-04-02T06:30:56Z
- **Tasks:** 2 of 3 complete (Task 3 is a human-action checkpoint)
- **Files modified:** 2

## Accomplishments
- CI release workflow creates universal fat binary from a single `macos-latest` runner on any `v*` tag push
- Homebrew formula template covers install, post_install (codesign + .app creation), caveats, and test block
- CellarLauncher shell script uses polling (not fixed sleep) and `opt_bin` path for cross-architecture correctness

## Task Commits

Each task was committed atomically:

1. **Task 1: GitHub Actions release workflow** - `ece1a72` (feat)
2. **Task 2: Homebrew tap formula with post_install .app creation** - `2dda053` (feat)
3. **Task 3: Create tap repository on GitHub** - CHECKPOINT (human-action required)

**Plan metadata:** (pending — awaiting checkpoint completion)

## Files Created/Modified
- `.github/workflows/release.yml` - Release CI: universal build, GitHub Releases upload, tap formula update
- `Formula/cellar.rb` - Homebrew tap formula template with bottle block, post_install .app, caveats, test

## Decisions Made
- Used `cellar-community/homebrew-cellar` as placeholder tap org in both `release.yml` and `cellar.rb` — user must update the `tap:` field in `release.yml` and the `homepage`/`url` fields in `cellar.rb` before first release
- `bottle do cellar :any_skip_relocation` — the Cellar binary is statically linked (Swift + Vapor package) with no external dylib dependencies
- CellarLauncher polls port 8080 with 20x0.5s iterations instead of a fixed sleep — matches the anti-pattern guidance in RESEARCH.md
- Used `opt_bin` DSL interpolation (not `$(brew --prefix)/bin`) — Homebrew resolves this correctly on both Intel (`/usr/local`) and Apple Silicon (`/opt/homebrew`)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

Task 3 is a blocking human-action checkpoint. Before the release pipeline is functional, the user must:

1. Create the tap repository `cellar-community/homebrew-cellar` (or preferred org) on GitHub
2. Copy `Formula/cellar.rb` into the tap repo at `Formula/cellar.rb`
3. Create a GitHub PAT with `repo` scope for the tap repo
4. Add the PAT as `HOMEBREW_TAP_TOKEN` secret in the main Cellar repo (Settings -> Secrets -> Actions)
5. Update the `tap:` field in `.github/workflows/release.yml` to match the actual org/repo
6. Update `homepage`, `url`, `root_url` placeholders in `Formula/cellar.rb` to match the actual org
7. Verify: `brew tap <org>/cellar` succeeds after pushing the formula to the tap repo

## Next Phase Readiness

- CI and formula artifacts are complete and ready for use once the tap repo is created
- The `cellar install-app` subcommand (DIST-03) is referenced in the formula caveats but not yet implemented — that will be a separate plan or addition to the source code
- First release: push a `v*` tag → CI builds and uploads binary → update formula sha256 in tap repo (manual until `update-homebrew-formula-action` is verified to handle the bottle block)

---
*Phase: 23-homebrew-tap-distribution-with-launcher-app*
*Completed: 2026-04-02*

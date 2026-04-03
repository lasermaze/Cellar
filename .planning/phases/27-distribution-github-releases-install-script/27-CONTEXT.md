# Phase 27: Distribution — GitHub Releases + Install Script - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning
**Source:** PRD provided inline by user

<domain>
## Phase Boundary

Make Cellar installable with a single command. Two deliverables: (1) clean up the existing release CI workflow, (2) create an install.sh script. No Swift source code changes. No Formula/cellar.rb changes. No Package.swift changes.

</domain>

<decisions>
## Implementation Decisions

### Deliverable 1: Release workflow cleanup (.github/workflows/release.yml)
- Remove the Homebrew formula update step (sed + git push block at end)
- Add `generate_release_notes: true` to the `softprops/action-gh-release` step
- Add checksum: after building archive, compute `shasum -a 256`, upload as `cellar-{version}-macos.tar.gz.sha256`
- Add smoke test: run `.build/apple/Products/Release/cellar --help` after build, before upload
- Keep existing trigger (v* tag push) and build step as-is

### Deliverable 2: install.sh at repo root
- Detect system: must be macOS, clear error on Linux/Windows
- Detect architecture: arm64 or x86_64 (universal binary, just for messaging)
- Find latest release: GitHub API `repos/lasermaze/Cellar/releases/latest`, parse `.tag_name` with curl+grep/sed (no jq)
- Download archive: `curl -fSL` from GitHub Releases URL
- Verify checksum: download .sha256, verify with `shasum -a 256 -c`. Fail on mismatch, warn-and-continue if .sha256 missing
- Install binary: extract to `~/.cellar/bin/cellar`, create dir if needed
- Update PATH: detect shell (zsh/bash), append `export PATH="$HOME/.cellar/bin:$PATH"` to rc file if not present
- Remove quarantine: `xattr -rd com.apple.quarantine ~/.cellar/bin/cellar 2>/dev/null`
- Smoke test: run `~/.cellar/bin/cellar --help`, print troubleshooting on failure
- Print success message with getting-started commands

### Script requirements
- `#!/bin/bash` with `set -euo pipefail`
- No deps beyond curl, tar, shasum, grep, sed (all on macOS)
- Support `CELLAR_INSTALL_DIR` env var (default: `~/.cellar/bin`)
- Support `CELLAR_VERSION` env var for specific version
- Colorized output (ANSI codes) only if `[ -t 1 ]`
- Idempotent: re-run upgrades binary, doesn't duplicate PATH entries
- Under 150 lines

### Deliverable 3: No CI changes needed
- install.sh is checked into repo root, users fetch via raw GitHub URL
- `curl -fsSL https://raw.githubusercontent.com/lasermaze/Cellar/main/install.sh | bash`

### Constraints (locked)
- Do NOT modify any Swift source code
- Do NOT modify Formula/cellar.rb
- Do NOT modify Package.swift
- No jq, python, node, or non-macOS tools
- No sudo — user-writable location only

### Claude's Discretion
- Exact ANSI color codes and formatting
- Error message wording beyond the specified success message
- Temp directory strategy for download/extract

</decisions>

<specifics>
## Specific Ideas

- Success message format is specified exactly in the PRD (see Deliverable 2 step 10)
- The existing release.yml already builds universal binary correctly — just needs cleanup
- Binary is self-contained after build (SPM resource bundling)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.github/workflows/release.yml` — existing CI, needs cleanup not rewrite
- `Formula/cellar.rb` — keep untouched

### Integration Points
- release.yml uploads to GitHub Releases → install.sh downloads from GitHub Releases
- install.sh lives at repo root, fetched via raw.githubusercontent.com

</code_context>

<deferred>
## Deferred Ideas

None — PRD covers phase scope completely.

</deferred>

---

*Phase: 27-distribution-github-releases-install-script*
*Context gathered: 2026-04-02 via PRD*

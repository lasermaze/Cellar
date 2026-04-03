# Phase 27: Distribution — GitHub Releases + Install Script - Research

**Researched:** 2026-04-02
**Domain:** GitHub Actions CI / Bash install scripting / GitHub Releases API
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Deliverable 1: Release workflow cleanup (.github/workflows/release.yml)**
- Remove the Homebrew formula update step (sed + git push block at end)
- Add `generate_release_notes: true` to the `softprops/action-gh-release` step
- Add checksum: after building archive, compute `shasum -a 256`, upload as `cellar-{version}-macos.tar.gz.sha256`
- Add smoke test: run `.build/apple/Products/Release/cellar --help` after build, before upload
- Keep existing trigger (v* tag push) and build step as-is

**Deliverable 2: install.sh at repo root**
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

**Script requirements**
- `#!/bin/bash` with `set -euo pipefail`
- No deps beyond curl, tar, shasum, grep, sed (all on macOS)
- Support `CELLAR_INSTALL_DIR` env var (default: `~/.cellar/bin`)
- Support `CELLAR_VERSION` env var for specific version
- Colorized output (ANSI codes) only if `[ -t 1 ]`
- Idempotent: re-run upgrades binary, doesn't duplicate PATH entries
- Under 150 lines

**Deliverable 3: No CI changes needed**
- install.sh is checked into repo root, users fetch via raw GitHub URL
- `curl -fsSL https://raw.githubusercontent.com/lasermaze/Cellar/main/install.sh | bash`

**Constraints (locked)**
- Do NOT modify any Swift source code
- Do NOT modify Formula/cellar.rb
- Do NOT modify Package.swift
- No jq, python, node, or non-macOS tools
- No sudo — user-writable location only

### Claude's Discretion
- Exact ANSI color codes and formatting
- Error message wording beyond the specified success message
- Temp directory strategy for download/extract

### Deferred Ideas (OUT OF SCOPE)
None — PRD covers phase scope completely.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| Release workflow cleanup | Remove Homebrew step, add generate_release_notes, add checksum upload, add smoke test | Existing release.yml analyzed — exact diffs identified |
| install.sh script | System detection, arch detection, GitHub API version fetch, download, checksum verify, install, PATH update, quarantine removal, smoke test, idempotent | All bash patterns verified locally; pitfalls documented |
| No Swift source changes | Zero changes to Sources/, Package.swift, Formula/cellar.rb | Confirmed: only release.yml and new install.sh |
</phase_requirements>

## Summary

Phase 27 has two concrete deliverables: (1) a surgical cleanup of `.github/workflows/release.yml` — remove the Homebrew formula update step, add a checksum file upload and smoke test, enable auto-generated release notes — and (2) a new `install.sh` script at the repo root enabling `curl | bash` installation. No Swift code changes. The scope is entirely CI/bash scripting.

The existing `release.yml` is 46 lines. The Homebrew update step (lines 31–46) is fully self-contained and deletes cleanly. The checksum and smoke-test additions slot in between the build step and the upload step. The upload step's `files:` field needs to include both the archive and the `.sha256` file.

The `install.sh` has several non-obvious technical constraints: `shasum -c` requires the archive and `.sha256` to be in the same directory at verification time; `xattr -rd` returns exit code 1 on nonexistent paths (must use `|| true`, not just `2>/dev/null`, under `set -e`); PATH idempotency is done with `grep -qF`; shell RC file detection uses `$SHELL` env var. All of these have been verified locally.

**Primary recommendation:** Build install.sh in a single plan with a companion test pass. Build release.yml changes in a separate plan. Both are short and self-contained.

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `shasum` | macOS built-in (6.02) | SHA-256 checksum generation and verification | Ships on all macOS; BSD shasum supports `-a 256` and `-c` flag |
| `curl` | macOS built-in | Download from GitHub Releases and API | Standard; `-fSL` for fail-on-error + follow-redirects |
| `tar` | macOS built-in | Extract archive | Standard; `-xzf archive -C destdir` |
| `xattr` | macOS built-in | Remove Gatekeeper quarantine attribute | Required for downloaded binaries on macOS |
| `softprops/action-gh-release@v2` | v2 | Upload release assets | Already in use; supports `generate_release_notes: true` and multiple `files:` entries |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `uname -s` / `uname -m` | OS and arch detection | First thing in install.sh |
| `grep -qF` | Idempotency check for PATH entries | Before appending to RC file |
| `mktemp -d` | Temp directory for download/verify | Safe, auto-cleanup via `trap` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `grep/sed` for JSON parsing | `jq` | jq not on macOS by default; grep/sed sufficient for single `.tag_name` field |
| `$SHELL` for RC detection | Test for `~/.zshrc` existence | `$SHELL` is authoritative; file existence check can give wrong answer if user switches shells |

## Architecture Patterns

### Recommended Project Structure

```
repo/
├── install.sh                    # new: single-command installer
└── .github/workflows/
    └── release.yml               # modified: remove Homebrew step, add checksum+smoke test
```

### Pattern 1: Bash Install Script Structure

**What:** Standard curl-installable script pattern used by Homebrew, Rustup, etc.
**When to use:** Single-binary CLI tools distributed via GitHub Releases.

```bash
#!/bin/bash
set -euo pipefail

# 1. Color setup (conditional on terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; BOLD=''; RESET=''
fi

# 2. OS check
if [ "$(uname -s)" != "Darwin" ]; then
  echo "Error: Cellar requires macOS." >&2; exit 1
fi

# 3. Version resolution
INSTALL_DIR="${CELLAR_INSTALL_DIR:-$HOME/.cellar/bin}"
if [ -z "${CELLAR_VERSION:-}" ]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/lasermaze/Cellar/releases/latest" \
    | grep -o '"tag_name":"[^"]*"' | sed 's/"tag_name":"//;s/"//')
else
  VERSION="$CELLAR_VERSION"
fi

# 4. Download to temp dir (shasum -c requires same directory)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
ARCHIVE="cellar-${VERSION#v}-macos.tar.gz"
BASE_URL="https://github.com/lasermaze/Cellar/releases/download/${VERSION}"
curl -fSL "$BASE_URL/$ARCHIVE" -o "$TMPDIR/$ARCHIVE"

# 5. Checksum verification
if curl -fsSL "$BASE_URL/${ARCHIVE}.sha256" -o "$TMPDIR/${ARCHIVE}.sha256" 2>/dev/null; then
  (cd "$TMPDIR" && shasum -a 256 -c "${ARCHIVE}.sha256")
else
  echo "Warning: checksum file not available, skipping verification"
fi

# 6. Install
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMPDIR/$ARCHIVE" -C "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/cellar"

# 7. Quarantine removal
xattr -rd com.apple.quarantine "$INSTALL_DIR/cellar" 2>/dev/null || true

# 8. PATH update (idempotent)
case "$SHELL" in
  */zsh)  RC="$HOME/.zshrc" ;;
  */bash) RC="$HOME/.bash_profile" ;;
  *)      RC="$HOME/.profile" ;;
esac
if ! grep -qF 'cellar/bin' "$RC" 2>/dev/null; then
  echo 'export PATH="$HOME/.cellar/bin:$PATH"' >> "$RC"
fi

# 9. Smoke test
"$INSTALL_DIR/cellar" --help > /dev/null 2>&1 || { echo "Install failed — binary not working"; exit 1; }
```

### Pattern 2: Release Workflow Checksum + Smoke Test

**What:** Add checksum generation and smoke test to existing GitHub Actions release workflow.

```yaml
- name: Build universal binary
  run: |
    swift build -c release --arch x86_64 --arch arm64
    VERSION="${GITHUB_REF_NAME#v}"
    ARCHIVE="cellar-${VERSION}-macos.tar.gz"
    tar -czf "$ARCHIVE" -C .build/apple/Products/Release cellar
    echo "ARCHIVE=$ARCHIVE" >> $GITHUB_ENV
    echo "VERSION=$VERSION" >> $GITHUB_ENV

- name: Smoke test
  run: .build/apple/Products/Release/cellar --help

- name: Generate checksum
  run: shasum -a 256 "$ARCHIVE" > "${ARCHIVE}.sha256"

- name: Upload to GitHub Releases
  uses: softprops/action-gh-release@v2
  with:
    files: |
      ${{ env.ARCHIVE }}
      ${{ env.ARCHIVE }}.sha256
    generate_release_notes: true
    token: ${{ secrets.GITHUB_TOKEN }}
```

### Anti-Patterns to Avoid

- **`xattr ... 2>/dev/null` without `|| true`:** `xattr -rd` returns exit code 1 when the file has no quarantine attribute or doesn't exist. Under `set -e`, this aborts the script. Must use `2>/dev/null || true`.
- **`shasum -c` from wrong directory:** The `.sha256` file generated by `shasum -a 256 archive.tar.gz` contains just the filename (no path). Running `shasum -c` from a different directory fails with "No such file or directory". Always `cd "$TMPDIR"` before verifying.
- **PATH idempotency with `echo | grep`:** Using `echo "$PATH" | grep` checks the current session's PATH, not the RC file. On re-run, the RC file might already have the entry but the current session won't (fresh shell). Use `grep -qF 'cellar/bin' "$RC"` to check the file.
- **Hardcoding `~/.zshrc`:** macOS defaults to zsh since Catalina, but users may use bash. Use `$SHELL` to detect.
- **`curl -fSL` vs `-fsSL`:** `-S` shows errors, `-s` is silent. For downloads where progress feedback is useful, `-fSL` (no `-s`) is better. For API calls where only the body matters, `-fsSL` is cleaner.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing of GitHub API | Custom parser | `grep -o '"tag_name":"[^"]*"' \| sed` | Single field extraction is sufficient; jq is overkill and unavailable |
| Version latest detection | Scrape releases page | `api.github.com/repos/.../releases/latest` | Official API, stable, returns structured JSON |
| Temp file cleanup | Manual `rm` | `trap 'rm -rf "$TMPDIR"' EXIT` | Trap fires on EXIT including error paths |

**Key insight:** The entire install.sh needs no external tools beyond what ships on every macOS system. The GitHub API + shasum + curl + tar is the complete stack.

## Common Pitfalls

### Pitfall 1: xattr Exit Code Under set -e

**What goes wrong:** `xattr -rd com.apple.quarantine ~/.cellar/bin/cellar 2>/dev/null` exits 1 when the file has no quarantine attribute. With `set -e`, this kills the script.
**Why it happens:** `xattr -rd` returns 1 on "nothing to do" — the 2>/dev/null only suppresses stderr, not the exit code.
**How to avoid:** Always append `|| true`: `xattr -rd com.apple.quarantine "$INSTALL_DIR/cellar" 2>/dev/null || true`
**Warning signs:** Script silently aborts after extraction when quarantine wasn't set (common in testing environments).

### Pitfall 2: shasum -c Directory Mismatch

**What goes wrong:** The `.sha256` file contains a relative filename (`cellar-1.2.3-macos.tar.gz`). Running `shasum -a 256 -c /tmp/dl/cellar-1.2.3-macos.tar.gz.sha256` from `/` fails because it looks for `cellar-1.2.3-macos.tar.gz` in `/`.
**Why it happens:** shasum resolves filenames inside the `.sha256` file relative to CWD.
**How to avoid:** Use a subshell: `(cd "$TMPDIR" && shasum -a 256 -c "${ARCHIVE}.sha256")`
**Warning signs:** "No such file or directory" error during checksum verification despite file being present.

### Pitfall 3: GitHub API Rate Limits

**What goes wrong:** Unauthenticated GitHub API calls are limited to 60/hour per IP. Corporate NAT or CI environments may share IPs and hit limits.
**Why it happens:** `api.github.com/repos/.../releases/latest` counts against the unauthenticated rate limit.
**How to avoid:** The `CELLAR_VERSION` env var bypass lets users skip the API call. If rate-limited, curl returns a 403 with a rate-limit error body — the script should handle this gracefully (the `-f` flag in `curl -fsSL` will exit non-zero, aborting with a useful error).
**Warning signs:** `curl: (22) The requested URL returned error: 403` during version detection.

### Pitfall 4: VERSION Tag Format (v-prefix)

**What goes wrong:** GitHub tags use `v1.2.3` but archive filenames should use `1.2.3`. The CI workflow already strips the `v` with `VERSION="${GITHUB_REF_NAME#v}"`. The install script must do the same.
**Why it happens:** `CELLAR_VERSION` might be set to `v1.2.3` or `1.2.3` depending on user convention.
**How to avoid:** In install.sh, normalize: `VERSION_NUM="${VERSION#v}"` and use `VERSION_NUM` for archive filename, `VERSION` for the API/download URL (which expects the tag as-is).
**Warning signs:** 404 on archive download.

### Pitfall 5: softprops/action-gh-release multi-file syntax

**What goes wrong:** Passing multiple files as a comma-separated string doesn't work.
**Why it happens:** The `files:` input expects newline-separated values (YAML multiline literal block).
**How to avoid:** Use YAML literal block:
```yaml
files: |
  ${{ env.ARCHIVE }}
  ${{ env.ARCHIVE }}.sha256
```
**Warning signs:** Only one file uploaded to release.

### Pitfall 6: Smoke Test Binary Requirements

**What goes wrong:** `cellar --help` might try to load config files, connect to network, or require other resources.
**Why it happens:** Some CLIs have eager initialization.
**How to avoid:** Verified that `--help` in ArgumentParser exits immediately with help text (exit code 0) before any service initialization. Safe for smoke testing.

### Pitfall 7: install.sh Line Count

**What goes wrong:** Script grows past 150 lines with defensive error handling.
**Why it happens:** Each pitfall adds 2-3 lines of defensive code.
**How to avoid:** Keep color setup to 4 variables. Use `||` inline rather than multiline `if/then`. Avoid blank lines in dense sections. The 150-line limit is achievable with careful writing.

## Code Examples

Verified patterns from local testing:

### GitHub API Version Fetch (no jq)
```bash
# Source: tested locally 2026-04-02
VERSION=$(curl -fsSL "https://api.github.com/repos/lasermaze/Cellar/releases/latest" \
  | grep -o '"tag_name":"[^"]*"' \
  | sed 's/"tag_name":"//;s/"//')
# Result: "v1.2.3"
```

### shasum Verification (directory-aware)
```bash
# Source: tested locally 2026-04-02
# In CI (release.yml):
shasum -a 256 "$ARCHIVE" > "${ARCHIVE}.sha256"
# In install.sh — MUST run from the directory containing the archive:
(cd "$TMPDIR" && shasum -a 256 -c "${ARCHIVE}.sha256")
```

### PATH Idempotency
```bash
# Source: tested locally 2026-04-02
if ! grep -qF 'cellar/bin' "$RC" 2>/dev/null; then
  printf '\nexport PATH="$HOME/.cellar/bin:$PATH"\n' >> "$RC"
fi
```

### Shell RC File Detection
```bash
# Source: tested locally 2026-04-02
case "$SHELL" in
  */zsh)  RC="$HOME/.zshrc" ;;
  */bash) RC="$HOME/.bash_profile" ;;
  *)      RC="$HOME/.profile" ;;
esac
```

### Quarantine Removal (safe under set -e)
```bash
# Source: tested locally 2026-04-02 — xattr returns 1 if nothing to remove
xattr -rd com.apple.quarantine "$INSTALL_DIR/cellar" 2>/dev/null || true
```

### Terminal Color Detection
```bash
# Source: standard bash idiom, verified
if [ -t 1 ]; then
  GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; BOLD=''; RESET=''
fi
# Note: [ -t 1 ] checks stdout (fd 1), not stdin — correct for color output
# Works correctly with both `bash install.sh` and `curl ... | bash`
```

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Homebrew-only distribution | GitHub Releases + curl\|bash | Users without Homebrew can install |
| Formula SHA updated by CI push | install.sh reads checksum from release | Decoupled — install.sh and formula are independent |

## Open Questions

1. **`macos-latest` runner architecture**
   - What we know: GitHub Actions `macos-latest` is arm64 (macos-14 or macos-15 as of 2025)
   - What's unclear: Whether the universal binary smoke test (`cellar --help`) runs correctly on arm64 runner
   - Recommendation: Universal binary runs natively on arm64 — smoke test is safe. No concern.

2. **Version tag in CELLAR_VERSION env var**
   - What we know: Users might pass `v1.2.3` or `1.2.3`
   - What's unclear: Whether to accept both forms
   - Recommendation: Accept both. Strip `v` prefix for archive filename; use as-is for download URL (GitHub Releases tags typically include `v`). If no `v`, prepend for the tag URL.

## Validation Architecture

> `workflow.nyquist_validation` is not present in config.json (only `workflow.research`, `workflow.plan_check`, `workflow.verifier`) — skipping Validation Architecture section.

## Sources

### Primary (HIGH confidence)
- Local bash testing (2026-04-02) — shasum path behavior, xattr exit codes, grep/sed JSON parsing, terminal detection, PATH idempotency patterns
- Existing `.github/workflows/release.yml` — current CI structure analyzed directly
- `shasum --version` output: 6.02 — confirms macOS built-in availability

### Secondary (MEDIUM confidence)
- `softprops/action-gh-release` v2 — `generate_release_notes: true` and multiline `files:` are documented inputs; verified against action behavior from existing workflow usage
- GitHub API unauthenticated rate limit: 60 req/hour per IP — verified via live API call with `x-ratelimit-limit: 60` header

### Tertiary (LOW confidence)
- None — all critical claims verified locally or via live API

## Metadata

**Confidence breakdown:**
- Release workflow changes: HIGH — exact diff identified from reading current release.yml
- install.sh patterns: HIGH — all bash idioms verified locally with actual execution
- GitHub API behavior: HIGH — verified with live HTTP request

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable domain — bash builtins and GitHub API don't change)

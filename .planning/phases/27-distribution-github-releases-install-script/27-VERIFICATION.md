---
phase: 27-distribution-github-releases-install-script
verified: 2026-04-02T03:15:00Z
status: passed
score: 12/12 must-haves verified
re_verification: false
---

# Phase 27: Distribution — GitHub Releases + Install Script Verification Report

**Phase Goal:** Make Cellar installable with a single command — clean up release CI workflow (checksum, smoke test, remove Homebrew step), create install.sh script (detect system, download, verify, install to ~/.cellar/bin, update PATH).
**Verified:** 2026-04-02T03:15:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | Release workflow generates a .sha256 checksum file alongside the archive | VERIFIED | `shasum -a 256 "$ARCHIVE" > "${ARCHIVE}.sha256"` at release.yml:29 |
| 2  | Release workflow runs a smoke test (cellar --help) before uploading | VERIFIED | "Smoke test" step at release.yml:25-26 runs `.build/apple/Products/Release/cellar --help` |
| 3  | Release workflow uploads both archive and checksum to GitHub Releases | VERIFIED | `files:` block at release.yml:34-36 uploads `${{ env.ARCHIVE }}` and `${{ env.ARCHIVE }}.sha256` |
| 4  | Release workflow generates release notes automatically | VERIFIED | `generate_release_notes: true` at release.yml:37 |
| 5  | Homebrew formula update step is removed from the workflow | VERIFIED | `grep "Homebrew" release.yml` returns nothing |
| 6  | Running curl | bash on macOS downloads and installs the cellar binary | VERIFIED | install.sh: fetches from GitHub API, downloads archive, extracts to INSTALL_DIR, smoke tests binary |
| 7  | Script detects non-macOS systems and exits with a clear error | VERIFIED | install.sh:24-27 — `[ "$(uname -s)" != "Darwin" ]` exits 1 with "Cellar requires macOS" |
| 8  | Script verifies download integrity via SHA-256 checksum | VERIFIED | install.sh:63-68 — downloads .sha256 sidecar, verifies with `shasum -a 256 -c`; warns and continues if absent |
| 9  | Script adds ~/.cellar/bin to PATH in the appropriate shell RC file | VERIFIED | install.sh:80-89 — detects zsh/bash/sh, appends `export PATH=...` if 'cellar/bin' not already present |
| 10 | Re-running the script upgrades the binary without duplicating PATH entries | VERIFIED | install.sh:86 — `grep -qF 'cellar/bin' "$RC"` guards the append; tar overwrite replaces binary |
| 11 | Script removes Gatekeeper quarantine attribute from downloaded binary | VERIFIED | install.sh:77 — `xattr -rd com.apple.quarantine "$INSTALL_DIR/cellar" 2>/dev/null \|\| true` |
| 12 | Script runs cellar --help as a smoke test after installation | VERIFIED | install.sh:92-96 — `"$INSTALL_DIR/cellar" --help > /dev/null 2>&1` with error exit on failure |

**Score:** 12/12 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.github/workflows/release.yml` | CI release pipeline with checksum and smoke test | VERIFIED | 39-line file; 5 steps (checkout, build, smoke test, checksum, upload); no Homebrew step |
| `install.sh` | Single-command Cellar installer for macOS | VERIFIED | 111 lines (under 150 limit); executable (`chmod +x`); bash syntax valid (`bash -n` passes) |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `.github/workflows/release.yml` | GitHub Releases | `softprops/action-gh-release` with `generate_release_notes: true` | VERIFIED | Pattern present at release.yml:37 |
| `install.sh` | GitHub Releases API | `curl` to `api.github.com/repos/lasermaze/Cellar/releases/latest` | VERIFIED | install.sh:39 — curl + grep + sed; no jq |
| `install.sh` | `~/.cellar/bin/cellar` | `tar -xzf "$TMPDIR/$ARCHIVE" -C "$INSTALL_DIR"` | VERIFIED | install.sh:73 — tar extracts cellar binary; install.sh:74 sets chmod +x |

---

### Requirements Coverage

The plan frontmatter declares string-form requirement IDs (not REQUIREMENTS.md IDs). REQUIREMENTS.md maps distribution requirements to Phase 23. Phase 27 is an addendum/evolution that introduces `install.sh` as an alternative to the Homebrew tap path. Assessment against the declared plan requirements:

| Requirement (Plan Frontmatter) | Source Plan | Status | Evidence |
|-------------------------------|-------------|--------|----------|
| Release workflow cleanup (checksum + smoke test) | 27-01 | SATISFIED | release.yml has shasum step, smoke test step, no Homebrew step, auto release notes |
| install.sh script (system detection, download, checksum verify, PATH update, idempotent) | 27-02 | SATISFIED | install.sh:24-96 implements all five behaviors |
| no Swift source changes | 27-02 | SATISFIED | Commits 96ae569 and a300455 only modify `.github/workflows/release.yml` and `install.sh` respectively |

**Note on REQUIREMENTS.md coverage:** DIST-01, DIST-02, DIST-03 are mapped to Phase 23 (Homebrew tap). Phase 27 extends distribution with an `install.sh` path. DIST-02 (release workflow builds universal binary and uploads to GitHub Releases) is substantively implemented by Phase 27's release.yml. The REQUIREMENTS.md mapping table has not been updated to include Phase 27 against these IDs — this is a documentation gap, not an implementation gap. No new requirement IDs were defined for Phase 27 in REQUIREMENTS.md.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | — |

Checks performed:
- `install.sh`: no TODO/FIXME/PLACEHOLDER/HACK comments; no empty return stubs; no console.log; all steps are substantive
- `release.yml`: no placeholder steps; all 5 steps are functional YAML

---

### Human Verification Required

#### 1. Real release download

**Test:** Tag a release (e.g., `v0.1.0-test`) and run `curl -fsSL https://raw.githubusercontent.com/lasermaze/Cellar/main/install.sh | bash` on a fresh macOS machine.
**Expected:** Binary downloads, checksum verifies, binary installs to `~/.cellar/bin`, PATH updated in zshrc, `cellar --help` succeeds.
**Why human:** Requires an actual GitHub Release with uploaded artifacts; can't simulate GitHub API + release download in static analysis.

#### 2. Checksum fallback on missing .sha256

**Test:** Run install.sh with `CELLAR_VERSION` set to a release that has no `.sha256` sidecar.
**Expected:** Script prints "checksum file not available, skipping verification" and continues to install successfully.
**Why human:** Requires a real network call against a release that lacks the sidecar file.

#### 3. Non-macOS exit behavior

**Test:** Run `bash install.sh` on a Linux system (or mock `uname -s` to return "Linux").
**Expected:** Script exits immediately with "error: Cellar requires macOS. Detected: Linux" printed to stderr.
**Why human:** Behavioral test requiring non-macOS environment.

#### 4. Idempotent re-run

**Test:** Run install.sh twice in a row against a real release.
**Expected:** Second run upgrades the binary; zshrc does NOT gain a second `export PATH=...` entry.
**Why human:** Requires real install state on disk to verify the grep guard works end-to-end.

---

### Gaps Summary

No gaps. All 12 must-have truths verified against the actual codebase. Both artifacts exist, are substantive, and are correctly wired. Both commits (96ae569, a300455) are confirmed in git history and modify only the intended files.

The only open item is the REQUIREMENTS.md tracking table not being updated to reference Phase 27 alongside Phase 23 for DIST-01/DIST-02 — this is a documentation hygiene issue, not a functional gap.

---

_Verified: 2026-04-02T03:15:00Z_
_Verifier: Claude (gsd-verifier)_

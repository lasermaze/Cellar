# Pitfalls Research: Cellar

**Domain:** macOS CLI+TUI Wine game launcher for old Windows games
**Date:** 2026-03-25

## Critical Pitfalls

### 1. Wine Process Lifecycle Mismanagement
**Severity:** Critical
**Warning signs:** Zombie Wine processes, wineserver not shutting down, orphaned processes after CLI exit, high CPU in background.

Wine spawns multiple processes: `wine`, `wineserver` (shared per-prefix), and `wine-preloader`. If the CLI doesn't track the full process tree, zombies accumulate.

**Prevention:**
- Track wineserver PID per bottle, not just the game process
- On CLI exit (including SIGINT/SIGTERM), terminate wineserver for all active bottles (`wineserver -k` per WINEPREFIX)
- Set process termination handlers with timeout-based force-kill fallback
- `cellar status` should show running processes

**Phase:** Wine Process Layer (early).

### 2. Bottle Pollution / Cross-Contamination
**Severity:** Critical
**Warning signs:** Game A breaks after configuring Game B. Registry changes leak. DLL overrides from one game affect another.

**Prevention:**
- Absolute rule: one WINEPREFIX per game, set explicitly on every Wine invocation
- Never rely on default `~/.wine` — always set WINEPREFIX explicitly
- Bottle Manager refuses to operate without explicit prefix
- Verify WINEPREFIX before every `wine`, `regedit`, `wineboot` call

**Phase:** Bottle Manager design (early).

### 3. macOS Code Signing + Notarization (for distribution)
**Severity:** High (but deferred for CLI)
**Warning signs:** "Cannot be opened because the developer cannot be verified" on user machines.

For a CLI tool distributed via Homebrew, this is less critical than for a .app bundle, but still matters for GitHub release binaries.

**Prevention:**
- Sign CLI binary with Developer ID
- Notarize the binary for Gatekeeper
- Homebrew Cask formula handles most of this automatically
- Test on clean macOS install, not just dev machine

**Phase:** Distribution / packaging (later).

### 4. Apple Silicon + Homebrew Path Confusion
**Severity:** High
**Warning signs:** Wine not found despite being installed. Wrong architecture binary used. Rosetta crashes.

Homebrew installs to `/opt/homebrew/` on Apple Silicon, `/usr/local/` on Intel. Wine via Gcenx tap may be x86_64 (under Rosetta) or arm64.

**Prevention:**
- Check both Homebrew paths
- Detect Wine architecture with `file` command
- Document which Gcenx tap formulas are supported
- Dependency Checker reports Wine version AND architecture
- Warn if Wine arch doesn't match what recipe expects

**Phase:** Dependency Checker (early).

### 5. Over-Scoping Before One Game Works
**Severity:** High
**Warning signs:** Building recipe schema for 100 games before one launches. Adding AI before manual recipe works. Community features before personal use.

This killed Whisky — scope + solo maintainer burnout.

**Prevention:**
- Phase 1: Cossacks launches from `cellar launch cossacks` with a hardcoded recipe
- No AI until manual launch flow works end-to-end
- No community features until personal recipe management works
- Roadmap enforces this ordering

**Phase:** All — discipline constraint.

### 6. Deprecated OpenGL on macOS
**Severity:** High
**Warning signs:** Visual glitches, black screens, performance degradation on newer macOS versions. wined3d rendering failures.

Apple deprecated OpenGL in 2018 but it still works. For old DX8/DX9 games, wined3d → OpenGL is the **only** viable translation path on macOS. D3DMetal doesn't cover DX8/DX9, and DXVK-macOS doesn't support DX8/DX9 due to MoltenVK gaps.

**Prevention:**
- Test on latest macOS version regularly
- Track macOS OpenGL deprecation status
- Recipes should note OpenGL-specific workarounds
- cnc-ddraw can help DirectDraw games bypass some OpenGL issues
- Future: monitor DXVK-macOS DX9 support (depends on MoltenVK extensions)

**Phase:** Ongoing — affects all Wine-based rendering.

## Medium Pitfalls

### 7. Silent Wine Failures
**Severity:** Medium
**Warning signs:** Game "launches" but nothing appears. Wine exits code 0 but no window.

**Prevention:**
- Always capture stdout/stderr via Pipe
- Log everything to per-launch log file
- Detect suspicious patterns: quick exit (<2s), no window created, D3D init errors
- Surface log summary even on apparent "success"

**Phase:** Wine Process Layer + log capture.

### 8. Homebrew Installation Failure Modes
**Severity:** Medium
**Warning signs:** Guided install hangs. Xcode CLT prompt confuses user. Admin password needed.

**Prevention:**
- Check for Xcode CLT first, guide separately
- Explain admin password requirement before triggering install
- Show progress (Homebrew install takes minutes)
- Fallback: "Run this in Terminal: ..."
- Test guided flow on clean macOS install

**Phase:** Dependency Checker + onboarding.

### 9. Recipe Schema Premature Optimization
**Severity:** Medium
**Warning signs:** Designing a recipe format for every Wine config before knowing which configs matter.

**Prevention:**
- Start with minimum fields for Cossacks
- Add fields as new games need them
- Version the schema for migration

**Phase:** Recipe Engine design.

### 10. API Key Security
**Severity:** Medium
**Warning signs:** Keys in plaintext config files. Keys leaked in logs or debug output.

**Prevention:**
- Store keys in macOS Keychain (even for CLI tools, `security` command works)
- Never log keys
- Exclude keys from any debug bundle export
- AI features gracefully degrade without a key

**Phase:** AI Subsystem.

### 11. Wine Version Drift
**Severity:** Medium
**Warning signs:** Recipe works with Wine 9.x but breaks with 10.x. Gcenx tap updates Wine, recipes break.

**Prevention:**
- Recipes specify Wine version tested-with (not hard requirement)
- Warn if installed Wine version differs significantly
- Don't block launch — just warn

**Phase:** Recipe Engine + Dependency Checker.

### 12. Gcenx Tap Dependency
**Severity:** Medium
**Warning signs:** Gcenx tap goes offline or unmaintained. Tap URL changes.

The entire Wine-on-macOS Homebrew ecosystem depends on one maintainer (Gcenx). If they step away, the tap could go stale.

**Prevention:**
- Document alternative Wine sources (macOS_Wine_builds releases on GitHub)
- Support configurable Wine binary path (`cellar config wine-path /path/to/wine`)
- Don't hard-code tap name in installation logic

**Phase:** Dependency Checker.

## Summary

| # | Pitfall | Severity | Phase Impact |
|---|---------|----------|--------------|
| 1 | Wine process lifecycle | Critical | Wine Process Layer |
| 2 | Bottle cross-contamination | Critical | Bottle Manager |
| 3 | Code signing / notarization | High | Distribution |
| 4 | Apple Silicon path confusion | High | Dependency Checker |
| 5 | Over-scoping | High | All phases |
| 6 | Deprecated OpenGL | High | Ongoing |
| 7 | Silent Wine failures | Medium | Wine Process Layer |
| 8 | Homebrew install failures | Medium | Onboarding |
| 9 | Recipe schema over-engineering | Medium | Recipe Engine |
| 10 | API key security | Medium | AI Subsystem |
| 11 | Wine version drift | Medium | Recipe Engine |
| 12 | Gcenx tap dependency | Medium | Dependency Checker |

---
*Researched: 2026-03-25*

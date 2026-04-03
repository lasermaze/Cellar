# Phase 26: ISO disc image support for game installation - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend `cellar add` to accept disc image files (.iso, .bin/.cue) in addition to bare .exe installers. Mount the image, discover the installer executable inside, run it through the existing bottle/recipe pipeline, and unmount after installation completes.

</domain>

<decisions>
## Implementation Decisions

### Supported formats
- `.iso` — primary target, most common disc image format for old PC games
- `.bin/.cue` — second most common (many GOG and scene releases). If a `.cue` is provided, use the referenced `.bin`. If a `.bin` is provided directly, look for a companion `.cue` in the same directory.
- Other formats (.mdf/.mds, .nrg, etc.) are out of scope — too niche, users can convert with third-party tools

### Mount strategy
- Use macOS `hdiutil attach` for mounting — it handles .iso natively and can handle some .bin files
- For .bin/.cue that hdiutil can't mount, attempt conversion to .iso using `hdiutil convert` first
- Mount to a temporary directory, unmount after installation (always, even on failure)
- If mount fails, print actionable error message suggesting the user convert the image or extract files manually

### Installer discovery
- After mounting, scan the volume for installer executables in priority order:
  1. Parse `autorun.inf` if present — extract the `open=` path
  2. Look for common installer names at volume root: `setup.exe`, `install.exe`, `Setup.exe`, `Install.exe`
  3. If multiple candidates found, present them to the user for selection
  4. If no installer found, list all `.exe` files and let user choose, or error if none exist
- Game name derived from volume label (if meaningful) or the image filename

### AddCommand integration
- AddCommand detects input file extension — if `.iso`, `.bin`, or `.cue`, route through disc image handler before the existing pipeline
- The disc image handler returns a path to the installer `.exe` on the mounted volume
- From that point forward, the existing AddCommand pipeline runs unchanged (bottle creation, installer execution, exe discovery, recipe generation)
- Unmount happens in a `defer` block to ensure cleanup regardless of success/failure

### CLI UX
- `cellar add /path/to/game.iso` — just works, same command as .exe
- Print mount/unmount status messages so user knows what's happening
- If the image contains multiple discs (multi-disc games), handle disc 1 only — user swaps manually if needed (rare for old games)

### Claude's Discretion
- Whether to create a separate `DiscImageHandler` struct or inline the logic in AddCommand
- Exact hdiutil flags for mounting (read-only, nobrowse, etc.)
- Whether to support .img files (often just renamed .iso)
- Temp directory naming/cleanup strategy
- How to handle cases where hdiutil needs sudo (shouldn't for read-only mounts)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AddCommand.swift` (320 lines) — the entire add pipeline: dependency check, bottle creation, installer run, exe discovery, recipe generation
- `WineProcess` — already handles running arbitrary .exe files with Wine
- `GuidedInstaller.runStreamingProcess()` — runs shell processes with streaming output (could be used for hdiutil)

### Established Patterns
- AddCommand accepts `@Argument var installerPath: String` — extend to accept disc images
- Game ID derived from filename via `slugify(installerName)`
- All commands are `AsyncParsableCommand` (migrated in Phase 24)

### Integration Points
- `AddCommand.run()` line 17-24 — file existence check (extend to detect disc images)
- `AddCommand.run()` line 96 — where installer .exe path is used (swap in discovered path from mounted volume)
- `Process` / `hdiutil` — macOS system command, no dependencies needed

</code_context>

<specifics>
## Specific Ideas

- User directive: "standard approach" — use hdiutil, scan for common installer names, support .iso and .bin/.cue
- Many GOG games ship as .exe installers (already supported) but older releases and scene copies often come as .iso or .bin/.cue
- The mount/discover/unmount pattern should be transparent to the rest of the pipeline

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 26-iso-disc-image-support-for-game-installation*
*Context gathered: 2026-04-02*

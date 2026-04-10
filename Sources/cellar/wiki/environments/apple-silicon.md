# Apple Silicon (arm64)

Apple Silicon Macs (M1, M2, M3, M4 series) run Wine through Rosetta 2, Apple's x86_64
to ARM translation layer. This introduces important constraints and a different
compatibility profile from Intel Macs.

## Architecture Overview

```
Windows game (x86/x86_64)
  → Wine (x86_64, compiled for macOS)
  → Rosetta 2 (x86_64 → arm64 translation)
  → macOS/ARM
```

DXVK path (for D3D games):
```
Direct3D → DXVK (Vulkan) → MoltenVK (Vulkan → Metal) → Metal GPU drivers
```

## No Native ARM Wine

As of 2026, there is no native ARM64 build of Wine for macOS. All Wine builds run
through Rosetta 2. This is expected and supported — Rosetta 2 is fast enough that
the translation overhead is not a practical bottleneck for most games.

**Implication:** Cellar always installs the x86_64 Wine build, even on Apple Silicon.
The Homebrew formula for wine-stable is x86_64-only; brew will use Rosetta automatically.

## WoW64 Mode (All Bottles Are win64)

On Apple Silicon Wine, all bottles use WoW64 (Windows-on-Windows 64-bit) mode:
- The Wine binary is 64-bit (x86_64)
- WoW64 enables running 32-bit (x86) Windows executables inside the 64-bit prefix
- All new bottles in Cellar are created as win64 bottles

**Implication:** 32-bit games work in a win64 bottle on Apple Silicon. There is no
need to create a win32 bottle. The `--arch win32` flag is informational only.

Source: Wine macOS FAQ, Cellar Phase 37 research

## GPTK (Game Porting Toolkit)

Apple's Game Porting Toolkit (GPTK) is an alternative Wine distribution provided by
Apple, optimized for macOS game compat:
- Bundled with Xcode Command Line Tools (available via `brew install apple/apple/game-porting-toolkit`)
- Includes a patched Wine build with improved Direct3D → Metal bridging
- Uses the same `gameportingtoolkit` wrapper binary
- Collective memory entries for GPTK won't match vanilla wine-stable runs (different flavor)

**Detection:** Cellar's `CollectiveMemoryService` detects GPTK by checking for
`/usr/local/bin/gameportingtoolkit` or `/opt/homebrew/bin/gameportingtoolkit`.

If GPTK is installed, it is used preferentially. If only wine-stable is installed,
vanilla Wine is used.

## MoltenVK for Vulkan (DXVK Path)

Vulkan is not natively available on macOS. MoltenVK bridges Vulkan calls to Metal.
DXVK on macOS uses MoltenVK automatically.

**Current MoltenVK limitations:**
- Tessellation shaders: limited support (some D3D11 games fail)
- Geometry shaders: limited support
- Sparse resources: not supported
- Performance: 10-20% overhead vs native Vulkan

**MoltenVK version:** Bundled with Wine Homebrew formula. To get newer MoltenVK,
update wine-stable via brew: `brew upgrade wine-stable`.

## Rosetta 2 Performance Notes

- First-launch overhead: Rosetta 2 generates native translations on first run
- Subsequent runs: Rosetta cache is used, negligible overhead
- Gaming performance: typically within 5-10% of native x86_64 hardware for CPU-bound games
- GPU performance: Metal is the native GPU API; DXVK → MoltenVK → Metal adds overhead

## Known Apple Silicon Compatibility Quirks

- Some games using Direct3D 11 tessellation stages may fail (MoltenVK limitation)
- Games using 16-bit Windows subsystem (Win16) do not run — Wine doesn't support Win16 on 64-bit
- Some installers check CPU vendor strings and refuse to run (rare; fix: `CPUVENDORID=GenuineIntel`)
- Games that spawn 32-bit child processes work fine in WoW64 mode

See also: [engines/dxvk.md](../engines/dxvk.md), [environments/wine-stable-9.md](wine-stable-9.md)

Last updated: 2026-04-06

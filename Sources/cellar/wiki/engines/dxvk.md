# DXVK

DXVK translates Direct3D 9, 10, and 11 API calls to Vulkan. On macOS, Vulkan is provided
by MoltenVK (a Vulkan-to-Metal translation layer). The full chain is:
`Direct3D → DXVK → Vulkan → MoltenVK → Metal`

## When to Use DXVK

- Games using Direct3D 9, 10, or 11 (not DirectDraw, not D3D 12)
- Games that crash or have severe rendering corruption with WineD3D
- Games reporting shader compilation errors or device creation failures
- When WineD3D falls back to software rendering (extremely slow)

## When NOT to Use DXVK

- DirectDraw games (pre-D3D9) — DXVK does not handle DirectDraw
- OpenGL games running under Wine's WGL — DXVK doesn't intercept OpenGL
- D3D12 games — use VKD3D-Proton instead (not currently in Cellar scope)

## Installing DXVK

**Via winetricks (recommended):**
```
winetricks dxvk
```
This installs the current stable version (2.x as of 2026) into the Wine prefix.

**Manual install:** Download from https://github.com/doitsujin/dxvk/releases
and copy `x64/*.dll` files to `~/.wine/drive_c/windows/system32/` (or game dir).

## Version Notes

- DXVK 1.x: Supports D3D9/10/11. Stable, lower GPU requirements.
- DXVK 2.x: Improved shader compilation, better async support, higher perf.
  Preferred on Apple Silicon (MoltenVK compatibility improved in 2.x).
- Older games (pre-2010) often work fine with DXVK 1.x; no benefit from 2.x.

Source: DXVK GitHub releases, ProtonDB game reports

## Environment Variables

```bash
# Show performance overlay (0=off, 1=fps, 2=full stats)
DXVK_HUD=1

# Force async shader compilation (reduces stutters at cost of initial glitches)
DXVK_ASYNC=1

# Log level: none, error, warn, info, debug
DXVK_LOG_LEVEL=warn

# Limit DXVK to specific D3D version (9, 10, 11)
# Usually not needed; DXVK auto-detects
```

## Apple Silicon Notes

On Apple Silicon, Vulkan is not natively available — MoltenVK bridges Vulkan to Metal.
This introduces additional translation overhead and some compatibility quirks:

- Shader compilation via MoltenVK is slower than native Vulkan — expect longer first-launch
  times while shaders compile. DXVK_ASYNC=1 can help reduce stutters.
- Some DXVK 1.x versions had MoltenVK incompatibilities. DXVK 2.x is significantly more
  stable on MoltenVK.
- If a D3D11 game crashes immediately on Apple Silicon, try DXVK 2.3+ specifically.
- Tessellation and geometry shaders have limited support via MoltenVK — some D3D11 titles
  requiring these may not render correctly.

See also: [environments/apple-silicon.md](../environments/apple-silicon.md)

## DLL Overrides Required

When DXVK is installed manually (not via winetricks):
```
WINEDLLOVERRIDES="d3d9=n;d3d10core=n;d3d11=n;dxgi=n"
```
Winetricks sets these overrides automatically.

## Disabling DXVK

If a game works better with WineD3D than DXVK:
```
WINEDLLOVERRIDES="d3d9=b;d3d10core=b;d3d11=b;dxgi=b"
```
Forces Wine's built-in D3D (WineD3D) instead of DXVK native DLLs.

See also: [symptoms/d3d-errors.md](../symptoms/d3d-errors.md)

Last updated: 2026-04-06

# Direct3D Errors

Direct3D errors occur when a game's graphics API calls fail at the Wine/DXVK layer.
These typically manifest as crash-on-launch, black screen, or rendering corruption.

## Device Creation Failure

The most common D3D error. The game calls `D3D9CreateDevice` or `D3D11CreateDevice`
and it fails.

**Diagnosis:** Wine stderr or game log contains:
```
Direct3D device creation failed
Failed to create D3D device
Could not find any compatible Direct3D device
```

**Cause 1: DXVK not installed (D3D9/10/11 games)**
```
winetricks dxvk
```
DXVK significantly improves D3D device creation success on Wine/macOS versus WineD3D.

**Cause 2: MoltenVK version issue (Apple Silicon)**
On Apple Silicon, DXVK calls Vulkan via MoltenVK. Older MoltenVK versions (pre-1.2)
have D3D11 feature level limitations. If bundled MoltenVK is old:
- Update Wine via Homebrew: `brew upgrade wine-stable`
- This typically bundles a newer MoltenVK version

**Cause 3: Feature level too high**
Some games request D3D11 feature level 11.1 or higher. Wine/DXVK/MoltenVK may only
support up to 11.0 on older macOS.

Wine registry workaround to force a lower D3D11 feature level:
```
HKEY_CURRENT_USER\Software\Wine\Direct3D
"MaxVersionGL"="4.4"
```

Source: DXVK GitHub issues, Wine bugzilla

## Shader Compilation Errors

**Diagnosis:** Wine stderr contains:
```
GLSL shader compilation failed
SPIR-V compilation error
Failed to compile shader
```

**Cause:** DXVK's shader compilation fails with the current MoltenVK/GPU combo.

**Fix — Enable async shader compilation:**
```
DXVK_ASYNC=1
```
This compiles shaders on a background thread. The game may show graphical glitches
initially, but avoids hangs and crashes from shader compilation stalls.

**Fix — Use WineD3D instead of DXVK:**
If a specific game's shaders consistently fail with DXVK:
```
WINEDLLOVERRIDES="d3d9=b;d3d10core=b;d3d11=b;dxgi=b"
```
WineD3D uses OpenGL instead of Vulkan — may work when DXVK shaders fail.

## WineD3D Software Renderer Fallback

If neither DXVK nor WineD3D hardware acceleration works, Wine falls back to a software
renderer (extremely slow — 1-5 FPS).

**Diagnosis:** Game runs but is unplayably slow. Wine stderr may show:
```
Using software renderer
GL_RENDERER: llvmpipe
```

**Fix:**
```
MESA_GL_VERSION_OVERRIDE=4.5COMPAT
MESA_GLSL_VERSION_OVERRIDE=450
```
Forces Mesa to report a higher OpenGL version, which may unblock hardware acceleration.

## DXVK vs WineD3D Selection Guide

| Game Scenario | Recommended |
|---------------|-------------|
| D3D9/10/11 game, modern (post-2010) | DXVK 2.x |
| D3D9/10/11 game, older (2004-2010) | DXVK 1.x or 2.x |
| DirectDraw game (pre-D3D9) | cnc-ddraw (NOT DXVK) |
| Game crashes with DXVK | WineD3D built-in |
| OpenGL game | Neither (Wine WGL handles it) |
| D3D12 game | Not supported in Cellar scope |

## Checking Which D3D Version a Game Uses

Use Cellar's `inspect_game` tool — it reads PE imports and reports which D3D DLLs
the executable imports (d3d9.dll, d3d10.dll, d3d11.dll, d3d12.dll).

See also: [engines/dxvk.md](../engines/dxvk.md), [symptoms/black-screen.md](black-screen.md)

Last updated: 2026-04-06

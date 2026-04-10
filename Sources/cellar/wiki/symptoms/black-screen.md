# Black Screen on Launch

A black screen (game launches, window appears, but shows only black) is one of the most
common Wine compatibility symptoms. It indicates the game process is running but the
renderer is failing to produce visible output.

## Common Causes

### 1. Missing cnc-ddraw (DirectDraw games)

The most common cause for games released before 2004. Wine's built-in ddraw.dll produces
a black screen for many DirectDraw games on Wine 9+ (regression introduced in Wine 9.0).

**Diagnosis:** Check game release year and if it imports `ddraw.dll`. In Wine log, look for:
```
fixme:ddraw: ...
```
**Fix:** Install cnc-ddraw wrapper:
```
winetricks cnc-ddraw
WINEDLLOVERRIDES="ddraw=n,b"
```
See also: [engines/directdraw.md](../engines/directdraw.md)

### 2. Wrong Renderer / Graphics API Mismatch

Game is trying to use a graphics API that isn't working in the current Wine/DXVK config.

**Diagnosis:** Check Wine stderr for:
```
Direct3D device creation failed
```
or check if the game has a settings file that can select the renderer.

**Fix options:**
- Install DXVK if game uses D3D9/10/11: `winetricks dxvk`
- Force OpenGL for Unity games: add `-force-opengl` to launch args
- For D3D9 games, try `MESA_GL_VERSION_OVERRIDE=4.5COMPAT` (Mesa software fallback)

### 3. Resolution or Fullscreen Issue

Game launches in a resolution the display can't handle, or fullscreen mode fails.

**Diagnosis:** Game window appears briefly then goes black. Sometimes a mouse cursor visible.

**Fix:** Enable Wine's virtual desktop mode:
```
wine regedit
# Set: HKEY_CURRENT_USER\Software\Wine\Explorer\Desktops\Default = 1024x768
```
Or use winetricks:
```
winetricks vd=1024x768
```

### 4. Missing Visual C++ or .NET Runtime

Some games black-screen silently when a required runtime DLL is missing rather than
showing an error dialog.

**Fix:**
```
winetricks vcrun2019
winetricks dotnet48
```

## Diagnostic Steps

1. Run `cellar launch <game>` and capture Wine stderr
2. Check for `ddraw` mentions → cnc-ddraw fix
3. Check for `Direct3D` or `d3d` mentions → DXVK or renderer fix
4. Check for `module not found` → missing DLL fix
5. Check for exception codes (0xc0000005 = access violation, 0xe0434352 = .NET exception)
6. If no errors in log, suspect resolution/fullscreen issue → virtual desktop mode

## Quick Fix Sequence

For unknown old (pre-2005) games with black screen:
1. Try `winetricks cnc-ddraw` + `WINEDLLOVERRIDES="ddraw=n,b"` first
2. If still black: `winetricks dxvk` + remove ddraw override
3. If still black: `winetricks vd=1024x768` (virtual desktop)
4. If still black: check if game needs `vcrun2019` or `dotnet48`

See also: [engines/directdraw.md](../engines/directdraw.md), [symptoms/d3d-errors.md](d3d-errors.md)

Last updated: 2026-04-06

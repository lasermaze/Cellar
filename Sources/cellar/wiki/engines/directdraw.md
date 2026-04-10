# DirectDraw Games

Games using the DirectDraw API (typically DOS-era and early Windows games from 1995-2002)
require special handling on modern Wine because Wine's built-in ddraw.dll has known rendering
issues with WineD3D on macOS.

## Required Setup: cnc-ddraw Wrapper

The cnc-ddraw wrapper is the standard fix for DirectDraw games on Wine. It intercepts
DirectDraw calls and redirects them through OpenGL or Vulkan, bypassing Wine's problematic
built-in ddraw implementation.

**DLL override required:**
```
WINEDLLOVERRIDES="ddraw=n,b"
```
The `n,b` order means: try native (cnc-ddraw.dll from winetricks/manual install) first,
fall back to built-in if native not found.

**Install via winetricks:**
```
winetricks cnc-ddraw
```

**Manual install:** Download cnc-ddraw from https://github.com/FunkyFr3sh/cnc-ddraw
and place `ddraw.dll` in the game directory.

## Games Known to Need cnc-ddraw

- LEGO Racers (1999) — black screen without cnc-ddraw on Wine 9+
- LEGO Racers 2 (2001) — black screen without cnc-ddraw on Wine 9+
- Cossacks: European Wars — display corruption without cnc-ddraw
- Command & Conquer (Red Alert, Tiberian Sun) — intended use case for cnc-ddraw
- Age of Empires (1997) — DirectDraw rendering issues on Wine 9+
- Starcraft (original, not Remastered) — requires cnc-ddraw for stable display

Source: Lutris installer scripts, cnc-ddraw GitHub issues

## Wine 9+ Regression

Wine 9.0 introduced a regression where built-in ddraw.dll produces a black screen or
severe corruption in many DirectDraw games that previously worked. This regression is
present in Wine Stable 9.x and Wine Staging 9.x on macOS (both Intel and Apple Silicon).

**Workaround:** Install cnc-ddraw. Do NOT use DXVK for DirectDraw games — DXVK only
handles Direct3D 9/10/11, not DirectDraw.

## Detecting DirectDraw Games

Check the PE import table. DirectDraw games import `ddraw.dll`. In Cellar, the
`inspect_game` tool reads PE headers:
- `exe_type`: look for `ddraw` in imports
- If game was released before 2004 and crashes on launch, suspect DirectDraw first

## cnc-ddraw Configuration

cnc-ddraw reads from `cnc-ddraw.ini` in the game directory. Useful options:
```ini
[cnc-ddraw]
renderer=opengl        ; or "auto", "gdi", "opengl", "direct3d9"
width=0                ; 0 = native game resolution
height=0
windowed=false
```

On macOS/Wine, `renderer=opengl` is most compatible. `renderer=direct3d9` requires DXVK.

See also: [symptoms/black-screen.md](../symptoms/black-screen.md)

Last updated: 2026-04-06

# Crash on Launch (Before Menu)

A crash before the main menu appears means the game process started but terminated
abnormally. This is distinct from a black screen (process running) or a missing-exe
error (process never starts).

## Identifying a Crash vs Other Failures

- **Crash:** Wine process starts, then terminates with non-zero exit code
- **Black screen:** Wine process runs but no visible output (see [black-screen.md](black-screen.md))
- **Missing DLL:** Wine prints "err:module:..." and exits immediately on process start

Check Wine stderr output for the exit code and error type.

## Common Causes

### 1. Missing PE Import (DLL not found)

The game executable imports a DLL that isn't present in the Wine prefix or system.

**Diagnosis:** Look for in Wine stderr:
```
err:module:import_dll Library MSVCP140.dll (which is needed by L"game.exe") not found
err:module:LdrInitializeThunk Importing dlls for L"game.exe" failed, status c0000135
```

**Fix — Visual C++ runtimes (most common):**
```
winetricks vcrun2005    # Visual C++ 2005
winetricks vcrun2008    # Visual C++ 2008
winetricks vcrun2010    # Visual C++ 2010
winetricks vcrun2015    # Visual C++ 2015
winetricks vcrun2019    # Visual C++ 2019 (also covers 2022)
```
Most modern games need `vcrun2019`. Legacy games (2005-2012) may need an older version.

**Fix — .NET Framework:**
```
winetricks dotnet40     # .NET 4.0
winetricks dotnet48     # .NET 4.8
```
Unity games and many C#-based games need .NET 4.x.

**Fix — DirectX:**
```
winetricks d3dx9        # DirectX 9 June 2010 update (shader compiler)
winetricks directx9     # Full DirectX 9 redistributable
```

Source: ProtonDB crash reports, Cellar agent session logs

### 2. Access Violation (0xc0000005)

The game crashes with a memory access violation immediately on startup.

**Diagnosis:** Wine stderr shows:
```
wine: Unhandled page fault on read/write access to 0x... at address 0x... (thread ...)
```

**Common fixes:**
- Install `vcrun2019` (corrupt/missing CRT heap can cause access violations)
- Try disabling DXVK (`WINEDLLOVERRIDES="d3d9=b;d3d11=b"`) — some games crash with DXVK async
- Try `WINEDEBUG=+relay` to get full call stack (verbose, for diagnostics only)

### 3. .NET Exception (0xe0434352)

A managed code exception from the .NET/Mono runtime.

**Diagnosis:** Wine stderr shows:
```
wine: Unhandled exception 0xe0434352 in thread XX at address 0x...
```

**Fix:**
```
winetricks dotnet48
winetricks vcrun2019
```

### 4. DX Debug Layer / Overlay Crash

Some games crash when the DirectX debug layer or Steam overlay tries to inject.

**Fix:**
```
WINEDLLOVERRIDES="GameOverlayRenderer64=d"   # Disable Steam overlay
DXVK_LOG_LEVEL=none                          # Suppress DXVK debug layer
```

### 5. Anti-Cheat (EAC / BattlEye)

Games with Easy Anti-Cheat or BattlEye will crash on launch — these anti-cheat systems
explicitly block Wine/Proton (or require kernel-level access unavailable on macOS).

**Diagnosis:** Game log mentions "EasyAntiCheat" or "BattlEye", or crashes with no
useful Wine error.

**Resolution:** No fix available. Anti-cheat games cannot run on Wine without official
Proton compatibility — Cellar does not support bypassing anti-cheat systems.

## Diagnostic Approach

1. Capture full Wine stderr: `cellar launch <game>` (stderr logged automatically)
2. Search stderr for `err:module:` → missing DLL fix
3. Search stderr for `0xe0434352` → dotnet/Mono fix
4. Search stderr for `0xc0000005` → access violation fix
5. Search stderr for `EasyAntiCheat` or `BattlEye` → game unsupported on Wine

## Quick Fix Sequence for Unknown Crash

```
winetricks vcrun2019
winetricks dotnet48
```
Cover these two first — they fix the majority of modern game crashes on Wine.

See also: [symptoms/black-screen.md](black-screen.md), [symptoms/d3d-errors.md](d3d-errors.md)

Last updated: 2026-04-06

# Unity Engine Games on Wine

Unity games (2D and 3D) have a distinct set of Wine compatibility patterns. Most issues
stem from the Mono runtime, .NET dependencies, and Unity's networking/DRM systems.

## Common Issues

### Mono Runtime Crashes

Unity games embed Mono for C# scripting. On older Wine versions (pre-8.0), Mono can
crash during initialization with:
```
wine: Unhandled exception 0xe0434352 in thread XX
```
This is a .NET/Mono exception. Fixes:
- Install `dotnet48` via winetricks (installs the .NET 4.8 runtime)
- Alternatively, install `vcrun2019` (Visual C++ 2019 runtime) which many Unity games need

```
winetricks dotnet48
winetricks vcrun2019
```

### Steam DRM Conflicts

Unity games distributed via Steam with DRM protection can hang or crash when the Steam
overlay attempts to inject into the Unity process:
```
WINEDLLOVERRIDES="GameOverlayRenderer64=d"
```
This disables the Steam overlay DLL (prevents injection without breaking Steam auth).

### Unity Web Requests (UnityWebRequest)

Unity games that make HTTP/HTTPS calls (multiplayer, telemetry, update checks) use
`winhttp.dll`. Wine's built-in winhttp has limited HTTPS support. Fix:
```
WINEDLLOVERRIDES="winhttp=n,b"
```
Install the native winhttp via winetricks:
```
winetricks winhttp
```

Source: Lutris Unity game installers, ProtonDB Unity reports

## Input and Controller Issues

Unity games often use Unity's Input System or XInput. On Wine:
- XInput works via Wine's xinput1_3/xinput1_4 built-ins (usually no action needed)
- If controller input is not detected: `WINEDLLOVERRIDES="xinput1_3=n,b"`

## Graphics API Selection

Unity supports DirectX 11, DirectX 12, OpenGL, and Vulkan. On Wine/macOS:
- **DirectX 11** (default for most Unity games): Works via DXVK → MoltenVK on macOS
- **DirectX 12**: Not supported on Wine (no D3D12 translation in Cellar's scope)
- **OpenGL**: Works via Wine's WGL, but may be slower than DXVK path
- **Vulkan**: Works directly on Apple Silicon (MoltenVK) if the game exposes Vulkan

If a Unity game crashes on startup, try forcing OpenGL:
```
# Unity launch argument (add to game's launch args)
-force-opengl
```

## 32-bit vs 64-bit Unity Games

Unity can build 32-bit (x86) or 64-bit (x86_64) executables. On macOS Wine:
- All bottles run in WoW64 mode (win64 bottle handles both 32-bit and 64-bit executables)
- If the installer is 32-bit but the game exe is 64-bit, both will work in a win64 bottle

Check the exe with `file` command or Cellar's `inspect_game` tool to confirm architecture.

## Environment Variables Summary

```bash
WINEDLLOVERRIDES="winhttp=n,b"           # Fix web requests
WINEDLLOVERRIDES="GameOverlayRenderer64=d"  # Disable Steam overlay
WINEDLLOVERRIDES="xinput1_3=n,b"         # Fix controller input
```

See also: [symptoms/crash-on-launch.md](../symptoms/crash-on-launch.md)

Last updated: 2026-04-06

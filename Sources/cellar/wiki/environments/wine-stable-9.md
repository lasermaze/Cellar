# Wine Stable 9.x

Wine Stable 9.x (released January 2024, minor updates through 2024-2025) introduced
several changes affecting game compatibility. Some are improvements; some are regressions
compared to Wine 8.x.

## Key Changes in Wine 9.0

### WoW64 Architecture Change (Breaking)
Wine 9.0 changed its internal WoW64 implementation. The new architecture:
- Removes the need for separate win32 bottles in most cases
- All processes run through a 64-bit Wine core, with 32-bit emulation via ntdll
- This is the default on macOS and is how Cellar creates all new bottles

**Impact on games:** Most games are unaffected. Some older 16-bit games or games relying
on the old WINELOADER path may break.

### DirectDraw Regression (Breaking for Old Games)
Wine 9.0 introduced a regression in the built-in ddraw.dll implementation. DirectDraw
games that previously worked in Wine 8.x may show black screens or severe corruption
in Wine 9.x.

**Affected games:** DirectDraw (DDraw) titles, typically pre-2004 games
**Fix:** Install cnc-ddraw wrapper:
```
winetricks cnc-ddraw
WINEDLLOVERRIDES="ddraw=n,b"
```

Source: Wine bugzilla #55784, Lutris issue tracker

### Improved Vulkan / DXVK Support
Wine 9.x improved Vulkan layer integration. DXVK 2.x works better with Wine 9.x than
Wine 8.x for D3D11 titles. MoltenVK stability on Apple Silicon is improved in Wine 9.x
paired with DXVK 2.3+.

### NTLM/Network Authentication
Wine 9.x changed NTLM (Windows auth) handling. Games using Windows network auth or
some DRM systems that phone home may need:
```
WINEDLLOVERRIDES="ntlm_auth=n,b"
```

## Version Compatibility Reference

| Wine Version | DirectDraw | D3D9 (DXVK) | D3D11 (DXVK) | Notes |
|-------------|------------|-------------|--------------|-------|
| Wine 8.x | OK | OK | OK | Pre-WoW64 change, DDraw works |
| Wine 9.0 | BROKEN | OK | OK | DDraw regression introduced |
| Wine 9.x stable | BROKEN* | Better | Better | *Use cnc-ddraw workaround |

Source: Wine changelog, ProtonDB macOS reports

## Wine Staging vs Wine Stable

Wine Staging is a set of patches applied on top of Wine Stable, including:
- ESYNC/FSYNC (faster synchronization primitives — significant perf gain)
- Speculative Wine patches not yet in mainline
- Additional staging fixes for specific games

**On macOS, use Wine Stable** unless:
- A specific game is documented to need a Staging patch
- You're running GPTK (Apple's patched Wine, effectively Staging-equivalent)

Cellar's Homebrew dependency uses wine-stable. GPTK is a separate optional install.

## Regression Testing Approach

When a game regresses between Wine versions:
1. Check Wine bugzilla (bugs.winehq.org) for the specific game or DLL
2. Check if the regression is in a component DXVK replaces (use DXVK to bypass)
3. Check if cnc-ddraw helps for DirectDraw regressions
4. As last resort: test with a cached Wine 8.x bottle (requires manual install)

## Known Regressions (Wine 9.x on macOS)

- `ddraw.dll` — black screen for DirectDraw games (fix: cnc-ddraw)
- Some games using `mshtml.dll` (Internet Explorer engine) — more crashes than Wine 8.x
- `crypt32.dll` changes may affect games checking SSL certificates from old servers

See also: [engines/directdraw.md](../engines/directdraw.md), [environments/apple-silicon.md](apple-silicon.md)

Last updated: 2026-04-06

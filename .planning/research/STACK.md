# Stack Research

**Domain:** macOS CLI Wine launcher — v1.1 Agentic Independence stack additions
**Researched:** 2026-03-28
**Confidence:** HIGH (CGWindowListCopyWindowInfo, PE parsing, SwiftSoup) / HIGH (max_tokens handling — verified against official Anthropic docs)

---

## Context: What This File Is

This file covers **only new stack additions for v1.1**. The existing stack (Swift 6, ArgumentParser, URLSession, Foundation.Process, Wine via Gcenx) is validated and documented in the previous STACK.md. Do not re-litigate those decisions here.

The five technical questions for v1.1:
1. CGWindowListCopyWindowInfo for macOS window detection
2. PE header parsing for game engine detection
3. Wine trace:msgbox / trace:dialog log parsing
4. Structured HTML extraction from web pages
5. Anthropic max_tokens handling in the agent loop

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| CoreGraphics (built-in) | macOS 14+ | macOS window list enumeration | CGWindowListCopyWindowInfo returns title, owner, bounds, layer for all on-screen windows. No external dependency. Already available in Foundation imports on macOS. |
| Swift Data (Foundation) | built-in | PE header parsing | PE headers are fixed-offset binary structures. Foundation `Data` + `withUnsafeBytes` reads them without any library. The entire PE magic, machine type, and import table are at documented offsets. |
| SwiftSoup | 2.8.7 | HTML parsing for structured fix extraction from web pages | Pure Swift, SPM-compatible, jQuery-like CSS selector API. The only production-grade HTML parser in the Swift ecosystem. No C dependencies. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftSoup | 2.8.7 | DOM traversal, CSS selectors on fetched HTML | Use when fetch_page needs to extract structured data (tables, code blocks, list items) from WineHQ AppDB, PCGamingWiki, and forum pages rather than returning raw HTML |

No other new dependencies are required. All other v1.1 features (Wine trace parsing, max_tokens handling, engine detection) are implemented with Foundation types already in use.

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| (no new tools) | — | No new toolchain additions needed for v1.1 |

---

## Feature-by-Feature Analysis

### 1. CGWindowListCopyWindowInfo — macOS Window Detection

**Framework:** `CoreGraphics` — already available on macOS 14+, no import change needed (it's re-exported through AppKit/Cocoa but can also be imported directly as `import CoreGraphics`).

**Function signature:**
```swift
CGWindowListCopyWindowInfo(_ option: CGWindowListOption, _ relativeToWindow: CGWindowID) -> CFArray?
```

**Key dictionary keys returned per window:**
- `kCGWindowOwnerName` — process name (e.g., "wineserver", "wine64-preloader")
- `kCGWindowName` — window title (e.g., "Error", "DirectDraw Init Failed")
- `kCGWindowBounds` — CGRect as CFDictionary with X, Y, Width, Height
- `kCGWindowLayer` — z-order layer (dialogs have layer > 0)
- `kCGWindowOwnerPID` — PID for matching against known Wine PIDs

**Usage for Wine dialog detection:**
```swift
import CoreGraphics

func wineWindows(for pid: pid_t) -> [(title: String, bounds: CGRect)] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return list.compactMap { info in
        guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
              ownerPID == pid,
              let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
        else { return nil }
        let title = info[kCGWindowName as String] as? String ?? ""
        let bounds = CGRect(
            x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
            width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0
        )
        return (title: title, bounds: bounds)
    }
}
```

**Permission situation (IMPORTANT):**

`kCGWindowName` (the window title) requires Screen Recording permission on macOS 10.15+. Without it, the title key returns `nil` or an empty string. However:

- `kCGWindowOwnerName`, `kCGWindowBounds`, `kCGWindowLayer`, and `kCGWindowOwnerPID` are available **without** Screen Recording permission.
- This means dialog detection via size heuristics (small window = dialog, large window = game) and layer detection works **without requiring any permission**.
- Window title is a bonus signal — don't require it.

**Not deprecated.** `CGWindowListCopyWindowInfo` is not deprecated as of macOS 15 Sequoia. Only `CGWindowListCreateImage` (screenshot capture) and `CGDisplayStream` are being migrated toward ScreenCaptureKit. Window info enumeration remains available.

**Dialog heuristic without title:**
- Dialog windows: typically < 600px wide, < 400px tall, layer > 0
- Game windows: typically large (640x480 minimum for old games), layer = 0 or matches game resolution

**Confidence:** HIGH — verified against Apple developer forum posts, confirmed non-deprecated as of macOS 15.

---

### 2. PE Header Parsing — Game Engine Detection

**Approach:** Pure Swift with Foundation `Data`. No external library needed. PE format is a public standard with fixed offsets.

**What to extract for engine detection:**

| Field | PE Offset | Value | Engine Signal |
|-------|-----------|-------|---------------|
| Magic | 0x00 | `MZ` (0x4D5A) | Confirms PE file |
| PE signature offset | 0x3C | uint32 LE | Pointer to IMAGE_NT_HEADERS |
| Machine type | PE+4 | 0x014C = i386, 0x8664 = x64 | 32-bit vs 64-bit |
| PE32/PE32+ magic | PE+24 | 0x010B or 0x020B | Optional header type |
| Import table RVA | PE+24+104 (PE32) or PE+24+120 (PE32+) | RVA | Points to imported DLL list |

**Import table DLL names are the primary engine detector** for old Windows games. The import table lists every DLL the exe loads at startup — these are reliable engine fingerprints.

**Example engine fingerprints from import DLL names:**
```
mdraw.dll, MINMM.dll    → GSC DMCR engine (Cossacks, American Conquest)
binkw32.dll             → Bink video (common in 2000s games, not engine-specific)
SDL.dll, SDL2.dll       → SDL-based (wide variety of engines)
PHYSXLOADER.dll         → PhysX (Unreal Engine 3 era)
d3dx9_43.dll            → DirectX 9, likely 2005-2010 era game
ddraw.dll               → DirectDraw (pre-DX8, likely pre-2001)
```

**File pattern detection (second pass, no binary parsing):**
```
UnityEngine.dll present in directory  → Unity
GameAssembly.dll present              → Unity IL2CPP
ue4_redist.dll or Binaries/Win64/     → Unreal Engine 4
data.win present                      → GameMaker Studio
```

**Swift implementation pattern:**
```swift
struct PEInfo {
    let machineType: UInt16      // 0x014C = i386, 0x8664 = x64
    let is64Bit: Bool
    let importedDLLs: [String]   // lowercase DLL names from import table
}

func parsePEImports(from url: URL) -> PEInfo? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
          data.count > 0x40 else { return nil }

    // Check MZ magic
    guard data[0] == 0x4D, data[1] == 0x5A else { return nil }

    // PE header offset is at 0x3C as little-endian uint32
    let peOffset = Int(data.loadLE32(at: 0x3C))
    guard peOffset + 4 < data.count,
          data[peOffset] == 0x50, data[peOffset+1] == 0x45 else { return nil }

    let machineType = data.loadLE16(at: peOffset + 4)
    let optionalMagic = data.loadLE16(at: peOffset + 24)
    let is64Bit = optionalMagic == 0x020B

    // Import table RVA: offset 104 from optional header start for PE32, 120 for PE32+
    let importRVAOffset = peOffset + 24 + (is64Bit ? 120 : 104)
    // ... resolve RVA to file offset via section table, walk import descriptors
    // Each IMAGE_IMPORT_DESCRIPTOR has Name RVA pointing to null-terminated DLL name

    return PEInfo(machineType: machineType, is64Bit: is64Bit, importedDLLs: [])
}
```

**Practical note on implementation complexity:** Walking the import table requires resolving RVAs to file offsets via the section table. This is ~80-100 lines of Swift but no external library is needed. The alternative is shelling out to `objdump -p` (available via Xcode command line tools) which is simpler and already used elsewhere in the codebase. Use `objdump` first; implement native parsing if portability becomes an issue.

**`objdump` approach (already proven in the codebase):**
```bash
objdump -p /path/to/game.exe 2>/dev/null | grep "DLL Name:"
# Output: DLL Name: KERNEL32.dll
#         DLL Name: mdraw.dll
```

**Recommendation:** Use `objdump -p` for import table extraction (fast, no parsing code, already available). Add file-pattern engine detection (directory scan for engine-specific files) as a second pass. Reserve native PE binary parsing for future if `objdump` proves insufficient.

**Confidence:** HIGH — PE format is a published Microsoft standard, `objdump` approach is already proven in the codebase.

---

### 3. Wine trace:msgbox and trace:dialog Parsing

**No new framework needed.** Wine logs are plain text on stderr. Existing log parsing infrastructure handles this.

**Wine debug channels for dialog detection:**
- `WINEDEBUG=+dialog` — traces dialog creation, `DialogBoxParam`, `CreateDialog`, `MessageBox` calls
- `WINEDEBUG=+msgbox` — specific channel declared in `dlls/user32/msgbox.c` that traces message box text content

**Log line format** (standard Wine format):
```
XXXX:class:channel:function message
```
Where `XXXX` is thread ID (4 hex digits), `class` is trace/warn/fixme/err, `channel` is dialog or msgbox.

**Key patterns to match:**

```
# MessageBox creation (dialog channel)
0000:trace:dialog:DIALOG_CreateIndirect ...
0000:trace:dialog:DialogBoxIndirectParamAW ...

# MessageBox text content (msgbox channel)
0000:trace:msgbox:MessageBoxTimeoutW <text of the message box>

# Common Wine dialog errors that indicate stuck game
0000:fixme:dialog:DIALOG_CreateIndirect ...
0000:err:dialog:EndDialog ...

# Dialog class in window creation
0000:trace:win:CreateWindowExW ... class "#32770" ...
# #32770 is Windows' built-in dialog window class
```

**Practical implementation:** Add `+dialog,+msgbox` to the WINEDEBUG flags used in diagnostic `trace_launch` calls. Parse stderr with `NSRegularExpression` or simple string matching for `":trace:msgbox:"`, `":trace:dialog:DialogBox"`, and `"class \"#32770\""` patterns.

**Window class `#32770`** is the most reliable indicator — it is Windows' system dialog class, always present for MessageBox and DialogBox windows regardless of Wine debug channel verbosity.

**Confidence:** MEDIUM — Wine source confirmed (`dlls/user32/msgbox.c`), but exact trace output format requires validation with a running Wine instance. The `#32770` window class approach is HIGH confidence (documented Windows API behavior).

---

### 4. Structured HTML Extraction — SwiftSoup

**Why add a dependency:** The existing `fetch_page` tool returns raw HTML stripped to plain text via string manipulation. For v1.1's "extract actionable fixes" requirement, structured extraction is needed: find tables with Wine configuration values, code blocks with env var settings, and list items with step-by-step fixes. String stripping loses structure.

**Recommendation: SwiftSoup 2.8.7**

- Pure Swift, zero C/Objective-C dependencies
- SPM-compatible: `.package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.8.7")`
- CSS selector API: `doc.select("code")`, `doc.select("table")`, `doc.select("pre")`
- Actively maintained (latest release March 2025, 104 releases over 9 years)
- macOS 14 compatible

**Package.swift addition:**
```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.8.7"),
],
targets: [
    .executableTarget(
        name: "cellar",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SwiftSoup", package: "SwiftSoup"),
        ]
    ),
```

**Usage for fix extraction:**
```swift
import SwiftSoup

func extractFixes(from html: String, url: String) -> [String] {
    guard let doc = try? SwiftSoup.parse(html) else { return [] }

    var fixes: [String] = []

    // PCGamingWiki: config tables
    if let tables = try? doc.select("table.wikitable td") {
        fixes += tables.array().compactMap { try? $0.text() }
    }

    // WineHQ AppDB: code blocks with env vars
    if let code = try? doc.select("code, pre, .code") {
        fixes += code.array().compactMap { try? $0.text() }
    }

    // Forum posts: numbered list items
    if let lists = try? doc.select("ol li, .post-body li") {
        fixes += lists.array().compactMap { try? $0.text() }
    }

    return fixes.filter { $0.count > 10 && $0.count < 500 }
}
```

**Alternative considered — Foundation XMLParser:** Foundation's XMLParser is SAX-based and verbose for HTML (HTML is not valid XML). It requires significant delegate boilerplate and does not handle malformed HTML (which describes most WineHQ forum pages). SwiftSoup handles tag soup. Use XMLParser only for actual XML/RSS. Use SwiftSoup for HTML.

**Alternative considered — regex on raw HTML:** Fragile, breaks on attribute order changes, fails on nested elements. Not recommended for structured extraction.

**Confidence:** HIGH — SwiftSoup is the established Swift HTML parsing library, actively maintained, SPM-native.

---

### 5. Anthropic max_tokens Handling — Agent Loop Resilience

**No new framework needed.** This is a logic change in `AgentLoop.swift`.

**Official Anthropic guidance (verified March 2026):**

The existing `max_tokens` handler in `AgentLoop.swift` (line 126-130) appends a continuation prompt. This is the correct pattern for pure text responses but has a **critical bug for tool-use**: if `stop_reason == "max_tokens"` and the last content block is a `tool_use` block, the tool_use block is **incomplete** (truncated mid-JSON). Appending it to messages and asking to continue will not work — the API cannot recover a partial tool_use.

**Correct handling per official docs:**

```swift
case "max_tokens":
    // Check if the last block is an incomplete tool_use
    let lastBlock = response.content.last
    if case .toolUse(_, _, _) = lastBlock {
        // Incomplete tool_use — CANNOT continue, must retry with higher max_tokens
        // The current response cannot be appended to messages as-is
        print("[Agent: max_tokens hit mid tool-use — retrying with higher token budget]")
        // Increment maxTokens for next call (up to model limit)
        // Do NOT append the truncated response to messages
        // Simply retry the same messages array with higher maxTokens
        let newMaxTokens = min(maxTokens * 2, 32768)
        // ... retry logic
    } else {
        // Truncated text — safe to continue
        messages.append(AnthropicToolRequest.Message(
            role: "assistant",
            content: .blocks(response.content)
        ))
        messages.append(AnthropicToolRequest.Message(
            role: "user",
            content: .text("Continue from where you left off.")
        ))
    }
```

**Key distinction** verified against Anthropic docs:
- Truncated text block with `max_tokens`: append and continue (current code is correct)
- Truncated tool_use block with `max_tokens`: **cannot append** — must retry with higher `max_tokens` without appending the truncated response

**Token budget recommendation:**
- Current `maxTokens: 16384` in AIService.swift is appropriate for claude-sonnet-4-20250514
- Add a `currentMaxTokens` mutable property to `AgentLoop` that doubles on retry (16384 → 32768)
- Cap at model maximum (claude-sonnet-4 supports 64K output with streaming, 16K non-streaming)
- Non-streaming is the current pattern — cap retry escalation at 32768

**Confidence:** HIGH — behavior verified against official Anthropic stop_reason documentation (March 2026).

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| SwiftSoup for HTML | Foundation XMLParser | Only for well-formed XML (RSS feeds, structured API responses). Not for HTML. |
| SwiftSoup for HTML | Regex on raw HTML | Never for structured extraction. Acceptable only for pattern matching on known fixed strings (e.g., extracting a WINEDEBUG value from a known format). |
| objdump for PE imports | Native PE binary parsing in Swift | If distributing without Xcode CLI tools, or if objdump proves unreliable for cross-architecture EXEs. 80-100 lines of Swift to implement natively. |
| CGWindowListCopyWindowInfo | ScreenCaptureKit | ScreenCaptureKit is for screen capture (video frames, screenshots). CGWindowListCopyWindowInfo is for window metadata enumeration. They are different tools for different jobs. |
| CGWindowListCopyWindowInfo | NSWorkspace.runningApplications | NSWorkspace gives process names but not window titles or bounds. Use NSWorkspace to find the process, CGWindowListCopyWindowInfo to find its windows. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| ScreenCaptureKit for window detection | Requires Screen Recording permission, designed for video capture, async/complex API | CGWindowListCopyWindowInfo (metadata only, simpler, no capture permission needed) |
| Foundation XMLParser for HTML | SAX-based, verbose, fails on malformed HTML (all WineHQ forum pages are malformed) | SwiftSoup |
| pe-parse or libpe (C/C++ libraries) | Requires bridging header, breaks Swift 6 concurrency safety, adds build complexity | objdump (already available) + native Swift parsing if needed |
| Streaming Anthropic API for max_tokens | Adds significant complexity to synchronous DispatchSemaphore pattern currently used | Higher `max_tokens` ceiling + proper retry logic on truncation |
| AppKit for window detection | Requires NSApplicationDelegate, GUI event loop, incompatible with CLI context | CoreGraphics CGWindowListCopyWindowInfo |

## Stack Patterns by Variant

**If Screen Recording permission is granted:**
- Use `kCGWindowName` from CGWindowListCopyWindowInfo for title-based dialog detection ("Error", "Warning", "DirectDraw Init Failed")
- Combine with size heuristics for higher-confidence signal

**If Screen Recording permission is NOT granted (default for new installs):**
- Use bounds + layer from CGWindowListCopyWindowInfo (no permission needed)
- Dialog: width < 600, height < 400, layer > 0
- Combine with Wine trace:dialog log parsing for confirmation
- Do not prompt the user for Screen Recording permission — it creates friction for a non-critical feature

**If objdump is not available:**
- Check `which objdump` at startup
- Fall back to file-pattern detection only (directory scan for engine DLLs)
- Native PE parsing is the long-term solution if objdump proves unreliable

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| SwiftSoup 2.8.7 | Swift 5.5+, macOS 12+ | Package targets swift-tools-version 5.5 minimum. Project is macOS 14+ so no compatibility concern. |
| SwiftSoup 2.8.7 | Swift 6 | Compatible — no Swift 6 concurrency issues reported. Pure value-type parsing. |
| CoreGraphics CGWindowListCopyWindowInfo | macOS 10.9+ | Long-stable API, not deprecated through macOS 15. |

## Sources

- [Apple Developer Documentation — CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo) — function signature and key constants
- [Apple Developer Forums — window name gated by Screen Recording](https://developer.apple.com/forums/thread/126860) — permission requirements confirmed
- [Nonstrict.eu — ScreenCaptureKit on macOS Sonoma](https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/) — confirmed CGWindowListCopyWindowInfo not deprecated, CGWindowListCreateImage/CGDisplayStream are the migrating APIs (MEDIUM confidence)
- [Anthropic — Handling stop reasons](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons) — incomplete tool_use on max_tokens, correct retry pattern (HIGH confidence — official docs)
- [Wine source — dlls/user32/msgbox.c](https://github.com/wine-mirror/wine/blob/master/dlls/user32/msgbox.c) — confirmed `WINE_DEFAULT_DEBUG_CHANNEL(dialog)` and `WINE_DECLARE_DEBUG_CHANNEL(msgbox)` channels (HIGH confidence)
- [SteamDatabase FileDetectionRuleSets](https://github.com/SteamDatabase/FileDetectionRuleSets) — game engine detection patterns (two-pass regex approach) (HIGH confidence)
- [Microsoft PE Format](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format) — PE header structure, import table offsets (HIGH confidence — official spec)
- [SwiftSoup GitHub](https://github.com/scinfu/SwiftSoup) — version 2.8.7, March 2025 (HIGH confidence)

---
*Stack research for: Cellar v1.1 Agentic Independence — new capabilities only*
*Researched: 2026-03-28*

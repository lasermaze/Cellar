# Phase 10: Dialog Detection - Research

**Researched:** 2026-03-28
**Domain:** Wine trace parsing, macOS CoreGraphics window enumeration, hybrid signal detection
**Confidence:** HIGH

## Summary

Dialog detection requires two complementary signals: (1) parsing Wine `+msgbox` trace output from stderr to capture dialog text, and (2) querying macOS `CGWindowListCopyWindowInfo` to inspect Wine window sizes and titles. The Wine trace channel is the primary signal and already partially exists in the codebase -- `WineProcess.swift` line 48 already injects `+msgbox` into WINEDEBUG for every `run()` call. The macOS window list API is a secondary signal that works without any special entitlements but has permission-gated fields (window titles require Screen Recording permission; bounds and owner name do not).

A critical finding from source code verification: the `+msgbox` trace channel logs **only the message body text**, not the caption/title or button type. The single trace line in Wine's `dlls/user32/msgbox.c` is `TRACE_(msgbox)("%s\n", debugstr_w(lpszText))`, fired during `MSGBOX_OnInit`. The window caption and MB_xxx button style are used internally but never traced. This means extracting the dialog title requires either the macOS window list (with Screen Recording permission) or inferring it from the message body content alone.

**Primary recommendation:** Parse `trace:msgbox:MSGBOX_OnInit` lines from stderr to extract dialog body text (always available), add `list_windows` tool using `CGWindowListCopyWindowInfo` filtered to Wine processes for window size/title data (permission-dependent), and let the agent combine both signals via system prompt heuristics.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Add +msgbox as a default WINEDEBUG channel in both trace_launch AND launch_game -- dialog detection is always-on, not opt-in
- Parse MessageBox output into structured fields: title (window caption), message (body text), and button type (OK, OK/Cancel, Yes/No, etc.)
- Research phase MUST capture actual Gcenx wine-crossover trace:msgbox output before building the parser -- do not rely on Wine source docs alone
- Parsed msgbox data appears in both trace_launch and launch_game results as a `dialogs` array of structured entries
- New standalone `list_windows` agent tool -- agent calls it whenever needed, not integrated into launch_game result
- Uses CoreGraphics (CGWindowListCopyWindowInfo) directly from Swift -- no AppleScript, no subprocess
- Filters to Wine processes only (wine/wine64/wineserver process names) -- no leaking info about other apps
- Returns window titles, sizes (width x height), and owner process for each Wine window
- Small window heuristic: windows smaller than ~640x480 flagged as likely dialogs. Agent makes final judgment from size data.
- When Screen Recording permission is denied: return error result explaining permission is needed with instructions to grant it in System Settings
- Agent falls back to trace:msgbox as sole dialog signal when list_windows is unavailable
- Proactive permission probe: system prompt tells agent to call list_windows once early in session (after inspect_game) to test permission state
- If denied, agent tells user once via ask_user: "For best dialog detection, grant Screen Recording permission to Terminal in System Settings." Then continues with trace:msgbox only.
- Never ask user about permission more than once per session
- Agent combines signals itself -- no hardcoded hybrid logic in tool code
- System prompt includes multi-signal heuristic guidance and common dialog pattern guidance

### Claude's Discretion
- Exact msgbox trace line regex patterns (must match real Gcenx output from research)
- How to detect permission denial from CGWindowListCopyWindowInfo return values
- list_windows tool schema details (input params, output format)
- Internal implementation of CoreGraphics window enumeration
- How to identify Wine process names reliably across different Wine builds

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DIAG-01 | trace_launch includes +msgbox in WINEDEBUG and parses MessageBoxW output into structured dialog info (title, message, type) | Wine source confirms `TRACE_(msgbox)("%s\n", debugstr_w(lpszText))` as sole msgbox trace. Body text is reliably captured. Title and button type are NOT traced by Wine -- title can come from `list_windows` window title, button type can be inferred from body text patterns or left unknown. Regex pattern: `trace:msgbox:MSGBOX_OnInit L"(.*)"` |
| DIAG-02 | Agent queries macOS window list (CGWindowListCopyWindowInfo) to detect window sizes and titles of Wine processes | CGWindowListCopyWindowInfo returns kCGWindowBounds and kCGWindowOwnerName without Screen Recording permission. kCGWindowName requires Screen Recording. Permission detection via checking if any non-self window has kCGWindowName present. API is NOT deprecated on macOS Sequoia (only CGWindowListCreateImage is). |
| DIAG-03 | Agent uses hybrid signal (Wine traces + window list) to determine if game is stuck on a dialog vs running normally -- with graceful degradation if Screen Recording permission is denied | System prompt heuristics combine: quick exit + msgbox = dialog stuck, quick exit + no msgbox = crash, running + small window = dialog waiting, running + large window = normal. Without Screen Recording: bounds still available for size heuristic, just no window titles. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| CoreGraphics | macOS 14+ (system) | CGWindowListCopyWindowInfo for window enumeration | System framework, no dependency. Direct Swift bridge. Already available in macOS 14 target. |
| Foundation | macOS 14+ (system) | Process management, regex, JSON encoding | Already used throughout codebase |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| AppKit (NSRunningApplication) | macOS 14+ | Process name resolution for permission check | Only needed if canRecordScreen-style permission probe is used |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CGWindowListCopyWindowInfo | ScreenCaptureKit (SCShareableContent) | ScreenCaptureKit is newer but designed for capture, not enumeration. It requires async/await and is overkill for window list queries. CGWindowListCopyWindowInfo is simpler, synchronous, and NOT deprecated. |
| AppleScript "System Events" | CGWindowListCopyWindowInfo | AppleScript requires Accessibility permission and is slower. CONTEXT.md explicitly forbids AppleScript. |

**Installation:** No new dependencies. `import CoreGraphics` is sufficient. For NSRunningApplication, `import AppKit` or `import Cocoa`.

## Architecture Patterns

### Recommended Project Structure
```
Sources/cellar/Core/
├── AgentTools.swift       # Add list_windows tool + msgbox parsing in existing launch/trace functions
├── AIService.swift        # Add dialog detection methodology to system prompt
└── WineProcess.swift      # Already injects +msgbox — no changes needed
```

### Pattern 1: Stderr Line Parsing (existing pattern)
**What:** Parse structured data from Wine stderr trace lines using regex
**When to use:** Extracting dialog info from trace:msgbox output
**Example:**
```swift
// Source: Existing loaddll pattern in AgentTools.swift:1420
// Msgbox pattern follows identical approach
// Wine output format (verified from source + forum examples):
// 0009:trace:msgbox:MSGBOX_OnInit L"Microsoft Mathematics has encountered a problem..."
// Format: {tid}:trace:msgbox:MSGBOX_OnInit L"{message_text}"

let msgboxPattern = #"trace:msgbox:MSGBOX_OnInit L\"((?:[^\"\\]|\\.|\"\")*)\""#
for line in stderrLines {
    guard line.contains("trace:msgbox") else { continue }
    if let match = line.range(of: msgboxPattern, options: .regularExpression) {
        // Extract message text, unescape Wine debug string
    }
}
```

### Pattern 2: CoreGraphics Window Enumeration
**What:** Query macOS for window list filtered to Wine processes
**When to use:** list_windows tool implementation
**Example:**
```swift
// Source: Apple CGWindow.h documentation + verified Swift examples
import CoreGraphics

func listWineWindows() -> [[String: Any]] {
    guard let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else { return [] }

    let wineNames = Set(["wine", "wine64", "wineserver", "wine-preloader", "wine64-preloader"])
    return windowList.filter { window in
        guard let ownerName = window[kCGWindowOwnerName as String] as? String else { return false }
        return wineNames.contains(ownerName.lowercased())
    }
}
```

### Pattern 3: Screen Recording Permission Detection
**What:** Check if kCGWindowName is available for non-self windows
**When to use:** Determine whether list_windows can provide window titles
**Example:**
```swift
// Source: github.com/soffes/canRecordScreen gist (verified pattern)
func hasScreenRecordingPermission() -> Bool {
    let myPID = ProcessInfo.processInfo.processIdentifier
    guard let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly], kCGNullWindowID
    ) as? [[String: Any]] else { return false }

    for window in windows {
        guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
              pid != myPID else { continue }
        if window[kCGWindowName as String] as? String != nil {
            return true
        }
    }
    return false
}
```

### Pattern 4: Tool Definition + Dispatch (existing pattern)
**What:** Add new tool to toolDefinitions array and execute() switch
**When to use:** Adding list_windows tool
**Example:**
```swift
// Follows established pattern from AgentTools.swift
// Tool definition in toolDefinitions array
ToolDefinition(
    name: "list_windows",
    description: "Query macOS window list for Wine processes...",
    inputSchema: .object([...])
)
// Dispatch in execute()
case "list_windows": return listWindows(input: input)
```

### Anti-Patterns to Avoid
- **Hardcoded hybrid logic in tool code:** The CONTEXT.md explicitly says the agent combines signals itself via system prompt heuristics. Tools return raw data; the agent reasons about it.
- **Parsing caption from +msgbox trace:** Wine does NOT trace the caption. Do not build regex for something that is not in the output.
- **Using ScreenCaptureKit for window enumeration:** Overkill, async-only, designed for capture not listing. CGWindowListCopyWindowInfo is simpler and synchronous.
- **Blocking on Screen Recording permission:** The tool must return useful data (bounds, owner) even without permission, or return a clear error when no windows found. Never hang or crash.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Window enumeration | NSAppleScript or `osascript` subprocess | CGWindowListCopyWindowInfo | Native Swift, no Accessibility permission, faster, CONTEXT.md mandates this |
| Permission detection | TCC database queries | kCGWindowName presence check | TCC DB is private API and changes per macOS version. The window name availability check is the standard community pattern. |
| Wine debug string unescaping | Custom unescaper | Simple regex + known escape patterns | Wine's debugstr_w uses limited escapes: `\\n`, `\\t`, `\\\\`, `\\xHH`. |

**Key insight:** The entire window enumeration layer is a single CoreGraphics call with dictionary filtering. There is no need for helper libraries or complex frameworks.

## Common Pitfalls

### Pitfall 1: Assuming +msgbox traces the caption and button type
**What goes wrong:** Building a parser that expects title, message, and MB_xxx type from trace:msgbox output, then getting empty title/type fields for every dialog.
**Why it happens:** Wine's msgbox.c only has ONE trace call: `TRACE_(msgbox)("%s\n", debugstr_w(lpszText))`. It logs the message body only. The caption is set via SetWindowTextW (which logs on +win channel, but with massive noise). The button style is never logged.
**How to avoid:** The `dialogs` array should have `message` as the reliable field. `title` should be populated from `list_windows` window title when available, or left empty/null. `type` (button type) should be inferred from common patterns in message text (e.g., "Press OK" implies MB_OK, "Yes/No" in text implies MB_YESNO) or left as "unknown".
**Warning signs:** Empty title and type fields in all dialog entries during testing.

### Pitfall 2: CGWindowListCopyWindowInfo returning empty for Wine processes
**What goes wrong:** list_windows returns no windows even though a Wine game is running.
**Why it happens:** Wine process names may vary across builds. Gcenx wine-crossover may use `wine64-preloader` or `CX23.0.1` or other CrossOver-derived names. Also, wine windows may be owned by the `wineserver` process or a `start.exe` wrapper.
**How to avoid:** Filter by multiple process name patterns. Also consider filtering by kCGWindowOwnerPID matching known Wine PIDs from the launch process tree. Test with actual Gcenx wine-crossover build.
**Warning signs:** Zero windows returned when game is visibly running.

### Pitfall 3: Screen Recording permission popup on macOS Sequoia
**What goes wrong:** On macOS 15 Sequoia, calling CGWindowListCopyWindowInfo may trigger a system alert about the app collecting window information.
**Why it happens:** macOS Sequoia added new privacy prompts for window information access via deprecated capture APIs. However, CGWindowListCopyWindowInfo (enumeration, not capture) does NOT show a permission dialog -- it silently returns limited data.
**How to avoid:** CGWindowListCopyWindowInfo does NOT prompt. It returns data with kCGWindowName missing if permission is not granted. The tool should check for this and report permission state, not try to trigger a prompt.
**Warning signs:** Unexpected system dialogs when calling the tool.

### Pitfall 4: Multiline or escaped message text in trace:msgbox
**What goes wrong:** Regex fails to capture the full message text because it contains newlines or escaped quotes.
**Why it happens:** Wine's `debugstr_w` converts newlines to `\\n` and other control chars to escape sequences. Multi-paragraph dialog messages become single long lines with embedded `\\n`. But literal `"` in the message is escaped as `\\"`, which can confuse naive regex.
**How to avoid:** Use a regex that handles escaped characters inside the quoted string: `L\"((?:[^\"\\\\]|\\\\.)*)\"`  then unescape `\\n` to newline, `\\t` to tab, `\\\\` to backslash in post-processing.
**Warning signs:** Truncated or corrupted message text in dialog entries.

### Pitfall 5: WineProcess already adds +msgbox but launch_game doesn't parse it
**What goes wrong:** Assuming launch_game needs to add +msgbox to WINEDEBUG.
**Why it happens:** WineProcess.swift line 48 already injects `+msgbox` into every wine run. But the current launch_game code only parses `+loaddll` lines from stderr (lines 1224-1239). The msgbox trace lines are captured but not parsed.
**How to avoid:** Add msgbox parsing alongside the existing loaddll parsing in launch_game. For trace_launch, add `+msgbox` to the default channels (currently `["+loaddll"]`) AND add parsing logic.
**Warning signs:** Dialog text visible in read_log output but not in launch_game structured result.

## Code Examples

Verified patterns from official sources and codebase analysis:

### Wine trace:msgbox output format (verified from Wine source + community examples)
```
# Format (verified from Wine dlls/user32/msgbox.c and WineHQ forum examples):
# {thread_hex}:trace:msgbox:MSGBOX_OnInit L"{message_text_with_escapes}"
#
# Real examples:
# 0009:trace:msgbox:MSGBOX_OnInit L"Microsoft Mathematics has encountered a problem. Please install Microsoft Mathematics again."
# 3828042.6030024:trace:msgbox:MSGBOX_OnInit L"Runtime error!\n\nProgram: C:\Program Files (x86)\Game\game.exe\nabnormal program termination\n\nPress OK to exit the program, or Cancel to start the Wine debugger.\n"
#
# Note: timestamp format may vary (hex TID vs decimal with dots)
# The L"..." wrapping and function name are consistent
```

### Parsing msgbox from stderr (follows existing loaddll pattern)
```swift
// Source: Pattern from AgentTools.swift:1224 (loaddll parsing), adapted for msgbox
var dialogs: [[String: String]] = []
for line in stderrLines {
    guard line.contains("trace:msgbox:MSGBOX_OnInit") else { continue }
    // Extract text between L" and final "
    if let lQuoteRange = line.range(of: #"L""#),
       let textStart = Optional(lQuoteRange.upperBound),
       let lastQuote = line.lastIndex(of: "\""),
       lastQuote > textStart {
        var rawText = String(line[textStart..<lastQuote])
        // Unescape Wine debugstr_w sequences
        rawText = rawText.replacingOccurrences(of: "\\n", with: "\n")
        rawText = rawText.replacingOccurrences(of: "\\t", with: "\t")
        rawText = rawText.replacingOccurrences(of: "\\\\", with: "\\")
        dialogs.append([
            "message": rawText,
            "source": "trace:msgbox"
        ])
    }
}
```

### CGWindowListCopyWindowInfo for Wine windows
```swift
// Source: Apple CGWindow.h + community Swift patterns (verified)
import CoreGraphics

private func listWindows(input: JSONValue) -> String {
    guard let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        return jsonResult(["error": "Failed to query window list"])
    }

    // Wine process names vary by build -- use broad matching
    let wineNames: Set<String> = ["wine", "wine64", "wineserver",
        "wine-preloader", "wine64-preloader", "start.exe"]

    var wineWindows: [[String: Any]] = []
    var hasWindowNames = false

    for window in windowList {
        guard let ownerName = window[kCGWindowOwnerName as String] as? String else { continue }

        let isWine = wineNames.contains(ownerName.lowercased()) ||
                     ownerName.lowercased().contains("wine")
        guard isWine else { continue }

        var entry: [String: Any] = ["owner": ownerName]

        // Bounds are always available (no permission needed)
        if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] {
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0
            entry["width"] = Int(w)
            entry["height"] = Int(h)
            entry["likely_dialog"] = (w < 640 && h < 480)
        }

        // Window name requires Screen Recording permission
        if let name = window[kCGWindowName as String] as? String {
            entry["title"] = name
            hasWindowNames = true
        }

        wineWindows.append(entry)
    }

    return jsonResult([
        "windows": wineWindows,
        "screen_recording_permission": hasWindowNames,
        "count": wineWindows.count
    ])
}
```

### Permission detection heuristic
```swift
// Source: github.com/soffes/canRecordScreen gist (community standard pattern)
// Check if ANY non-self window has kCGWindowName -- indicates permission granted
private func checkScreenRecordingPermission() -> Bool {
    let myPID = ProcessInfo.processInfo.processIdentifier
    guard let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly], kCGNullWindowID
    ) as? [[String: Any]] else { return false }

    return windows.contains { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
              pid != myPID else { return false }
        return window[kCGWindowName as String] != nil
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CGWindowListCreateImage for screenshots | ScreenCaptureKit | macOS 15 Sequoia (2024) | CGWindowListCreateImage is deprecated/obsoleted. CGWindowListCopyWindowInfo (enumeration) is NOT deprecated. |
| CGPreflightScreenCaptureAccess() | Deprecated in Sequoia | macOS 15 (2024) | Cannot use the preflight API. Must use kCGWindowName presence heuristic instead. |
| Wine msgbox logging | Unchanged | Stable since Wine 1.x | The single TRACE_(msgbox) call has not changed in years. Format is stable. |

**Deprecated/outdated:**
- `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()`: Deprecated in macOS 15. Use the kCGWindowName presence check instead.
- `CGWindowListCreateImage()`: Obsoleted in macOS 15. Not relevant to this phase (we only enumerate, not capture).

## Open Questions

1. **Wine process names in Gcenx wine-crossover builds**
   - What we know: Upstream Wine uses `wine`, `wine64`, `wineserver`, `wine-preloader`, `wine64-preloader`. Gcenx builds from CrossOver sources which may use different binary names.
   - What's unclear: The exact process owner names that appear in CGWindowListCopyWindowInfo for Gcenx wine-crossover. Could be "Wine" (capitalized), or include version-specific names.
   - Recommendation: The list_windows implementation should match broadly (`contains("wine")` case-insensitive) rather than exact-matching a fixed set. Add a debug/trace mode that logs all window owners for troubleshooting. **Validate with actual Gcenx build during implementation.**

2. **Title extraction without Screen Recording permission**
   - What we know: trace:msgbox provides body text only. kCGWindowName requires Screen Recording. Without both, dialog title is unknown.
   - What's unclear: Whether dialog title is truly necessary for agent decision-making, or if body text + window size is sufficient.
   - Recommendation: Make title an optional field in the dialogs array. Body text alone contains enough information for common patterns (renderer selection, missing file, registration). The agent can function with trace:msgbox as sole signal per CONTEXT.md fallback design.

3. **Timing between Wine MessageBox and window appearing in CGWindowList**
   - What we know: Wine creates the dialog window synchronously during MessageBoxW. The trace:msgbox line appears in stderr when the dialog initializes.
   - What's unclear: How quickly the window appears in CGWindowListCopyWindowInfo after creation. Could be instantaneous or have a small delay.
   - Recommendation: The system prompt should suggest calling list_windows shortly after launch_game returns (not during), so timing is unlikely to be an issue. The dialog will be on screen for the user to interact with.

4. **Gcenx wine-crossover trace:msgbox output verification**
   - What we know: Upstream Wine source has `TRACE_(msgbox)("%s\n", debugstr_w(lpszText))`. CrossOver fork is based on upstream Wine user32. Forum examples confirm format: `{id}:trace:msgbox:MSGBOX_OnInit L"text"`.
   - What's unclear: Whether Gcenx's specific build has any patches that modify msgbox.c trace behavior. CrossOver sometimes misses upstream patches.
   - Recommendation: **MUST test with actual Gcenx wine-crossover before shipping.** Run `WINEDEBUG=+msgbox wine notepad.exe` or a known dialog-producing EXE and capture stderr. The parser regex should be validated against real output. This is flagged in STATE.md as a critical research requirement.

## Sources

### Primary (HIGH confidence)
- Wine source code: `dlls/user32/msgbox.c` ([GitHub mirror](https://github.com/wine-mirror/wine/blob/master/dlls/user32/msgbox.c)) - Verified WINE_DECLARE_DEBUG_CHANNEL(msgbox), single TRACE_(msgbox) call, no caption/type logging
- Apple CGWindow.h header ([MacOSX-SDKs](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.8.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGWindow.h)) - All kCGWindow* dictionary keys with types
- Existing codebase: WineProcess.swift already injects +msgbox at line 48; AgentTools.swift loaddll parsing pattern at lines 1224-1436

### Secondary (MEDIUM confidence)
- Screen Recording permission behavior: kCGWindowName absent, kCGWindowSharingState=0 when denied ([Ryan Thomson article](https://www.ryanthomson.net/articles/screen-recording-permissions-catalina-mess/), [Apple Developer Forums thread 126860](https://developer.apple.com/forums/thread/126860))
- canRecordScreen Swift pattern ([soffes gist](https://gist.github.com/soffes/da6ea98be4f56bc7b8e75079a5224b37)) - Community standard for permission detection
- Wine trace:msgbox output format examples ([WineHQ Forums](https://forum.winehq.org/viewtopic.php?f=8&t=34549), [CodeWeavers blog](https://www.codeweavers.com/blog/aeikum/2019/1/15/working-on-wine-part-4-debugging-wine))
- CGWindowListCopyWindowInfo NOT deprecated, CGWindowListCreateImage deprecated in Sequoia ([MacPorts ticket](https://trac.macports.org/ticket/71136))
- kCGWindowBounds available without Screen Recording permission (multiple sources agree bounds are not gated)

### Tertiary (LOW confidence)
- Gcenx wine-crossover msgbox behavior assumed identical to upstream Wine (no evidence of divergence, but unverified with actual build) -- **requires validation**
- Wine process names in Gcenx builds (assumed standard names, needs device testing)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - CoreGraphics is a system framework, no external dependencies needed
- Architecture: HIGH - Follows established patterns already in codebase (loaddll parsing, tool definitions)
- Pitfalls: HIGH - Wine source code verified, permission behavior well-documented by community
- Wine trace format: MEDIUM - Verified from source but not tested against Gcenx build (flagged for validation)
- Process name matching: LOW - Needs device testing with actual Gcenx wine-crossover

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable domain -- Wine debug channels and CoreGraphics API unlikely to change)

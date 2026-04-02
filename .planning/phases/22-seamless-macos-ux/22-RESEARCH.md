# Phase 22: Seamless macOS UX - Research

**Researched:** 2026-04-01
**Domain:** macOS permission APIs, Swift CLI/Vapor UX, file system cleanup
**Confidence:** HIGH

## Summary

Phase 22 addresses five friction points that block non-technical users from a smooth "open app → game runs" experience. All five requirements map to existing code that needs targeted changes: LaunchCommand, AddCommand/StatusCommand, GameService, and the Vapor web routes. No new SPM dependencies are needed — all required APIs are already in the project or available via system frameworks.

The two hardest problems are the pre-flight permission check (UX-01) and the hardcoded GOG path (UX-04). Permission checking uses macOS-private-but-stable `CGPreflightScreenCaptureAccess()` (CoreGraphics) and `AXIsProcessTrusted()` (ApplicationServices) — both already imported via `CoreGraphics` in `AgentTools.swift`. The GOG path is a one-line fix in `LaunchCommand.swift` already mostly correct: `entry.executablePath` is checked first, the GOG fallback fires only when it's nil and a recipe exists. The fix is to replace the hardcoded GOG directory string with `BottleScanner.findExecutable(named:in:)`.

Game removal (UX-03) needs a new `RemoveCommand` CLI struct plus a `CellarStore.removeGame()` helper. The web delete button already calls `GameService.deleteGame()` but only removes the games.json entry and optionally the bottle — it misses logs, recipes, success records, sessions, diagnostics, and research cache. Both surfaces need a shared `GameRemover` service that deletes all artifacts atomically.

First-run auto-setup (UX-02) requires moving the dependency check + install prompt from `StatusCommand` into `AddCommand` so users don't need to run `cellar status` first. In the web UI, the add-game form should detect Wine is missing before accepting a submission.

Actionable error messages (UX-05) are a quality-pass over all `print("Error:")` sites, adding a "Try this:" line to every one.

**Primary recommendation:** Implement as 3 plans — (1) pre-flight permission check + actionable errors throughout, (2) game removal (CLI + web), (3) first-run auto-setup + GOG path fix.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| UX-01 | Pre-flight check surfaces missing permissions (Screen Recording, Accessibility) with macOS deep links before launch | `CGPreflightScreenCaptureAccess()` in CoreGraphics; `AXIsProcessTrusted()` in ApplicationServices — both system frameworks already in scope. Deep links: `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` and `Privacy_Accessibility` |
| UX-02 | On first `cellar add` or web UI visit with missing dependencies, Cellar detects and offers inline installation with progress | `DependencyChecker().checkAll()` already exists; `GuidedInstaller` already implements install flows. `AddCommand` needs to call the install flow on dep-missing instead of exiting. Web: `LaunchService.resolveWine()` already detects Wine; index route can pre-check and surface a banner |
| UX-03 | `cellar remove <game-id>` deletes bottle, logs, recipes, success records, and registry entry; web UI delete button does the same | New `RemoveCommand` + shared `GameRemover` service. Artifact paths known from `CellarPaths`: `bottleDir`, `logDir`, `userRecipeFile`, `successdbFile`, `sessionFile`, `diagnosticsDir`, `researchCacheFile`, `lutrisCompatCacheDir`, `protondbCompatCacheDir`. `GameService.deleteGame()` already exists but is incomplete |
| UX-04 | LaunchCommand resolves executables from `entry.executablePath` and BottleScanner — hardcoded GOG path is gone | `LaunchCommand.swift` line 43-44: the hardcoded GOG path. Fix: replace with `BottleScanner.scanForExecutables(bottlePath:)` + `findExecutable(named:in:)` when `executablePath` is nil and a recipe exists |
| UX-05 | Every user-facing error message includes a concrete "Try this:" suggestion | Grep identifies ~15 `print("Error:")` sites across `LaunchCommand`, `AddCommand`, `StatusCommand`, `GameController`. Each needs a follow-up `print("Try this: ...")` line |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| CoreGraphics | System | `CGPreflightScreenCaptureAccess()` for Screen Recording permission check | Already imported in `AgentTools.swift` via `import CoreGraphics` |
| ApplicationServices | System | `AXIsProcessTrusted(options:)` for Accessibility permission check | Standard macOS accessibility API, no additional import needed (available in Foundation context) |
| Foundation | System | `FileManager` for artifact deletion, `URL(string:)` for deep links | Already present everywhere |
| ArgumentParser | Package | New `RemoveCommand` struct | Already used for all CLI commands |
| Vapor | Package | Web route adjustments | Already used |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| AppKit (NSWorkspace) | System | `NSWorkspace.shared.open(url:)` to open System Settings deep links from CLI | Only if CLI pre-flight check needs to open browser; standard for deep link opening |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `CGPreflightScreenCaptureAccess()` | `AVCaptureDevice.authorizationStatus(for: .screen)` | AVFoundation works too but CoreGraphics is already imported |
| `NSWorkspace.shared.open()` for deep links | Print URL and tell user to paste it | Printing is simpler for CLI; deep link opening is better UX |

**Installation:** No new SPM packages needed.

## Architecture Patterns

### Recommended Project Structure
```
Sources/cellar/
├── Commands/
│   └── RemoveCommand.swift       # NEW: cellar remove <game-id>
├── Core/
│   ├── GameRemover.swift         # NEW: shared artifact deletion service
│   ├── PermissionChecker.swift   # NEW: Screen Recording + Accessibility check
│   ├── DependencyChecker.swift   # MODIFY: extract install prompt logic
│   └── GuidedInstaller.swift     # UNCHANGED: install logic stays here
├── Web/
│   └── Services/
│       └── GameService.swift     # MODIFY: deleteGame() calls GameRemover
```

### Pattern 1: Pre-flight Permission Check (UX-01)

**What:** Before the agent loop starts (in `AIService.runAgentLoop()` or `LaunchCommand`), check Screen Recording and Accessibility permissions. If any are missing, print the issue with a deep link and ask the user to resolve before proceeding.

**When to use:** Only needed for Screen Recording (used by `list_windows` tool) and optionally Accessibility (used by some DirectInput games). Don't block launch — warn and continue.

**macOS APIs:**
```swift
// Screen Recording permission check (CoreGraphics — no prompt, just check)
// Source: Apple developer documentation CGPreflightScreenCaptureAccess
import CoreGraphics
let hasScreenRecording = CGPreflightScreenCaptureAccess()

// Accessibility permission check (ApplicationServices)
// Source: Apple developer documentation AXIsProcessTrusted
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
let hasAccessibility = AXIsProcessTrustedWithOptions(options)

// Deep links (open System Settings to the exact privacy pane)
let screenLink = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
let accessLink = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
// CLI: NSWorkspace.shared.open(URL(string: screenLink)!)
// Web: render as clickable <a href="..."> in Leaf template
```

**Confidence:** HIGH — `CGPreflightScreenCaptureAccess` is documented and used by screen-capture apps. `AXIsProcessTrusted` is the standard API. Deep link format confirmed working on macOS 12+.

**Pre-flight flow in LaunchCommand:**
```
1. checkPermissions() → [.screenRecording, .accessibility]
2. If missing: print warning with deep link, ask "Grant in System Settings then press Enter to continue"
3. Re-check after user presses Enter — if still missing, warn once more then proceed anyway
4. Don't block launch — permission warnings are advisory, not fatal
```

**Web UI pre-flight:**
- On the game detail / launch page, add a `/games/:gameId/preflight` endpoint that returns a JSON or HTML status
- The launch buttons show a warning banner if permissions are missing (HTMX fetch on page load)
- Each missing permission renders as `<a href="x-apple.systempreferences:...">Open System Settings</a>`

### Pattern 2: Game Removal Service (UX-03)

**What:** A shared `GameRemover` struct that deletes all artifacts for a game ID in one pass.

**Artifacts to delete** (from `CellarPaths`):
```swift
struct GameRemover {
    static func remove(gameId: String) throws {
        // 1. Remove from games.json
        var games = try CellarStore.loadGames()
        games.removeAll { $0.id == gameId }
        try CellarStore.saveGames(games)

        // 2. Delete bottle
        try? FileManager.default.removeItem(at: CellarPaths.bottleDir(for: gameId))

        // 3. Delete logs
        try? FileManager.default.removeItem(at: CellarPaths.logDir(for: gameId))

        // 4. Delete user recipe
        try? FileManager.default.removeItem(at: CellarPaths.userRecipeFile(for: gameId))

        // 5. Delete success record
        try? FileManager.default.removeItem(at: CellarPaths.successdbFile(for: gameId))

        // 6. Delete session handoff
        try? FileManager.default.removeItem(at: CellarPaths.sessionFile(for: gameId))

        // 7. Delete diagnostics
        try? FileManager.default.removeItem(at: CellarPaths.diagnosticsDir(for: gameId))

        // 8. Delete research cache
        try? FileManager.default.removeItem(at: CellarPaths.researchCacheFile(for: gameId))
        // Note: Lutris/ProtonDB caches use the gameId as filename in their subdirs
        try? FileManager.default.removeItem(at: CellarPaths.lutrisCompatCacheDir.appendingPathComponent("\(gameId).json"))
        try? FileManager.default.removeItem(at: CellarPaths.protondbCompatCacheDir.appendingPathComponent("\(gameId).json"))
    }
}
```

**CLI command:**
```swift
struct RemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a game and all its data"
    )
    @Argument var gameId: String
    @Flag(name: .long, help: "Skip confirmation prompt") var yes: Bool = false

    mutating func run() throws {
        guard let entry = try CellarStore.findGame(id: gameId) else {
            print("Error: Game '\(gameId)' not found.")
            print("Try this: Run `cellar list` to see available game IDs.")
            throw ExitCode.failure
        }
        if !yes {
            print("Remove \(entry.name) and all data? [y/n] ", terminator: "")
            fflush(stdout)
            guard readLine()?.lowercased() == "y" else {
                print("Aborted.")
                throw ExitCode.success
            }
        }
        try GameRemover.remove(gameId: gameId)
        print("Removed \(entry.name).")
    }
}
```

**Web delete button** — already triggers `DELETE /games/:gameId` with `cleanBottle=true`. Update `GameService.deleteGame()` to call `GameRemover.remove()` instead of its current partial cleanup.

**Web confirmation** — the existing `hx-confirm` on the delete button already prompts. No change needed there.

### Pattern 3: First-Run Auto-Setup (UX-02)

**What:** `AddCommand` currently exits with "Run `cellar` first to install dependencies." Instead, it should detect missing deps and run the same guided install flow that `StatusCommand` uses.

**Current code (`AddCommand.swift` lines 26-29):**
```swift
let status = DependencyChecker().checkAll()
guard status.allRequired, let wineURL = status.wine else {
    print("Error: Wine is not installed.")
    print("Run `cellar` first to install dependencies.")
    throw ExitCode.failure
}
```

**New flow:**
```swift
var status = DependencyChecker().checkAll()
if !status.allRequired {
    print("Missing dependencies detected. Installing now...")
    let installer = GuidedInstaller()
    if status.homebrew == nil {
        installer.installHomebrew()
        status = DependencyChecker().checkAll()
    }
    if status.homebrew != nil && status.wine == nil {
        installer.installWine()
        status = DependencyChecker().checkAll()
    }
    if status.homebrew != nil && status.wine != nil && status.winetricks == nil {
        installer.installWinetricks()
        status = DependencyChecker().checkAll()
    }
    guard status.allRequired else {
        print("Error: Dependencies still missing after install attempt.")
        print("Try this: Run `cellar status` for step-by-step guidance.")
        throw ExitCode.failure
    }
}
```

**Web UI:** The index page (`GET /`) already calls `LaunchService.resolveWine()` implicitly via `loadGameViewData()`. Add an explicit dep check in `GameController.register` for the index route — if Wine is missing, pass a `missingWine: true` context flag to the template and render a banner:
```html
<div class="alert alert-warning">
  Wine is not installed.
  <a href="/status">View setup guide</a>
</div>
```
Or add a dedicated `GET /status` web route that runs `DependencyChecker` and guides through install with SSE (similar to the install log pattern).

### Pattern 4: Fix Hardcoded GOG Path (UX-04)

**Current code (`LaunchCommand.swift` lines 41-45):**
```swift
if let stored = entry.executablePath {
    executablePath = stored
} else if let recipe = try RecipeEngine.findBundledRecipe(for: game) {
    let gogDir = bottleURL.path + "/drive_c/GOG Games/Cossacks - European Wars"
    executablePath = gogDir + "/" + recipe.executable
```

**Fix:** Replace hardcoded GOG path with BottleScanner:
```swift
} else if let recipe = try RecipeEngine.findBundledRecipe(for: game) {
    let discovered = BottleScanner.scanForExecutables(bottlePath: bottleURL)
    if let found = BottleScanner.findExecutable(named: recipe.executable, in: discovered) {
        executablePath = found.path
    } else {
        // Fallback: first discovered executable
        executablePath = discovered.first?.path
    }
```

This is a surgical fix — 4 lines replaced. No behavior change for Cossacks (BottleScanner will still find the same exe) but now works for any game.

### Pattern 5: Actionable Error Messages (UX-05)

**What:** Every `print("Error:")` or error exit needs a "Try this:" follow-up line.

**Audit of current error sites** (from code review):

| File | Error Message | Try This |
|------|--------------|----------|
| LaunchCommand | "Error: Wine is not installed." | `cellar status` |
| LaunchCommand | "Game not found." | `cellar list` |
| LaunchCommand | "Error: Bottle for '...' not found." | `cellar add <installer>` |
| LaunchCommand | "Error: No executable path stored..." | `cellar add <installer>` to re-scan |
| AddCommand | "Error: Installer not found at ..." | check path with `ls <path>` |
| AddCommand | "Error: winetricks is required..." | `brew install winetricks` |
| AddCommand | "Error: winetricks not found." | `brew install winetricks` |
| RemoveCommand (new) | "Error: Game not found." | `cellar list` |
| GameController (web) | Wine not installed (Abort 503) | Link to `/status` or setup guide |

**Implementation:** Simple — append a `print("Try this: ...")` after each error print. No new infrastructure needed.

### Anti-Patterns to Avoid

- **Blocking launch on permissions:** Permission warnings for Screen Recording and Accessibility should be advisory only — don't prevent the game from launching. The agent already handles the case where Screen Recording is denied gracefully.
- **Duplicate install logic:** Don't copy GuidedInstaller's flow into AddCommand — call it directly.
- **Silent partial deletion:** GameRemover must use `try?` (not `try`) for each artifact — some may not exist. Log what was deleted, don't fail if an artifact is missing.
- **Prompting twice:** The web UI delete button already has `hx-confirm`. Don't add a second server-side confirmation modal — that would break HTMX's expected behavior.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Screen Recording permission check | Custom TCC database query | `CGPreflightScreenCaptureAccess()` | TCC DB requires elevated permissions; official API is safe and stable |
| Accessibility check | Parse `/Library/Application Support/com.apple.TCC/` | `AXIsProcessTrustedWithOptions()` | Standard API, works without root |
| File deletion across multiple paths | Custom recursive delete | `FileManager.default.removeItem(at:)` with `try?` per artifact | Already handles recursive deletion for directories |
| Deep link opening | `Process.launch("open", ...)` | `NSWorkspace.shared.open(URL(string:)!)` | Cleaner, tested macOS pattern |

## Common Pitfalls

### Pitfall 1: `CGPreflightScreenCaptureAccess` vs `CGRequestScreenCaptureAccess`

**What goes wrong:** Using `CGRequestScreenCaptureAccess()` triggers a permission dialog. Using `CGPreflightScreenCaptureAccess()` only checks silently.

**Why it happens:** Two functions with very similar names do different things.

**How to avoid:** Always use `CGPreflightScreenCaptureAccess()` (the Preflight variant) for the check. Only use the Request variant if you want to trigger the system prompt (which we don't — we show our own message with a deep link instead).

**Warning signs:** Users see an unexpected system permission dialog during launch.

### Pitfall 2: Accessibility `kAXTrustedCheckOptionPrompt`

**What goes wrong:** Passing `kAXTrustedCheckOptionPrompt: true` to `AXIsProcessTrustedWithOptions` triggers a system prompt. Passing `false` checks silently.

**How to avoid:** Always pass `false` for the check-only case. The deep link guides the user to System Settings manually.

### Pitfall 3: GameRemover misses lutris/protondb cache filenames

**What goes wrong:** Lutris and ProtonDB caches in `~/.cellar/research/lutris/` and `~/.cellar/research/protondb/` use the game ID as filename — but the exact filename format depends on how `CompatibilityService` saves them.

**How to avoid:** Check `CompatibilityService.swift` for the exact cache file path formula before implementing `GameRemover`. (From CellarPaths: `lutrisCompatCacheDir.appendingPathComponent("\(gameId).json")` — standard pattern.)

**Confidence:** MEDIUM — need to verify CompatibilityService cache path at plan time.

### Pitfall 4: Web delete button confirmation already exists

**What goes wrong:** Adding a second server-rendered confirmation breaks the HTMX delete flow. The `hx-confirm` attribute on the delete button already handles confirmation natively in the browser.

**How to avoid:** Don't add a confirmation page/modal server-side. Keep `hx-confirm` as the sole confirmation mechanism for the web delete.

### Pitfall 5: `AddCommand` install flow blocks the run loop

**What goes wrong:** `GuidedInstaller.installHomebrew()` / `installWine()` use `process.waitUntilExit()` — synchronous, blocking. This is fine for CLI. But if AddCommand ever runs in a web context, it would block the Vapor event loop.

**How to avoid:** The web `POST /games` route does NOT call AddCommand — it redirects to an SSE stream. The install flow in `AddCommand` is CLI-only. No issue.

### Pitfall 6: Registering RemoveCommand

**What goes wrong:** Forgetting to add `RemoveCommand` to the main command group in `Cellar.swift`.

**How to avoid:** `Cellar.swift` likely has a `subcommands` array. Add `RemoveCommand.self` there.

## Code Examples

### Check Screen Recording Permission (Swift/macOS)
```swift
// Source: Apple CGPreflightScreenCaptureAccess documentation (macOS 12.3+)
import CoreGraphics

func checkPermissions() -> (screenRecording: Bool, accessibility: Bool) {
    let screenRecording = CGPreflightScreenCaptureAccess()
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    let accessibility = AXIsProcessTrustedWithOptions(opts)
    return (screenRecording, accessibility)
}

func printPermissionWarning(type: String, deepLink: String) {
    print("Warning: \(type) permission is not granted.")
    print("This may limit game detection capabilities.")
    print("Try this: Open System Settings → Privacy & Security → \(type)")
    print("  Or: open '\(deepLink)'")
}
```

### Open Deep Link (CLI)
```swift
// Source: AppKit NSWorkspace documentation
import AppKit
let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
NSWorkspace.shared.open(url)
```

### Web Deep Link (Leaf template)
```html
<!-- Deep links work directly as <a href> in browser -->
<a href="x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
   class="btn btn-secondary">
  Open Screen Recording Settings
</a>
```

### GameRemover (canonical pattern)
```swift
struct GameRemover {
    static func remove(gameId: String) throws {
        // Step 1: remove from registry (throws on failure — critical)
        var games = try CellarStore.loadGames()
        games.removeAll { $0.id == gameId }
        try CellarStore.saveGames(games)

        // Steps 2-N: remove artifacts (try? — non-fatal if missing)
        let artifacts: [URL] = [
            CellarPaths.bottleDir(for: gameId),
            CellarPaths.logDir(for: gameId),
            CellarPaths.userRecipeFile(for: gameId),
            CellarPaths.successdbFile(for: gameId),
            CellarPaths.sessionFile(for: gameId),
            CellarPaths.diagnosticsDir(for: gameId),
            CellarPaths.researchCacheFile(for: gameId),
            CellarPaths.lutrisCompatCacheDir.appendingPathComponent("\(gameId).json"),
            CellarPaths.protondbCompatCacheDir.appendingPathComponent("\(gameId).json"),
        ]
        for artifact in artifacts {
            try? FileManager.default.removeItem(at: artifact)
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Check permissions mid-launch (after failure) | Pre-flight check before launch starts | Phase 22 | User resolves in one pass instead of multiple failed attempts |
| Hardcoded GOG path | BottleScanner.findExecutable() | Phase 22 | Works for any game, not just Cossacks |
| No game removal | `cellar remove` + full artifact cleanup | Phase 22 | Bottles are 100MB+; no cleanup = disk bloat |
| "Run `cellar` first" gating | Inline install on first `cellar add` | Phase 22 | Eliminates mandatory pre-flight step for new users |

## Open Questions

1. **Does `CGPreflightScreenCaptureAccess` work from a CLI process (no bundle)?**
   - What we know: It's documented as requiring the calling process to have an Info.plist or be sandboxed. CLI tools may always return `false`.
   - What's unclear: Whether Terminal running cellar CLI triggers the check correctly.
   - Recommendation: Test at plan/implementation time. Fallback: detect by actually calling `CGWindowListCopyWindowInfo` and checking if window names are nil (current approach in AgentTools already does this).

2. **Accessibility permission: is it actually needed for any current game?**
   - What we know: The additional context mentions "Accessibility permission may be needed for some games using DirectInput" but there's zero current code that uses Accessibility API.
   - What's unclear: Whether phase 22 should check Accessibility at all, or only Screen Recording.
   - Recommendation: Check Screen Recording only for now. Add Accessibility to the pre-flight if/when a specific tool uses it. Don't check for hypothetical future needs.

3. **`cellar list` command — does it exist?**
   - What we know: REQUIREMENTS.md defers `GAME-04: List games with metadata (cellar list)` to v2. AddCommand's "Try this: Run `cellar list`" would reference a non-existent command.
   - What's unclear: Whether a minimal `cellar list` should be added in Phase 22 or error messages should reference `cellar launch` instead.
   - Recommendation: Reference `cellar launch` (which fails gracefully if ID is wrong) or use the web UI URL in error messages instead of `cellar list`.

4. **CompatibilityService cache filename for gameId**
   - What we know: CellarPaths provides `lutrisCompatCacheDir` and `protondbCompatCacheDir`. The file format likely follows the `"\(gameId).json"` pattern.
   - What's unclear: Whether CompatibilityService uses gameId directly or a transformed slug.
   - Recommendation: Read CompatibilityService.swift at plan time to confirm before writing GameRemover.

## Sources

### Primary (HIGH confidence)
- Codebase direct read — `LaunchCommand.swift`, `AddCommand.swift`, `StatusCommand.swift`, `GameService.swift`, `CellarPaths.swift`, `AgentTools.swift`, `GameController.swift`, `GuidedInstaller.swift`, `SuccessDatabase.swift`
- Apple developer documentation (training knowledge, HIGH for stable APIs): `CGPreflightScreenCaptureAccess`, `AXIsProcessTrustedWithOptions`, `NSWorkspace.shared.open`

### Secondary (MEDIUM confidence)
- macOS deep link format `x-apple.systempreferences:...?Privacy_ScreenCapture` — confirmed working in macOS 12-15 by multiple developer blog posts and Stack Overflow answers, but Apple does not document these URLs officially. They've been stable for 5+ years.

### Tertiary (LOW confidence)
- `CGPreflightScreenCaptureAccess` behavior from CLI process (no bundle) — unverified. May always return false. Fallback strategy documented in Open Questions #1.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs already in project or standard system frameworks
- Architecture: HIGH — patterns derived directly from reading existing code
- Pitfalls: HIGH for #1-#4, MEDIUM for #5-#6 — derived from code structure and macOS platform knowledge

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (macOS APIs stable, no fast-moving dependencies)

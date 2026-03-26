# Stack Research: Cellar

**Domain:** macOS CLI+TUI Wine game launcher with AI-powered recipe system
**Date:** 2026-03-25

## Recommended Stack

### Core Framework

| Component | Choice | Version | Confidence |
|-----------|--------|---------|------------|
| Language | Swift | 6.x | High |
| Interface | CLI + TUI (terminal) | — | High |
| Argument parsing | Swift Argument Parser | 1.x (SPM) | High |
| Persistence | JSON files | — | High |
| Minimum Target | macOS 14 Sonoma | — | Medium |

**Why Swift:** Native macOS, excellent process management via Foundation.Process, strong Codable support for JSON recipes, compiles to a single binary. CLI tools in Swift are well-supported.

**Why CLI+TUI:** Dramatically simpler than SwiftUI. Eliminates Xcode project complexity. CLI commands for scripting (`cellar launch cossacks`), interactive TUI for browsing (lazygit/btop style).

**TUI options:** Swift has limited TUI library options. Candidates:
- Raw ANSI escape codes (no dependency, full control, more work)
- A Swift ncurses wrapper
- Consider if a simpler language (Python with `rich`/`textual`, or Rust with `ratatui`) would be better for TUI specifically

**Why JSON persistence (not SwiftData):** CLI tools don't need a database. JSON files in `~/.cellar/` are inspectable, portable, and version-controllable. SwiftData is overkill and couples to macOS version.

### Runtime Engine

| Component | Choice | Confidence |
|-----------|--------|------------|
| Primary engine | Wine via Gcenx Homebrew tap | High |
| Wine formula | `wine-crossover` from `gcenx/wine` | High |
| Future DX11/12 | GPTK (detect if user has it installed) | Medium |
| DirectDraw shim | cnc-ddraw (bundled in recipes) | Medium |

**Why Gcenx tap:** Official Homebrew `wine-stable` is deprecated (disable date 2026-09-01). Gcenx tap is maintained by the WineHQ macOS package maintainer. `wine-crossover` is built from CrossOver 23.7.1 sources with macOS-specific patches.

**DX translation chain for old games:**
```
Game (DirectDraw/DX8/DX9) → wined3d → OpenGL → macOS OpenGL stack → Metal
```

**Why not GPTK for the wedge:** D3DMetal only handles DX11/DX12. For old DX8/DX9 games like Cossacks, GPTK falls back to the same wined3d/OpenGL path. No benefit for the target wedge.

**D3DMetal cannot be redistributed** (Apple EULA restriction). If Cellar detects GPTK installed on the system, it can use it for DX11+ games — same legal pattern Whisky used.

### Process Management

| Component | Choice | Confidence |
|-----------|--------|------------|
| Wine subprocess | Foundation.Process | High |
| Log capture | Pipe on stdout/stderr | High |
| Process lifecycle | Process.terminationHandler | High |
| Cleanup | wineserver -k per WINEPREFIX on exit | High |

### AI Integration

| Component | Choice | Confidence |
|-----------|--------|------------|
| HTTP client | URLSession | High |
| Primary AI | Anthropic Claude API (Haiku for triage, Sonnet for generation) | Medium |
| Fallback AI | OpenAI API (user-supplied key) | Medium |
| Abstraction | Swift protocol (AIProvider) | High |
| Key storage | macOS Keychain (via `security` CLI) | High |

**User supplies their own API key.** No API costs for the project.

### Recipe Storage

| Component | Choice | Confidence |
|-----------|--------|------------|
| Format | JSON | High |
| Parser | Foundation JSONDecoder/Encoder | High |
| Bundled recipes | In the project repo, installed with the CLI | High |
| User recipes | `~/.cellar/recipes/` | High |
| Community sharing | Git repo PRs | High |

### Package Dependencies (SPM)

| Dependency | Purpose | Confidence |
|------------|---------|------------|
| Swift Argument Parser | CLI command/subcommand parsing | High |
| *TUI library TBD* | Interactive terminal UI | Medium |

**Minimal dependency approach.** Foundation covers HTTP, process management, JSON, and file I/O. Only add what Swift stdlib genuinely can't do.

### Distribution

| Component | Choice | Confidence |
|-----------|--------|------------|
| Primary | Homebrew formula (tap) | High |
| Secondary | GitHub release binary | High |
| Signing | Developer ID + notarization | Medium |

**Why Homebrew formula (not cask):** CLI tools use formulae, not casks. `brew install cellar` or `brew tap cellar/cellar && brew install cellar`.

## What NOT to Use

| Technology | Why Not |
|------------|---------|
| SwiftUI | CLI+TUI instead — dramatically simpler |
| SwiftData / Core Data | JSON files sufficient for CLI persistence |
| Electron / Tauri | Not building a GUI app |
| Bundled Wine | Maintenance trap — use Homebrew Wine |
| GPTK D3DMetal (bundled) | Can't redistribute (Apple EULA). Detect if installed. |
| Alamofire | URLSession sufficient |

## Language Alternative Worth Noting

Swift is a good choice but has weak TUI ecosystem. If TUI quality is a priority:
- **Python** (rich/textual) — fastest TUI development, but distribution is harder
- **Rust** (ratatui) — excellent TUI ecosystem, single binary, but learning curve
- **Go** (bubbletea) — good TUI, easy cross-compile, but less macOS-native feel

Swift was chosen for native Foundation.Process and Codable, but this tradeoff should be revisited if TUI development bogs down.

## Build System

- **Swift Package Manager** for the executable package
- No Xcode project needed — `swift build` from command line
- `Package.swift` as the single build definition

---
*Confidence: High = well-established, Low = needs validation*
*Researched: 2026-03-25*

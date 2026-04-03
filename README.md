# Cellar

**Run old Windows games on your Mac — no manual Wine configuration needed.**

Cellar is a free, open-source macOS command-line tool that uses an AI agent to automatically configure and run old Windows games on Mac (both Apple Silicon and Intel) via Wine. Instead of manually tweaking Wine settings, DLL overrides, and registry entries, Cellar's AI agent researches your game, diagnoses issues, and fixes compatibility problems automatically. It's a Wine configuration automation tool for retro gaming on Mac — an alternative to manual Wine setup, CrossOver, or Game Porting Toolkit for classic PC games.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/lasermaze/Cellar/main/install.sh | bash
```

That's it. One command, no Xcode or Swift toolchain required. The installer downloads a pre-built universal binary, verifies its checksum, and adds it to your PATH.

Then run `cellar` to check dependencies and get started:

```bash
cellar              # Check dependencies, install Wine if needed
cellar add game.iso # Add a game from installer or disc image
cellar launch game  # Launch with AI agent
cellar serve        # Open the web UI
```

Cellar accepts `.exe` installers and `.iso`/`.bin`/`.cue` disc images — it mounts disc images automatically.

## How it works

1. **Add a game** — `cellar add /path/to/setup.exe` (or `.iso`) creates a Wine bottle, runs the installer, discovers executables, and generates a recipe
2. **Launch** — `cellar launch <game>` starts the AI agent, which researches the game, runs diagnostic traces, configures Wine, and launches
3. **It learns** — working configurations are saved locally and can be shared with the community via collective memory

### The AI Agent

When launching a game, Cellar's agent follows a three-phase **Research-Diagnose-Adapt** loop:

- **Research** — queries a local success database, checks collective memory from other users, searches WineHQ/ProtonDB/PCGamingWiki for game-specific compatibility info
- **Diagnose** — runs timed diagnostic Wine launches with debug tracing to see exactly which DLLs load, verifies overrides took effect, checks file access paths
- **Adapt** — applies targeted fixes based on evidence (not guesses), verifies each fix, then launches for real

The agent has 20+ tools including web search, DLL trace analysis, PE import inspection, known DLL downloads (cnc-ddraw, dgVoodoo2, dxwrapper, DXVK), registry editing, and a community success database.

## How Cellar compares

| | Cellar | CrossOver | Whisky | GPTK | Lutris |
|---|---|---|---|---|---|
| **Price** | Free | $74/yr | Free | Free | Free |
| **Platform** | macOS | macOS | macOS | macOS | Linux |
| **Focus** | Old/retro games | Modern + old | Modern games | Modern games | All games |
| **Configuration** | AI-automated | Manual profiles | Manual | Manual | Community scripts |
| **Wine version** | wine-crossover (Gcenx) | Proprietary Wine | Wine upstream | Apple GPTK | System Wine |
| **Disc images** | .iso/.bin/.cue | .exe only | .exe only | N/A | Varies |
| **Open source** | Yes (MIT) | No | Yes | No | Yes |
| **Apple Silicon** | Yes (universal) | Yes | Yes | Yes | N/A |

**When to use Cellar**: You have old PC games (GOG, CD-ROM, abandonware) and want them running on your Mac without learning Wine internals. Cellar is best for pre-2010 games that need specific DLL overrides, registry tweaks, or DirectDraw/Direct3D configuration.

**When to use something else**: For modern AAA games, CrossOver or Whisky with DXVK/MoltenVK is a better fit. For Linux, use Lutris or Proton.

## Requirements

- macOS 14+ (Sonoma or later)
- Apple Silicon or Intel Mac
- An AI API key (Anthropic, Deepseek, or Kimi) for the AI agent — without one, Cellar falls back to recipe-only launches

Cellar automatically detects and installs its runtime dependencies (Homebrew, Wine, winetricks) on first run via `cellar status`.

## Web UI

Run `cellar serve` to open a local web interface for managing your game library, launching games with live agent logs, configuring API keys and model selection, and viewing collective memory stats.

## AI Provider Support

Cellar supports three AI providers — choose based on your preference:

| Provider | Models | Cost |
|---|---|---|
| **Claude** (Anthropic) | Sonnet 4.6, Opus 4.6, Haiku 4.5 | $3-15/MTok |
| **DeepSeek** | V3, R1 | $0.27-2.19/MTok |
| **Kimi** (Moonshot AI) | moonshot-v1 8K/32K/128K | $0.20-5/MTok |

Set your API key via the web UI (`cellar serve` → Settings) or environment variable:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."   # Claude
export DEEPSEEK_API_KEY="sk-..."        # DeepSeek
export KIMI_API_KEY="sk-..."            # Kimi
```

## Common Questions

**Can I run GOG games on Mac?**
Yes. Download the GOG installer (`.exe`) or disc image (`.iso`), then `cellar add /path/to/installer.exe`. Cellar handles Wine configuration automatically.

**Do I need CrossOver?**
No. Cellar is free and uses open-source Wine via Homebrew. CrossOver is a paid product with its own Wine fork — Cellar is a free alternative for retro/classic games.

**Does it work on Apple Silicon (M1/M2/M3/M4)?**
Yes. Cellar ships as a universal binary that runs natively on both Apple Silicon and Intel Macs.

**Is this Game Porting Toolkit?**
No. Apple's Game Porting Toolkit (GPTK) targets modern DirectX 12 games. Cellar targets older games (DirectDraw, Direct3D 7-9, OpenGL) that need specific Wine configuration rather than GPU translation.

**What games work?**
Cellar is best for pre-2010 PC games — strategy games, RPGs, adventure games, and shooters from the Windows 95/98/XP/Vista era. Games that work with Wine generally work with Cellar, but with automatic configuration instead of manual setup.

**Is it safe?**
Cellar runs Wine in isolated per-game bottles (separate Wine prefixes). Each game gets its own sandboxed Windows environment. The AI agent can only modify files within the game's bottle. API keys are stored with restricted file permissions (0600).

**How much does the AI cost per game?**
Typically $0.05-0.50 per game launch with Claude Sonnet. DeepSeek is ~5x cheaper. The default budget ceiling is $15 per session, but most games resolve in 2-3 agent iterations.

## Project Structure

```
Sources/cellar/
  Commands/       — CLI commands (status, add, launch, remove, log, serve, sync)
  Core/           — Business logic (AIService, AgentLoop, AgentTools, WineProcess, DiscImageHandler)
  Core/Tools/     — Agent tool implementations (Research, Diagnostic, Config, Launch, Save)
  Models/         — Data types (GameEntry, Recipe, KnownDLLRegistry, AIModels)
  Persistence/    — Storage (CellarStore, RecipeEngine, CellarPaths, CellarConfig)
  Web/            — Vapor web server (GameController, LaunchController, SettingsController)
```

## Building from Source

If you prefer to build from source instead of using the install script:

```bash
git clone https://github.com/lasermaze/Cellar.git
cd Cellar
swift build -c release
sudo cp .build/release/cellar /usr/local/bin/
```

Requires Xcode 16+ or Swift 6.0+ toolchain.

## License

MIT

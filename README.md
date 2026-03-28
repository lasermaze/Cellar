# Cellar

A macOS CLI tool that makes old Windows games just work — no manual Wine configuration required. Cellar uses an AI agent with a Research-Diagnose-Adapt architecture to automatically figure out what a game needs and configure Wine accordingly.

## What it does

1. **Checks dependencies** — detects Homebrew, Wine (via Gcenx tap), winetricks, and GPTK; guides you through installation if anything is missing
2. **Adds games** — `cellar add /path/to/setup.exe` creates a Wine bottle, runs the installer, discovers executables, and generates a recipe
3. **Launches games** — `cellar launch <game>` applies configuration and launches via Wine with an AI agent that can research, diagnose, and fix issues automatically

## The AI Agent (v2 Architecture)

When launching a game, Cellar's agent follows a three-phase **Research-Diagnose-Adapt** loop:

- **Research** — queries a local success database of previously working configs, then searches the web (WineHQ, ProtonDB, PCGamingWiki) for game-specific compatibility info
- **Diagnose** — runs timed diagnostic Wine launches with debug tracing to see exactly which DLLs load, verifies overrides took effect, checks file access paths
- **Adapt** — applies targeted fixes based on evidence (not guesses), verifies each fix before doing a real launch

The agent has 18 tools including web search, DLL trace analysis, PE import inspection, success database queries, and more.

## Requirements

- macOS 14+ (Sonoma or later)
- Apple Silicon or Intel Mac
- [Homebrew](https://brew.sh)
- An Anthropic API key (for AI features)

## Setup

### 1. Install system dependencies

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Wine via Gcenx tap
brew tap gcenx/wine
brew install --cask wine-crossover

# Install winetricks
brew install winetricks
```

### 2. Build and install Cellar

```bash
git clone https://github.com/lasermaze/Cellar.git
cd Cellar
swift build -c release
sudo cp .build/release/cellar /usr/local/bin/
```

Verify the installation:

```bash
cellar status
```

### 3. Set your API key

The AI agent requires an Anthropic API key. Without one, Cellar falls back to recipe-only launches (no AI diagnosis or research).

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

To persist across sessions, add that line to your shell config (`~/.zshrc` or `~/.bashrc`).

## Usage

### Check system status

```bash
cellar status
```

Shows which dependencies are installed and guides you through setting up anything missing.

### Add a game

```bash
cellar add /path/to/setup_game.exe
```

This will:
- Create a Wine bottle for the game
- Run the installer
- Scan for game executables
- Generate or apply a recipe

### Launch a game

```bash
cellar launch <game-slug>
```

The AI agent takes over: researches the game, runs diagnostics, configures Wine, and launches. If something fails, it diagnoses and adapts rather than blindly retrying.

### View logs

```bash
cellar log <game-slug>
```

Shows the Wine output from the last launch attempt.

## How it works

Cellar manages Wine bottles (isolated Wine prefixes) per game. Each game gets:

- A **bottle** — its own Wine prefix in `~/.cellar/bottles/`
- A **recipe** — configuration (env vars, registry keys, DLL overrides) in `~/.cellar/recipes/`
- A **success record** — comprehensive working config saved in `~/.cellar/successdb/` after a successful launch

The AI agent has domain knowledge about macOS-specific Wine quirks:
- wow64 bottles need system DLLs in `syswow64`, not the game directory
- cnc-ddraw requires `ddraw.ini` with `renderer=opengl` on macOS
- Virtual desktop mode doesn't work with macOS winemac.drv
- Games need their working directory set to the executable's parent folder

## Project structure

```
Sources/cellar/
  CLI/            — Command definitions (StatusCommand, AddCommand, LaunchCommand, etc.)
  Core/           — Business logic (AIService, AgentTools, WineProcess, SuccessDatabase, etc.)
  Models/         — Data types (GameEntry, Recipe, KnownDLLRegistry, etc.)
  Persistence/    — Storage (GameStore, RecipeEngine, CellarPaths)
```

## License

MIT

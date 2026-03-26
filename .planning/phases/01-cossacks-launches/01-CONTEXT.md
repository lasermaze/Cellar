# Phase 1: Cossacks Launches - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Cossacks: European Wars (GOG original edition) launches end-to-end through the full pipeline on a fresh Mac. From `cellar` on a bare system to game running with logs captured and validation prompt shown. No manual Wine configuration required.

Requirements: SETUP-01–05, BOTTLE-01, RECIPE-01–02, LAUNCH-01–03

</domain>

<decisions>
## Implementation Decisions

### CLI Flow Design
- `cellar` with no arguments on a fresh Mac: immediately detect missing deps and walk user through interactive setup
- Two-step game flow: `cellar add /path/to/game` first, then `cellar launch cossacks` by name
- Game name auto-derived from directory name (no `--name` flag needed)
- Output style: informative — a few lines per action explaining what's happening ("Creating bottle... Applying recipe... Launching Wine..."), not minimal and not verbose
- After setup is complete and deps are present, `cellar` shows status + next step: "All dependencies found. Run `cellar add /path/to/game` to get started."

### Guided Install UX
- Auto-run installs: Cellar runs `brew install` etc. directly — user watches progress
- Stream Homebrew's own output in real-time during installation (no spinner/summary)
- Let Homebrew handle Xcode CLT detection and prompts — don't duplicate
- On install failure: show error and offer retry, with manual steps as fallback
- No pre-check for Xcode CLT separately

### Recipe Contents
- Target: GOG original edition of Cossacks: European Wars specifically (one version only)
- Recipe specifies the exact EXE to launch (no scanning/asking)
- Full experience recipe: launch config + display settings (resolution, windowed mode) + audio + performance tweaks + known crash workarounds
- Recipe lives in `recipes/cossacks-european-wars.json` in the project repo root
- Wine settings in recipe use Wine-native formats: registry edits as .reg file content, DLL overrides as Wine env var format
- Full transparency when applying: show each registry key being set, like a diff
- Cellar runs the GOG installer (setup.exe) inside the Wine bottle — user points `cellar add` at the installer, not pre-installed files

### Validation + Logging
- Wine stdout/stderr streams to terminal in real-time while game runs
- Also captured to log file simultaneously: `~/.cellar/logs/{game}/{timestamp}.log`
- Immediate validation prompt when Wine process exits: "Did the game reach the menu? [y/n]"
- Quick-exit detection: if Wine exits in < 2 seconds, flag as likely crash, skip validation prompt, suggest checking logs
- Record just success/failure flag in game metadata (no detailed failure description in v1)
- `cellar log` design: Claude's discretion
- After game exits: ask user "Shut down Wine services? [y/n]"
- Ctrl+C during game: kill Wine process but still ask validation question
- Wineserver cleanup on Ctrl+C: terminate game process only, leave wineserver decision to post-exit prompt

### Claude's Discretion
- `cellar log` command design (list vs show last vs both)
- Exact JSON schema for recipe files (following Wine-native format decision)
- Loading/progress indicators during bottle creation
- Error message wording
- `cellar status` output format
- ~/.cellar/ directory structure details

</decisions>

<specifics>
## Specific Ideas

- The installer flow is important: user has a GOG setup.exe, not pre-installed game files. Cellar should handle running that installer inside the Wine bottle.
- Full transparency on recipe application — user sees every registry key being changed. This builds trust with Wine-naive users who don't know what's happening under the hood.
- Wine output streams live to terminal — noisy but honest. Users can see exactly what Wine is doing.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project

### Established Patterns
- None — first phase establishes all patterns

### Integration Points
- Homebrew CLI (`brew tap`, `brew install`)
- Wine CLI (`wine`, `wineboot`, `wineserver`, `regedit`)
- Gcenx Homebrew tap (`gcenx/wine`)
- macOS Keychain (future, for API keys in Phase 2)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-cossacks-launches*
*Context gathered: 2026-03-26*

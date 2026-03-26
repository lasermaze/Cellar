# Roadmap: Cellar

## Overview

Cellar is built in five vertical slices. Each phase delivers a working capability end-to-end — not a layer of infrastructure. Phase 1 proves the complete pipeline by getting Cossacks: European Wars actually launching through the whole stack (dependency check, bottle creation, hardcoded recipe, launch, log capture, validation prompt). Phase 2 adds AI intelligence to that working loop. Phase 3 adds the self-healing repair loop. Phase 4 generalizes beyond Cossacks to multi-game management. Phase 5 adds community sharing. At every phase boundary, something real works.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Cossacks Launches** - Prove the core pipeline end-to-end: dependency check, bottle creation, hardcoded recipe, launch, log capture, validation prompt
- [ ] **Phase 2: AI Intelligence** - Add AI log interpretation and AI recipe generation to the working launch loop
- [ ] **Phase 3: Repair Loop** - When launch fails, AI diagnoses and retries with variant configs; self-healing pipeline
- [ ] **Phase 4: Multi-Game Management** - Generalize beyond Cossacks; add/remove games, bottle reset, winecfg, full CLI surface
- [ ] **Phase 5: Community** - Export working recipes as shareable JSON files

## Phase Details

### Phase 1: Cossacks Launches
**Goal**: Cossacks: European Wars launches end-to-end through the full pipeline on a fresh Mac, with no manual Wine configuration required
**Depends on**: Nothing (first phase)
**Requirements**: SETUP-01, SETUP-02, SETUP-03, SETUP-04, SETUP-05, BOTTLE-01, RECIPE-01, RECIPE-02, LAUNCH-01, LAUNCH-02, LAUNCH-03
**Success Criteria** (what must be TRUE):
  1. Running `cellar` on a fresh Mac reports the status of Homebrew, Wine (Gcenx tap), and GPTK — missing dependencies are named explicitly
  2. A user without Homebrew or Wine is guided through installation step-by-step and can complete the setup by following the on-screen instructions
  3. Running `cellar launch cossacks` with a valid game path creates an isolated WINEPREFIX for Cossacks automatically and applies the bundled recipe (registry edits, DLL overrides, env vars, launch args)
  4. The game process launches with Wine and its stdout/stderr is written to a per-launch log file
  5. After launch exits, Cellar asks "Did the game reach the menu? (y/n)" and records the response
**Plans:** 4 plans

Plans:
- [ ] 01-01-PLAN.md — Swift package scaffold, models, dependency checker (SETUP-01, SETUP-02, SETUP-05)
- [ ] 01-02-PLAN.md — Guided install UX and StatusCommand wiring (SETUP-03, SETUP-04)
- [ ] 01-03-PLAN.md — Bottle manager, recipe engine, Cossacks recipe (BOTTLE-01, RECIPE-01, RECIPE-02)
- [ ] 01-04-PLAN.md — Add/Launch/Log commands, validation prompt, end-to-end pipeline (LAUNCH-01, LAUNCH-02, LAUNCH-03)

### Phase 2: AI Intelligence
**Goal**: The launch pipeline uses AI to interpret crash logs in plain English and to generate recipes for games that have no bundled recipe
**Depends on**: Phase 1
**Requirements**: RECIPE-03, LAUNCH-04
**Success Criteria** (what must be TRUE):
  1. When a launch fails, Cellar calls an AI API with the captured Wine log and returns a plain-English diagnosis to the user (not raw Wine errors)
  2. When a game has no bundled recipe, Cellar calls an AI API to generate a candidate recipe and applies it automatically before launching
  3. The AI integration is configurable (API key from environment) and fails gracefully with a clear message when unavailable
**Plans**: TBD

### Phase 3: Repair Loop
**Goal**: When a launch fails, Cellar automatically retries with AI-suggested variant configurations before declaring failure
**Depends on**: Phase 2
**Requirements**: RECIPE-04
**Success Criteria** (what must be TRUE):
  1. When a launch fails, Cellar generates at least one alternative recipe variant (via AI or permutation) and retries automatically
  2. The user sees each retry attempt labeled (e.g., "Trying variant 2/3…") so the loop is transparent
  3. After exhausting variants, Cellar reports what was tried and surfaces the best diagnosis before stopping
**Plans**: TBD

### Phase 4: Multi-Game Management
**Goal**: Users can manage any number of games — add, remove, reset bottles, open winecfg — and the full CLI command surface is in place
**Depends on**: Phase 3
**Requirements**: GAME-01, GAME-02, BOTTLE-02, BOTTLE-03, CLI-01
**Success Criteria** (what must be TRUE):
  1. User can run `cellar add /path/to/game` to register a new game in the library (not just Cossacks)
  2. User can run `cellar remove <game>` to delete the library entry and optionally wipe its bottle
  3. User can run `cellar reset <game>` to wipe and recreate a clean WINEPREFIX for any game
  4. User can run `cellar config <game>` to open winecfg scoped to that game's bottle
  5. All documented CLI commands (`add`, `launch`, `remove`, `reset`, `config`, `log`, `status`) are implemented and produce useful output
**Plans**: TBD

### Phase 5: Community
**Goal**: Users can share a working recipe so others with the same game can use it
**Depends on**: Phase 4
**Requirements**: COMM-01
**Success Criteria** (what must be TRUE):
  1. User can run a command that exports the working recipe for a game as a standalone JSON file
  2. The exported file contains all fields needed for another user to import and apply the recipe
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Cossacks Launches | 0/4 | Planning complete | - |
| 2. AI Intelligence | 0/? | Not started | - |
| 3. Repair Loop | 0/? | Not started | - |
| 4. Multi-Game Management | 0/? | Not started | - |
| 5. Community | 0/? | Not started | - |

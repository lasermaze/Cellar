# Roadmap: Cellar

## Milestones

- ✅ **v1.0 Research-Diagnose-Adapt** — Phases 1–7 (shipped 2026-03-28)
- 🚧 **v1.1 Agentic Independence** — Phases 8–11 (in progress)

## Phases

<details>
<summary>✅ v1.0 Research-Diagnose-Adapt (Phases 1–7) — SHIPPED 2026-03-28</summary>

- [x] **Phase 1: Cossacks Launches** — Full pipeline: dependency check, bottle, recipe, launch, log capture, validation prompt (2026-03-27)
- [x] **Phase 1.1: Reactive Dependencies** (INSERTED) — Try-first/install-on-failure deps, winetricks timeout protection (2026-03-27)
- [x] **Phase 2: AI Intelligence** — AI log interpretation and AI recipe generation (2026-03-27)
- [x] **Phase 3: Repair Loop** — AI-driven retry loop with variant configs (2026-03-27)
- [x] **Phase 3.1: Advanced Repair** (INSERTED) — DLL replacements, registry edits, three-tier escalation system (2026-03-27)
- [x] **Phase 6: Agentic Loop** (INSERTED) — 18-tool agent loop replacing hardcoded LaunchCommand pipeline (2026-03-27)
- [x] **Phase 7: Research-Diagnose-Adapt** (INSERTED) — Web search, diagnostic traces, DLL verification, success database (2026-03-28)

</details>

### 🚧 v1.1 Agentic Independence (In Progress)

**Milestone Goal:** Make the agent truly autonomous — it persists through failures, detects dialog blockers, pre-configures games before launch, and extracts actionable fixes from web research.

- [ ] **Phase 8: Loop Resilience** — Fix max_tokens truncation bug, retry on transient errors, budget tracking with ceiling
- [ ] **Phase 9: Engine Detection and Pre-configuration** — Detect game engine from file patterns and PE imports; pre-configure games before first launch to skip known dialogs
- [ ] **Phase 10: Dialog Detection** — Wine trace:msgbox parsing and macOS window list monitoring to detect stuck-on-dialog state
- [ ] **Phase 11: Smarter Research** — Actionable fix extraction from web pages, engine-aware search queries, cross-game success matching

## Phase Details

### Phase 8: Loop Resilience
**Goal**: The agent loop is correct and observable — it handles max_tokens truncation without corrupting state, retries transient failures, and reports session cost against a configurable budget
**Depends on**: Phase 7
**Requirements**: LOOP-01, LOOP-02, LOOP-03, LOOP-04
**Success Criteria** (what must be TRUE):
  1. When the API returns stop_reason="max_tokens" with an incomplete tool_use block, the agent retries with doubled max_tokens and does not append the truncated response to message history — the loop continues correctly
  2. When a 5xx or network error occurs, the agent retries up to 3 times with exponential backoff before surfacing the error; 4xx errors (except 429) abort immediately with a clear message
  3. At the end of an agent session, total token usage and estimated cost are printed; a configurable budget ceiling halts the session with a warning at 80% and stops at 100%
  4. When the API returns an empty end_turn response (no tool calls, no text), the agent sends a continuation prompt instead of silently aborting
**Plans**: TBD

### Phase 9: Engine Detection and Pre-configuration
**Goal**: The agent detects a game's engine and graphics API from files and PE imports, and pre-configures Wine settings before the first launch to eliminate renderer-selection and first-run dialogs for known engines
**Depends on**: Phase 8
**Requirements**: ENGN-01, ENGN-02, ENGN-03, ENGN-04
**Success Criteria** (what must be TRUE):
  1. The inspect_game tool result includes an engine field with detected engine family (GSC/DMCR, Unreal 1, Build, id Tech 2/3, Unity, UE4/5, Westwood, Blizzard), confidence level, detected signals, and a known-config hint
  2. PE import table analysis identifies the primary graphics API (ddraw.dll = DirectDraw, d3d9.dll = DX9, opengl32.dll = OpenGL) and includes it in the inspect_game result
  3. For a recognized engine, the agent writes INI and registry pre-configuration before the first launch attempt — the game directory has the expected ddraw.ini or equivalent without any agent iteration spent diagnosing the dialog
  4. Web search queries constructed after engine detection include engine name and graphics API in addition to game name — search results are visibly more targeted than game-name-only queries
**Plans**: TBD

### Phase 10: Dialog Detection
**Goal**: The agent can detect when a Wine game is stuck on a dialog box — via Wine trace:msgbox parsing as the primary signal and macOS window list inspection as an optional complement — and uses the combined signal to distinguish dialog-stuck from running-normally
**Depends on**: Phase 9
**Requirements**: DIAG-01, DIAG-02, DIAG-03
**Success Criteria** (what must be TRUE):
  1. When a Wine program displays a MessageBox, trace_launch captures the dialog title, message text, and type as structured fields in its result — without requiring any additional permissions
  2. When a Wine game is running, the agent can query the macOS window list to report window titles and sizes for Wine processes; when Screen Recording permission is denied, the tool returns bounds and owner name only (no silent failure or crash)
  3. After a launch_game call, the tool result indicates whether the game appeared stuck on a dialog (hybrid signal: dialog_detected from trace:msgbox and/or small-window heuristic from window list), distinct from a crash or normal exit
**Plans**: TBD

### Phase 11: Smarter Research
**Goal**: The agent extracts specific, actionable fixes from web pages rather than raw text dumps, finds cross-game solutions from the success database using engine and API tags, and uses structured HTML parsing via SwiftSoup
**Depends on**: Phase 10
**Requirements**: RSRCH-01, RSRCH-02, RSRCH-03
**Success Criteria** (what must be TRUE):
  1. fetch_page returns an extracted_fixes field containing specific env vars, registry paths, DLL names, winetricks verbs, and INI changes found on the page — not just raw text; raw text_content is still included as fallback
  2. When query_successdb is called with engine type and graphics API tags, it returns solutions from similar games (not just exact game matches) ranked by signal overlap
  3. fetch_page uses SwiftSoup CSS-selector extraction for known sources (WineHQ AppDB, PCGamingWiki, forums) — code blocks, tables, and list items are parsed structurally rather than stripped as plain text
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 8 → 9 → 10 → 11

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1–7. v1.0 phases | v1.0 | All complete | Complete | 2026-03-28 |
| 8. Loop Resilience | v1.1 | 0/? | Not started | - |
| 9. Engine Detection and Pre-configuration | v1.1 | 0/? | Not started | - |
| 10. Dialog Detection | v1.1 | 0/? | Not started | - |
| 11. Smarter Research | v1.1 | 0/? | Not started | - |

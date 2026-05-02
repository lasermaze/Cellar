---
phase: 41-wiki-as-shared-agent-experience
plan: 02
subsystem: wiki
tags: [wiki, sessions, agent-experience, session-draft-buffer, update_wiki, mid-session-notes]

# Dependency graph
requires:
  - phase: 41-01
    provides: WikiService.postSessionLog, postFailureSessionLog, midSessionNotes parameter
provides:
  - SessionDraftBuffer (in-memory + on-disk crash-recovery draft)
  - CellarPaths.sessionsDraftDir + sessionDraftFile(for:)
  - update_wiki agent tool (tool 23)
  - AgentTools.draftBuffer + sessionShortId
  - midSessionNotes populated from tools.draftBuffer.notes in both session log calls
  - Draft cleared on success; kept on failure for inspection
  - purgeOldDrafts() called at session start (7-day TTL)
  - System prompt teaches update_wiki usage
affects: [agent-loop-prompt, session-log-entries, wiki/sessions/ entries]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SessionDraftBuffer pattern: lazy stored property on AgentTools, initialized with sessionShortId, persists every append atomically"
    - "Draft file format: ISO8601-TAB-content per line, newlines escaped as \\n for single-line integrity"
    - "Draft lifecycle: cleared on success postSessionLog write; kept on failure; purged after 7 days"

key-files:
  created:
    - Sources/cellar/Core/SessionDraftBuffer.swift
  modified:
    - Sources/cellar/Persistence/CellarPaths.swift
    - Sources/cellar/Core/AgentTools.swift
    - Sources/cellar/Core/Tools/ResearchTools.swift
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "SessionDraftBuffer is lazy var on AgentTools (not init) — avoids early filesystem access before session starts"
  - "Both tasks combined into one atomic commit — updateWiki dispatch and implementation are inseparable; build fails if either half is missing"
  - "Failure path keeps draft on disk — operator may want to inspect orphaned notes after failed session"
  - "purgeOldDrafts placed before agentLoop.run (at sessionStartTime) — bounded cost, no orphan accumulation"

# Metrics
duration: 3min
completed: 2026-05-02
---

# Phase 41 Plan 02: Mid-Session update_wiki Tool + SessionDraftBuffer Summary

**update_wiki tool added with crash-safe on-disk buffer; midSessionNotes parameter wired from tools.draftBuffer.notes into both session log call sites**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-05-02T22:59:02Z
- **Completed:** 2026-05-02T23:01:37Z
- **Tasks:** 2
- **Files modified:** 5 (1 created, 4 modified)

## Accomplishments

- New `SessionDraftBuffer` class: in-memory `notes` array + on-disk crash-recovery draft at `~/.cellar/cache/sessions/{shortId}.draft.md`; tab-delimited format with newline escaping; `clearDraft()` on success; `purgeOldDrafts()` for 7-day cleanup
- `CellarPaths` gains `sessionsDraftDir` and `sessionDraftFile(for:)` helpers
- `AgentTools` gets `sessionShortId` (UUID-derived 8-char hex, stable per instance) and `lazy var draftBuffer: SessionDraftBuffer`; `update_wiki` registered as tool 23 with dispatch case
- `ResearchTools.updateWiki()`: validates `content` present, non-empty, ≤1000 chars; appends to `draftBuffer`; returns JSON confirmation with `total_notes`
- `AIService`: `midSessionNotes: []` placeholders replaced with `tools.draftBuffer.notes` in success and failure `postSessionLog` calls; `clearDraft()` called after successful write; `SessionDraftBuffer.purgeOldDrafts()` at session start; system prompt extended with `update_wiki` guidance paragraph

## Task Commits

1. **Tasks 1+2: All changes (combined — dispatch and implementation are inseparable)** - `7d0b46f` (feat)

## Files Created/Modified

- `Sources/cellar/Core/SessionDraftBuffer.swift` — new file: `SessionDraftBuffer` class with `append(content:)`, `clearDraft()`, `purgeOldDrafts(maxAge:)`, tab-delimited persist/readDraft helpers
- `Sources/cellar/Persistence/CellarPaths.swift` — added `sessionsDraftDir` (computed var, `~/.cellar/cache/sessions/`) and `sessionDraftFile(for:)` (lines 141–148)
- `Sources/cellar/Core/AgentTools.swift` — added `sessionShortId` + `lazy var draftBuffer` to mutable state block; added tool 23 `update_wiki` definition; added `case "update_wiki"` dispatch
- `Sources/cellar/Core/Tools/ResearchTools.swift` — added `updateWiki(input:)` implementation (lines 225–247)
- `Sources/cellar/Core/AIService.swift` — replaced `midSessionNotes: []` with `tools.draftBuffer.notes` in both call sites; added `tools.draftBuffer.clearDraft()` after success write; added `SessionDraftBuffer.purgeOldDrafts()` at session start; appended `update_wiki` paragraph to system prompt

## Decisions Made

- Combined both tasks into one atomic commit — the dispatch in AgentTools and the implementation in ResearchTools are inseparable; intermediate build state would fail
- `lazy var draftBuffer` (not init-time) — avoids filesystem directory creation before the agent loop actually starts
- Draft file location `~/.cellar/cache/sessions/` (not `~/.cellar/sessions/`) — `sessions/` is already used by `SessionHandoff` files; `cache/sessions/` is the draft scratch area

## Deviations from Plan

**1. [Rule 1 - Structural] Combined tasks into single commit**
- **Found during:** Task 1 intermediate build check
- **Issue:** AgentTools.swift dispatches `updateWiki` (Task 1) but the function is defined in ResearchTools.swift (Task 2) — build fails with "cannot find 'updateWiki' in scope" between tasks
- **Fix:** Executed both tasks before committing; single atomic commit covers all 5 files
- **Behavioral change:** None — same code, same result

## Issues Encountered

None beyond the expected cross-file build dependency requiring the combined commit.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 41 complete: both P01 (session log writes) and P02 (mid-session update_wiki tool) are shipped
- Agents can now call `update_wiki(content: "...")` at any point during a session
- On-disk draft at `~/.cellar/cache/sessions/{shortId}.draft.md` survives crashes
- Session log entries will include `## Mid-session observations` block when notes are present
- E2E verification: run a game session, call update_wiki during the session, confirm the observation appears in the resulting `wiki/sessions/{date}-{slug}-{id}.md` entry

---
*Phase: 41-wiki-as-shared-agent-experience*
*Completed: 2026-05-02*

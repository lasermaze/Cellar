---
phase: 42-unify-agent-loop-with-single-model-catalog-and-typed-tool-boundary
plan: "03"
subsystem: core/agent-tools
tags: [typed-enum, tool-dispatch, refactor, agent-tools]
dependency_graph:
  requires:
    - phase: 42-01
      provides: "ModelCatalog infrastructure (not directly used by this plan)"
    - phase: 42-02
      provides: "AgentProvider concrete struct (provides tool-dispatch context)"
  provides:
    - "AgentToolName enum — 24 string-backed cases, one per agent tool"
    - "ToolMetadata struct — description, inputSchema, pendingAction closure per tool"
    - "AgentToolName.definition — derived ToolDefinition accessor"
    - "AgentToolName.pendingActionDescription(for:) — replaces switch-based pending-action tracking"
    - "AgentTools.toolDefinitions derived from AgentToolName.allCases — no hand-authored array"
  affects: [Phase-43-tool-schemas-to-resources, Phase-45-agenttools-split]
tech_stack:
  added: []
  patterns:
    - "typed-enum-dispatch: AgentToolName(rawValue: wireName) replaces switch toolName: String"
    - "static-dictionary-metadata: [AgentToolName: ToolMetadata] co-locates description/schema/pendingAction per tool"
    - "derived-collection: AgentToolName.allCases.map defines toolDefinitions — no drift possible"
    - "closure-per-tool-pending-action: ((JSONValue) -> String?)? captures input formatting without separate switch"
key_files:
  created:
    - Sources/cellar/Core/AgentToolName.swift
  modified:
    - Sources/cellar/Core/AgentTools.swift
key_decisions:
  - "ToolMetadata uses @unchecked Sendable + @Sendable closure — Swift 6 concurrency-safe static table"
  - "DEBUG assertMetadataComplete() static method (not a stored let) — avoids private-access-from-outside-extension error"
  - "resolvedTool computed once before userForceConfirmed guard — typed comparison replaces raw string != checks"
  - "trackPendingAction private method deleted entirely — replaced by tool.pendingActionDescription(for: input)"
  - "AgentToolName case names: lowerCamelCase matching Swift convention; raw values match wire strings exactly"
patterns-established:
  - "AgentToolName enum + metadata table: the single source of truth for tool identity — extend here to add tools"
  - "pendingActionDescription closure pattern: ((JSONValue) -> String?)? avoids a separate tracking switch"
requirements-completed: []
duration: ~6min
completed: "2026-05-03"
---

# Phase 42 Plan 03: Typed Tool Boundary — AgentToolName Enum Replaces String Switches

**24-case `AgentToolName` enum with static metadata table replaces two `switch toolName: String` blocks and a 510-line hand-authored `toolDefinitions` array in AgentTools.swift — compiler now enforces dispatch completeness.**

## Performance

- **Duration:** ~6 min (344 seconds)
- **Started:** 2026-05-03T21:45:52Z
- **Completed:** 2026-05-03T21:51:36Z
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- Created `AgentToolName.swift` (611 lines): 24-case string-backed enum, `ToolMetadata` struct, static metadata table with one entry per tool, `definition` and `pendingActionDescription(for:)` accessors, `DEBUG assertMetadataComplete()` method
- Deleted 510-line hand-authored `toolDefinitions: [ToolDefinition]` array from AgentTools.swift; replaced by `static var toolDefinitions: [ToolDefinition] { AgentToolName.allCases.map { $0.definition } }`
- Replaced `switch toolName: String` dispatch (24 cases + default) with `guard let tool = AgentToolName(rawValue: toolName)` + exhaustive `switch tool: AgentToolName` — typo-class bugs impossible
- Deleted `trackPendingAction(toolName: String, input: JSONValue)` 20-line private method; replaced by single `tool.pendingActionDescription(for: input)` call
- AgentTools.swift: 746 → 225 lines (-521 lines)
- All 5 Tools/*.swift files untouched (Phase 31 carry-forward preserved)

## Final Case Count

| Metric | Count |
|--------|-------|
| AgentToolName cases | 24 |
| Tools with non-nil `pendingAction` closure | 5 |
| Tools with nil `pendingAction` | 19 |

**Tools with non-nil pendingAction (require input formatting):**
1. `set_environment` — formats `key=value` from input fields
2. `set_registry` — formats `key_path, value_name` from input fields
3. `install_winetricks` — formats `verb` from input field
4. `place_dll` — formats `dll_name` from input field
5. `write_game_file` — formats `relative_path` from input field

None of the 5 closures required particularly complex input parsing — all use simple `input["field"]?.asString` extraction, same as the original switch body. No non-trivial JSON navigation required.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create AgentToolName enum with full metadata table** - `c8632e3` (feat)
2. **Task 2: Replace dispatch + pending-action + toolDefinitions with enum-driven equivalents** - `4cd042f` (feat)

**Plan metadata:** _(final commit — this summary)_

## AgentTools.swift Line Count Delta

| Metric | Before | After |
|--------|--------|-------|
| Total lines | 746 | 225 |
| Hand-authored ToolDefinition array | ~510 lines | 0 (deleted) |
| toolDefinitions property | static let + 510-line array body | 3-line computed var |
| execute() dispatch switch | 28 lines (24 cases + default + overhead) | 26 lines (typed switch, cleaner) |
| trackPendingAction method | 20 lines | 0 (deleted) |
| Pending-action call site | 1 line (call to method) | 1 line (call to enum method) |

The net -521 is entirely the deleted hand-authored array. The dispatch logic itself is essentially the same length in both forms.

## Debug Assertion Behavior

The `DEBUG assertMetadataComplete()` static method iterates all 24 cases and asserts each has a metadata entry. It was not needed during this execution (the table was built correctly from the start), but the assertion will be useful if a future developer adds a new enum case without adding a metadata entry — the assert fires immediately rather than silently crashing at `metadata[self]!`.

The assertion is a static method (not a stored `private let`) because Swift's `private` protection level prevents access to `private` members from outside the `extension AgentToolName` scope — even from a file-scope stored property in the same file.

## Files Created/Modified

- `/Users/peter/Documents/Cellar/Sources/cellar/Core/AgentToolName.swift` (created — 611 lines)
  - `enum AgentToolName: String, CaseIterable` with 24 cases
  - `private struct ToolMetadata: @unchecked Sendable` with description, inputSchema, pendingAction
  - `private static let metadata: [AgentToolName: ToolMetadata]` — one entry per case
  - `var definition: ToolDefinition` — builds from metadata
  - `func pendingActionDescription(for input: JSONValue) -> String?` — calls closure or returns nil
  - `#if DEBUG static func assertMetadataComplete()` — completeness guard
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/AgentTools.swift` (modified — 746 → 225 lines)
  - `static let toolDefinitions` array deleted; replaced by `static var { AgentToolName.allCases.map }`
  - `switch toolName: String` dispatch deleted; replaced by typed `switch tool: AgentToolName`
  - `trackPendingAction` method deleted; replaced by `tool.pendingActionDescription(for: input)`
  - `userForceConfirmed` guard now uses `resolvedTool != .saveSuccess && != .saveRecipe`

## Decisions Made

- `ToolMetadata: @unchecked Sendable` with `@Sendable` closure — required for Swift 6 static stored property in a non-isolated context. The closure captures no mutable state, so `@unchecked` is safe.
- `assertMetadataComplete()` as a static method rather than a file-scope stored `let` — `private` members of an extension are inaccessible from outside that extension's scope, even in the same file.
- `resolvedTool` computed once before the `userForceConfirmed` guard, then reused in the `guard let tool = resolvedTool` below — avoids double `rawValue` lookup and keeps the guard readable.
- Kept `trackPendingAction` deletion inside Task 2 commit (same commit as dispatch replacement) — the two are semantically one unit; having a `trackPendingAction` with a string switch while the dispatch uses a typed switch would be inconsistent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ToolMetadata Sendable conformance for static stored property**
- **Found during:** Task 1 (build verification)
- **Issue:** `static let metadata: [AgentToolName: ToolMetadata]` caused Swift 6 concurrency error: non-`Sendable` type in shared mutable state
- **Fix:** Added `@unchecked Sendable` to `ToolMetadata` struct and `@Sendable` to the closure field type
- **Files modified:** `Sources/cellar/Core/AgentToolName.swift`
- **Committed in:** `c8632e3` (Task 1 commit)

**2. [Rule 1 - Bug] DEBUG assertion private-access error**
- **Found during:** Task 1 (build verification)
- **Issue:** File-scope stored `private let _check: Void = { AgentToolName.metadata... }()` couldn't access `private` member from outside the extension's scope
- **Fix:** Converted to `static func assertMetadataComplete()` inside the extension — private access works correctly within the extension scope
- **Files modified:** `Sources/cellar/Core/AgentToolName.swift`
- **Committed in:** `c8632e3` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs from Swift 6 access/concurrency constraints)
**Impact on plan:** Both fixes were compile errors requiring immediate resolution. No scope creep — both corrections are contained in AgentToolName.swift and do not change the design.

## Issues Encountered

Two build errors on first Task 1 attempt (documented in deviations above). Both resolved in the same build cycle before committing.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 42 complete. All three plans shipped:
  - P01: ModelCatalog — single source of truth for model identity/pricing
  - P02: AgentProvider — concrete struct, three adapters, AgentLoopProvider deleted
  - P03: AgentToolName — typed dispatch, derived toolDefinitions, pending-action via closures
- Phase 43 (extract agent policy data to versioned Resources/) can proceed immediately
  - AgentToolName metadata table is the extraction target for tool schemas in Phase 43
  - Tool schemas are now co-located in one place (AgentToolName.metadata) rather than scattered across 510 lines
- Phase 45 (split AgentTools into session/runtime actor) has a cleaner starting point:
  - AgentTools.swift is now 225 lines (was 746) — less to decompose

---

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| Sources/cellar/Core/AgentToolName.swift exists | FOUND |
| Sources/cellar/Core/AgentTools.swift exists | FOUND |
| Tools/*.swift unchanged | CONFIRMED |
| AgentToolName has 24 cases | CONFIRMED |
| Commit c8632e3 (Task 1) exists | FOUND |
| Commit 4cd042f (Task 2) exists | FOUND |
| swift build succeeds | PASSED |
| Zero switch toolName: String blocks in AgentTools.swift | CONFIRMED |
| Hand-authored toolDefinitions array deleted | CONFIRMED |
| trackPendingAction method deleted | CONFIRMED |

---
*Phase: 42-unify-agent-loop-with-single-model-catalog-and-typed-tool-boundary*
*Completed: 2026-05-03*

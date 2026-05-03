---
phase: 43-extract-agent-policy-data-to-versioned-resources-and-achieve-provider-parity-for-tool-use-across-anthropic-deepseek-and-kimi
plan: 03
subsystem: api
tags: [swift, agentloop, tool-calling, anthropic, deepseek, kimi, openai-compat, codable, sendable]

requires:
  - phase: 43-01
    provides: PolicyResources bundle loader and typed resource access
  - phase: 42-03
    provides: AgentToolName enum and typed tool dispatch

provides:
  - AgentToolCall struct {id, name, input} with Sendable + Equatable conformance
  - AgentLoopProviderResponse.toolCalls typed as [AgentToolCall] (was anonymous tuple)
  - AnthropicAdapter, DeepseekAdapter, KimiAdapter all decode/encode via AgentToolCall
  - Round-trip unit tests for all three adapters (9 tests, 3 per provider)
  - JSONValue gains Sendable conformance

affects:
  - 44-collapse-memory-layer (AgentLoop/AgentTools see canonical tool shape)
  - 45-split-agenttools (SessionContext and RuntimeActor consume AgentToolCall)

tech-stack:
  added: []
  patterns:
    - "Adapter testability: internal translateResponse/encodedAssistantBlocks helpers avoid HTTP in unit tests"
    - "Struct replaces named tuple: AgentToolCall has explicit Sendable+Equatable, shareable across actor boundaries"

key-files:
  created:
    - Sources/cellar/Models/AgentToolCall.swift
    - Tests/cellarTests/Providers/AnthropicAdapterTests.swift
    - Tests/cellarTests/Providers/DeepseekAdapterTests.swift
    - Tests/cellarTests/Providers/KimiAdapterTests.swift
  modified:
    - Sources/cellar/Core/AgentProvider.swift
    - Sources/cellar/Core/Providers/AnthropicAdapter.swift
    - Sources/cellar/Core/Providers/DeepseekAdapter.swift
    - Sources/cellar/Core/Providers/KimiAdapter.swift
    - Sources/cellar/Models/AIModels.swift

key-decisions:
  - "JSONValue gains Sendable: required by AgentToolCall.input field; all JSONValue cases contain value types so conformance is safe"
  - "Internal testable helpers (translateResponse/encodedAssistantBlocks) keep private implementation hidden while enabling deterministic unit tests"
  - "AgentLoop and AgentTools required zero changes: struct property access is syntactically identical to named-tuple label access in Swift"

patterns-established:
  - "Canonical tool call shape: all provider-specific wire details stay inside adapters; AgentLoop sees only AgentToolCall"
  - "Adapter unit test pattern: construct parsed response structs directly (no HTTP); call internal translateResponse helper; assert equality"

requirements-completed: [TUP-01, TUP-02, TUP-03, TUP-04, TUP-05]

duration: 5min
completed: 2026-05-03
---

# Phase 43 Plan 03: Provider Parity — AgentToolCall Struct Summary

**AgentToolCall struct replaces anonymous tuple in all three adapters; 9 new round-trip tests verify encode/decode parity across Anthropic, DeepSeek, and Kimi**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-03T22:45:42Z
- **Completed:** 2026-05-03T22:50:42Z
- **Tasks:** 2
- **Files modified:** 8 (6 source + 3 test created, 1 existing model updated)

## Accomplishments

- Created `AgentToolCall` struct with `Sendable` and `Equatable` conformance — canonical tool invocation shape for all providers
- Replaced `[(id: String, name: String, input: JSONValue)]` anonymous tuple with `[AgentToolCall]` in `AgentLoopProviderResponse`
- Updated all three adapters (`AnthropicAdapter`, `DeepseekAdapter`, `KimiAdapter`) to construct `AgentToolCall` values instead of tuples
- Added `Sendable` to `JSONValue` (required for the new struct's stored property; safe because all JSONValue cases hold value types)
- Added 9 unit tests across three files covering: response decode, assistant-turn encode, and full round-trip for each provider
- `AgentLoop.swift` and `AgentTools.swift` required zero changes — Swift struct property access is syntactically identical to named-tuple label access

## LOC Delta

| File | Before | After | Delta |
|------|--------|-------|-------|
| AnthropicAdapter.swift | 146 | 163 | +17 (testable helpers) |
| DeepseekAdapter.swift | 207 | 228 | +21 (testable helpers) |
| KimiAdapter.swift | 204 | 225 | +21 (testable helpers) |
| AgentToolCall.swift | — | 12 | +12 (new) |
| AIModels.swift | n/a | n/a | +1 (Sendable on JSONValue) |
| AnthropicAdapterTests.swift | — | 113 | +113 (new) |
| DeepseekAdapterTests.swift | — | 131 | +131 (new) |
| KimiAdapterTests.swift | — | 131 | +131 (new) |

## Task Commits

Each task was committed atomically:

1. **Task 1: Introduce AgentToolCall + retype response + update adapters** - `6585367` (refactor)
2. **Task 2: Adapter round-trip tests** - `b666fc2` (test)

## Files Created/Modified

- `Sources/cellar/Models/AgentToolCall.swift` — new canonical struct; Sendable + Equatable
- `Sources/cellar/Core/AgentProvider.swift` — `toolCalls` retyped from tuple to `[AgentToolCall]`
- `Sources/cellar/Core/Providers/AnthropicAdapter.swift` — builds `AgentToolCall` from `tool_use` blocks; internal test helpers
- `Sources/cellar/Core/Providers/DeepseekAdapter.swift` — builds `AgentToolCall` from OpenAI `tool_calls`; internal test helpers
- `Sources/cellar/Core/Providers/KimiAdapter.swift` — same as DeepSeek (OpenAI-compat wire)
- `Sources/cellar/Models/AIModels.swift` — `JSONValue` gains `Sendable` conformance
- `Tests/cellarTests/Providers/AnthropicAdapterTests.swift` — 3 tests: decode/encode/round-trip
- `Tests/cellarTests/Providers/DeepseekAdapterTests.swift` — 3 tests: decode/encode/round-trip
- `Tests/cellarTests/Providers/KimiAdapterTests.swift` — 3 tests: decode/encode/round-trip

## Decisions Made

- **JSONValue gains Sendable**: Required for `AgentToolCall.input` because `AgentToolCall` is `Sendable`. All JSONValue cases hold value types (String, Double, Bool, recursive self) so the conformance is unconditionally safe. Added as a one-line change to the existing declaration in AIModels.swift.
- **Internal testable helpers instead of exposing private state**: Each adapter's `translateXxxResponse` method was `private`. Rather than promoting the private method or exposing the internal messages array, added small `internal` wrapper helpers (`translateResponse`, `encodedAssistantBlocks`, `encodedAssistantToolCalls`) that tests call directly. This keeps implementation private while enabling deterministic unit tests.
- **AgentLoop and AgentTools unchanged**: Swift named-tuple label access (`call.id`) and struct property access (`call.id`) are syntactically identical. The two files compiled without modification, confirming the type change was backward-compatible at the call site.

## Pre-existing JSON-in-text Fallback

No JSON-in-text fallback existed for tool calls in DeepSeek or Kimi adapters. Both adapters already used native `tool_calls` array decoding in their `translateXxxResponse` methods. Nothing was deleted.

## Fixture Set (Round-trip Tests)

All three adapter test files use the same canonical fixtures:

```swift
AgentToolCall(id: "call_1", name: "inspect_game", input: .object([:])),           // empty object
AgentToolCall(id: "call_2", name: "set_environment", input: .object([             // flat key-value
    "key": .string("WINEDLLOVERRIDES"), "value": .string("ddraw=n,b")
])),
AgentToolCall(id: "call_3", name: "search_web", input: .object([                  // nested array
    "query": .string("starcraft wine"),
    "tags": .array([.string("rts"), .string("blizzard")])
])),
```

Covers: empty object, flat key-value object, and nested array — the three structural cases most likely to expose encoding bugs.

## Provider Quirks Discovered

- **No quirks found**: Kimi's `tool_call_id` format is identical to DeepSeek's (both OpenAI-compat). No differences in wire format, ID format, or `finishReason` values were observed at the test layer.
- The pre-existing `CellarConfig Kimi model` test failure (`moonshot-v1-8k` vs `moonshot-v1-128k`) is unrelated and predates this plan.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added Sendable to JSONValue**
- **Found during:** Task 1 (build after introducing AgentToolCall)
- **Issue:** `AgentToolCall` declares `Sendable` conformance; its `input: JSONValue` field caused a compile error because `JSONValue` was not `Sendable`
- **Fix:** Added `Sendable` to JSONValue's protocol list in AIModels.swift — one-word change
- **Files modified:** `Sources/cellar/Models/AIModels.swift`
- **Verification:** `swift build` green after change
- **Committed in:** `6585367` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 — missing protocol conformance)
**Impact on plan:** Essential for Swift 6 actor-boundary safety. No scope creep.

## Issues Encountered

None beyond the Sendable deviation above.

## Next Phase Readiness

- Phase 43 is now fully complete (P01 + P02 + P03). All five TUP requirements closed.
- Phase 44 (KnowledgeStore) and Phase 45 (AgentTools split) can proceed; both will consume `AgentToolCall` via `AgentLoop.toolCalls` without seeing wire-protocol details.

---
*Phase: 43-extract-agent-policy-data*
*Completed: 2026-05-03*

## Self-Check: PASSED

- FOUND: Sources/cellar/Models/AgentToolCall.swift
- FOUND: Tests/cellarTests/Providers/AnthropicAdapterTests.swift
- FOUND: Tests/cellarTests/Providers/DeepseekAdapterTests.swift
- FOUND: Tests/cellarTests/Providers/KimiAdapterTests.swift
- FOUND: commit 6585367 (Task 1)
- FOUND: commit b666fc2 (Task 2)

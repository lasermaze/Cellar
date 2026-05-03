---
phase: 42-unify-agent-loop-with-single-model-catalog-and-typed-tool-boundary
plan: "02"
subsystem: core/agent-loop
tags: [agent-loop, provider-abstraction, refactor, adapters]
dependency_graph:
  requires:
    - phase: 42-01
      provides: "ModelCatalog, ModelDescriptor, ModelProvider enum used by AgentProvider.init dispatch"
  provides:
    - "AgentProvider concrete struct — the only provider type AgentLoop sees"
    - "ProviderAdapter internal protocol — class-bound, three implementations"
    - "AnthropicAdapter, DeepseekAdapter, KimiAdapter — wire-protocol isolation"
    - "AgentLoopProviderResponse moved to AgentProvider.swift"
    - "agentCallAPI helper moved to AgentProvider.swift"
  affects: [AIService, AgentLoop, Phase-43-adapters]
tech_stack:
  added: []
  patterns:
    - "concrete-struct-with-class-backed-adapter: AgentProvider holds any ProviderAdapter (AnyObject-constrained)"
    - "non-mutating delegation: adapter is a class reference — struct methods are non-mutating, no copy-on-mutation issue"
    - "dispatch-at-init: descriptor.provider switch in AgentProvider.init selects adapter once at construction"
key_files:
  created:
    - Sources/cellar/Core/AgentProvider.swift
    - Sources/cellar/Core/Providers/AnthropicAdapter.swift
    - Sources/cellar/Core/Providers/DeepseekAdapter.swift
    - Sources/cellar/Core/Providers/KimiAdapter.swift
  modified:
    - Sources/cellar/Core/AgentLoop.swift
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Core/ModelCatalog.swift
  deleted:
    - Sources/cellar/Core/AgentLoopProvider.swift
key_decisions:
  - "AgentProvider methods are non-mutating — class-bound adapter (AnyObject) means the struct holds a constant reference; adapter state mutates internally. No mutating keyword needed."
  - "No shared OpenAICompatHelpers.swift created — Deepseek and Kimi adapters are 60 lines of wire-protocol code each; duplication not yet loud enough to warrant extraction."
  - "AgentLoopProviderResponse type kept (not renamed) — type is part of the stable contract used across AgentLoop, adapters, and middleware. Renaming would be cosmetic churn."
  - "agentCallAPI top-level function retained as module-level helper in AgentProvider.swift — used by all three adapters, not adapter-specific."
requirements-completed: []
duration: 4min
completed: "2026-05-03"
---

# Phase 42 Plan 02: AgentProvider Struct + Three Adapters — Delete AgentLoopProvider

**623-line AgentLoopProvider.swift (protocol + 3 struct implementations) replaced by concrete AgentProvider struct holding a class-backed ProviderAdapter, with three explicit adapter classes owning per-provider wire-protocol quirks.**

## Performance

- **Duration:** ~4 min (211 seconds)
- **Started:** 2026-05-03T22:19:25Z
- **Completed:** 2026-05-03T22:23:05Z
- **Tasks:** 2
- **Files modified:** 7 (4 created, 3 modified, 1 deleted)

## Accomplishments

- Replaced 623-line `AgentLoopProvider.swift` (protocol + 3 struct implementations) with 4 focused files totaling ~620 lines: `AgentProvider.swift` (108 lines) + 3 adapters (~170 lines each)
- `AgentLoop.provider` retyped from `any AgentLoopProvider` to concrete `AgentProvider` — no protocol dispatch at the loop boundary
- `AIService.runAgentLoop` three-way provider switch collapsed to single `AgentProvider(descriptor:apiKey:tools:systemPrompt:)` construction
- `AgentLoopProvider` protocol and `AnthropicAgentProvider`/`DeepseekAgentProvider`/`KimiAgentProvider` structs fully deleted with zero remaining references

## Task Commits

Each task was committed atomically:

1. **Task 1: Create AgentProvider + ProviderAdapter + three adapter classes** - `0c82ac0` (feat)
2. **Task 2: Switch AgentLoop + AIService to AgentProvider; delete AgentLoopProvider.swift** - `60c1160` (feat)

**Plan metadata:** _(final commit — this summary)_

## Final Type Names

| New Type | Role |
|----------|------|
| `AgentProvider` | Concrete struct — the single type `AgentLoop.provider` holds |
| `ProviderAdapter` | Internal protocol (AnyObject-constrained) — not visible outside Core/ |
| `AnthropicAdapter` | Anthropic Messages API encoding/decoding, message state |
| `DeepseekAdapter` | OpenAI-compat + reasoning_content strip, message state |
| `KimiAdapter` | OpenAI-compat with Kimi base URL, message state |
| `AgentLoopProviderResponse` | Kept — moved from deleted file into AgentProvider.swift |

## AgentProvider Method Mutability

`AgentProvider`'s delegating methods (`appendUserMessage`, `appendAssistantResponse`, `appendToolResults`, `callWithRetry`) are **non-mutating**. The three adapters are classes (`final class`); the protocol is `AnyObject`-constrained. The struct holds `private let adapter: any ProviderAdapter` — a constant class reference. The referent's message array state mutates internally through the class reference, with no copy-on-write semantics. This directly avoided the protocol-existential mutation pitfall described in RESEARCH.md Pitfall 2.

## Shared OpenAICompatHelpers Decision

**Not created.** Deepseek and Kimi adapters share the same OpenAI-compatible wire format but each is ~170 lines independently. The shared logic (OpenAIToolRequest/Response types, tool encoding, argument decoding) already lives in the shared type definitions (`OpenAIToolRequest.swift`, `OpenAIToolResponse.swift`). The adapter classes themselves are message-state-init-retry-decode code — 60 lines of structure with different URLs and quirks. Not loud enough to extract. Per CONTEXT.md: "sharing only if duplication becomes loud."

## Line Counts

| File | Lines |
|------|-------|
| `AgentLoopProvider.swift` (deleted) | 625 |
| `AgentProvider.swift` (new) | 108 |
| `Providers/AnthropicAdapter.swift` (new) | 155 |
| `Providers/DeepseekAdapter.swift` (new) | 211 |
| `Providers/KimiAdapter.swift` (new) | 207 |
| **Sum of new files** | **681** |

Net: +56 lines. The increase is mostly doc comments and explicit MARK sections added to the new files for clarity.

## Reasoning-Content (Deepseek) and Partial/Safety (Kimi) Handling

**Deepseek:** The existing implementation already had a comment `// CRITICAL: Do NOT include reasoning_content`. In practice, `OpenAIToolResponse.choices[0].message` decodes only `content` and `toolCalls` fields — `reasoning_content` is a separate field not in the response struct, so it's silently dropped by the decoder. No special stripping code needed; the Phase 18 anti-pattern note is preserved as a comment in `DeepseekAdapter.appendAssistantResponse`.

**Kimi:** The existing `KimiAgentProvider` had identical structure to `DeepseekAgentProvider` except for the base URL (`api.moonshot.ai` vs `api.deepseek.com`). No Kimi-specific partial/safety flags were present in the original implementation beyond the standard OpenAI-compat `finishReason` field. The "partial/safety quirks" referenced in the PLAN.md appear to be aspirational/not yet implemented in the original code. The adapter faithfully preserves the existing behavior.

## Phase 18 Decision Preserved

Provider owns message state. `AgentLoop` never sees `AnthropicToolRequest.Message`, `OpenAIToolRequest.Message`, or any provider-specific type. The adapters are the module boundary — `AgentProvider` holds `any ProviderAdapter`, erasing the specific message array element type.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Stale comment in ModelCatalog.swift referencing deleted file**
- **Found during:** Task 2 (post-delete verification)
- **Issue:** Comment read "in AgentLoopProvider.swift" — file was deleted, comment now incorrect
- **Fix:** Updated comment to remove the stale file reference
- **Files modified:** Sources/cellar/Core/ModelCatalog.swift
- **Committed in:** `60c1160` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 stale comment)
**Impact on plan:** Cosmetic correctness fix. No scope creep.

## Issues Encountered

None. Build was green after each step: (1) new files added alongside old file, (2) AgentLoop + AIService updated, (3) old file deleted.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 42 P02 complete. `AgentLoopProvider.swift` is deleted. The agent loop now has one concrete provider path.
- Phase 42 P03 (AgentToolName typed enum) can proceed immediately — no dependency on P02's internal adapter types.
- Three adapters are ready for Phase 43's tool-use parity work (each adapter independently owns its encoding/decoding).

---

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| Sources/cellar/Core/AgentProvider.swift exists | FOUND |
| Sources/cellar/Core/Providers/AnthropicAdapter.swift exists | FOUND |
| Sources/cellar/Core/Providers/DeepseekAdapter.swift exists | FOUND |
| Sources/cellar/Core/Providers/KimiAdapter.swift exists | FOUND |
| Sources/cellar/Core/AgentLoopProvider.swift absent | CONFIRMED DELETED |
| Commit 0c82ac0 (Task 1) exists | FOUND |
| Commit 60c1160 (Task 2) exists | FOUND |
| swift build succeeds | PASSED |
| AgentLoop.provider type is AgentProvider (concrete) | CONFIRMED |
| Zero references to old protocol class names | CONFIRMED |

---
*Phase: 42-unify-agent-loop-with-single-model-catalog-and-typed-tool-boundary*
*Completed: 2026-05-03*

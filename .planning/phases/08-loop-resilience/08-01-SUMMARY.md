---
phase: 08-loop-resilience
plan: 01
subsystem: ai-agent
tags: [anthropic, token-usage, budget, agent-loop, opus]

requires:
  - phase: 07-agentic-v2
    provides: "AgentLoop struct, AIModels tool-use types, CellarPaths"
provides:
  - "AnthropicToolUsage struct decoding input_tokens/output_tokens from API"
  - "AgentLoopResult with totalInputTokens, totalOutputTokens, estimatedCostUSD"
  - "CellarConfig with budget ceiling from env/file/default"
  - "Model ID corrected to claude-opus-4-6"
affects: [08-loop-resilience-plan-02]

tech-stack:
  added: []
  patterns: ["config priority chain: env var > file > default", "optional usage decoding on API responses"]

key-files:
  created:
    - Sources/cellar/Persistence/CellarConfig.swift
  modified:
    - Sources/cellar/Models/AIModels.swift
    - Sources/cellar/Core/AgentLoop.swift
    - Sources/cellar/Persistence/CellarPaths.swift
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "Budget default is $5.00 per session, configurable via CELLAR_BUDGET env or ~/.cellar/config.json"
  - "Usage field is optional on AnthropicToolResponse to handle API responses that omit it"
  - "Token/cost fields initialized to zero at all return sites — Plan 02 wires actual accumulation"

patterns-established:
  - "Config priority chain: CELLAR_BUDGET env var > ~/.cellar/config.json > hardcoded default"

requirements-completed: [LOOP-03]

duration: 1min
completed: 2026-03-28
---

# Phase 8 Plan 01: Loop Data Layer Summary

**AnthropicToolUsage decoding, extended AgentLoopResult with token/cost fields, CellarConfig budget loading, and model ID correction to claude-opus-4-6**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-28T23:13:52Z
- **Completed:** 2026-03-28T23:14:18Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Added AnthropicToolUsage struct that decodes input_tokens and output_tokens from Anthropic API responses
- Extended AgentLoopResult with totalInputTokens, totalOutputTokens, and estimatedCostUSD fields (zeroed for now, Plan 02 wires accumulation)
- Created CellarConfig with load() that reads budget ceiling from CELLAR_BUDGET env var, ~/.cellar/config.json, or default $5.00
- Corrected model ID from claude-sonnet-4-20250514 to claude-opus-4-6 in AgentLoop default and AIService call site

## Task Commits

Each task was committed atomically:

1. **Task 1: Add AnthropicToolUsage and extend AgentLoopResult** - `68a0e1b` (feat)
2. **Task 2: Create CellarConfig and add configFile path** - `e3c4b15` (feat)

## Files Created/Modified
- `Sources/cellar/Models/AIModels.swift` - Added AnthropicToolUsage struct and usage field on AnthropicToolResponse
- `Sources/cellar/Core/AgentLoop.swift` - Extended AgentLoopResult with token/cost fields, fixed model default to claude-opus-4-6
- `Sources/cellar/Core/AIService.swift` - Fixed model ID to claude-opus-4-6 at agent loop call site
- `Sources/cellar/Persistence/CellarPaths.swift` - Added configFile static property
- `Sources/cellar/Persistence/CellarConfig.swift` - New file: budget config with env/file/default priority chain

## Decisions Made
- Budget default is $5.00 per session, configurable via CELLAR_BUDGET env or ~/.cellar/config.json
- Usage field is optional on AnthropicToolResponse to handle API responses that omit it
- Token/cost fields initialized to zero at all return sites — Plan 02 wires actual accumulation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All data types in place for Plan 02 to wire budget tracking, retry logic, and cost display into the agent loop
- CellarConfig.load() ready to be called from AgentLoop or AIService
- AnthropicToolResponse.usage ready to be accumulated in the loop

---
*Phase: 08-loop-resilience*
*Completed: 2026-03-28*

## Self-Check: PASSED

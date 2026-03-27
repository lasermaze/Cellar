---
phase: 06-implement-agentic-launch-architecture-with-ai-tool-use-loop
plan: 01
subsystem: ai
tags: [anthropic, tool-use, agent-loop, swift, codable, json]

# Dependency graph
requires:
  - phase: 03.1-expand-ai-repair-system
    provides: AIService, WineFix, AIModels foundation types
provides:
  - JSONValue recursive Codable enum for arbitrary JSON
  - ToolContentBlock enum with text/toolUse/toolResult cases
  - MessageContent enum (plain string or block array)
  - ToolDefinition struct with input_schema encoding
  - AnthropicToolRequest/AnthropicToolResponse for tool-use API
  - AgentLoop struct with send-execute-return cycle
affects:
  - 06-02 (AgentLauncher will use AgentLoop + ToolDefinition)
  - All future plans that build on the agentic architecture

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "JSONValue indirect enum: recursive Codable via singleValueContainer, Bool decoded before Double"
    - "ToolContentBlock: tagged union with custom Codable reading type field"
    - "AgentLoop send-execute-return: append user -> call API -> print text -> if tool_use execute + append results -> loop"
    - "ResultBox @unchecked Sendable + DispatchSemaphore for sync URLSession bridge (mirrors AIService pattern)"

key-files:
  created:
    - Sources/cellar/Core/AgentLoop.swift
  modified:
    - Sources/cellar/Models/AIModels.swift

key-decisions:
  - "JSONValue decodes Bool before Double — critical ordering to prevent true/false becoming 1.0/0.0"
  - "ToolContentBlock named to avoid collision with existing AnthropicResponse.ContentBlock"
  - "AgentLoop is a struct with private callAPI method — avoids making AIService.callAPI internal"
  - "system: nil when systemPrompt is empty — avoids sending empty string to Anthropic API"
  - "tools: nil when tools array is empty — cleaner than sending empty array"
  - "is_error only encoded in ToolContentBlock when true — matches Anthropic API convention"

patterns-established:
  - "AgentLoop.run(): synchronous blocking method for CLI tool compatibility"
  - "Tool results appended as user turn with .blocks([ToolContentBlock]) content"
  - "Text blocks printed with 'Agent: ' prefix, tool calls with '-> toolName' prefix"

requirements-completed: []

# Metrics
duration: 2min
completed: 2026-03-27
---

# Phase 06 Plan 01: Tool-Use API Types and AgentLoop Summary

**JSONValue Codable enum, ToolContentBlock tagged union, and AgentLoop send-execute-return state machine — the foundational layer for agentic game launching**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-27T22:32:23Z
- **Completed:** 2026-03-27T22:34:14Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added 6 new types to AIModels.swift: JSONValue, ToolContentBlock, MessageContent, ToolDefinition, AnthropicToolRequest, AnthropicToolResponse — all alongside existing types without any collision
- Created AgentLoop struct implementing the full send-execute-return cycle with iteration capping, text streaming, and error recovery
- Established the pattern all subsequent plans will use for AI-driven launch orchestration

## Task Commits

Each task was committed atomically:

1. **Task 1: Add tool-use API types to AIModels.swift** - `b0eb48b` (feat)
2. **Task 2: Implement AgentLoop state machine** - `d82f651` (feat)

## Files Created/Modified
- `Sources/cellar/Models/AIModels.swift` - Added JSONValue, ToolContentBlock, MessageContent, ToolDefinition, AnthropicToolRequest, AnthropicToolResponse
- `Sources/cellar/Core/AgentLoop.swift` - New file: AgentLoop struct with run(initialMessage:toolExecutor:) and AgentLoopResult

## Decisions Made
- **JSONValue Bool before Double decode order**: Reversed from natural order — Bool must be tried before Double otherwise `true`/`false` silently become `1.0`/`0.0` due to Swift JSON decoder behavior
- **ToolContentBlock naming**: Named `ToolContentBlock` (not `ContentBlock`) to avoid collision with the existing `AnthropicResponse.ContentBlock` nested type
- **AgentLoop as struct with private HTTP**: Keeps callAPI private to AgentLoop rather than making AIService.callAPI internal — cleaner encapsulation, same DispatchSemaphore + ResultBox pattern
- **Nil coalescing for system/tools**: Pass nil instead of empty string/array to Anthropic API — avoids confusing the model with empty system prompts

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- AgentLoop is ready to use: construct with apiKey + tools + systemPrompt, call run(initialMessage:toolExecutor:)
- AnthropicToolRequest/AnthropicToolResponse types handle the full tool-use conversation protocol
- Plan 06-02 can now build tool definitions (file_exists, read_dir, run_command, etc.) and wire AgentLoop into LaunchCommand

---
*Phase: 06-implement-agentic-launch-architecture-with-ai-tool-use-loop*
*Completed: 2026-03-27*

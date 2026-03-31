---
phase: 18-deepseek-api-support
plan: "01"
subsystem: core/ai-providers
tags: [ai, deepseek, provider-abstraction, tool-use, openai-compat]
dependency_graph:
  requires: []
  provides: [AgentLoopProvider protocol, AnthropicAgentProvider, DeepseekAgentProvider, OpenAI tool-use types]
  affects: [AgentLoop.swift (Plan 02 wires in provider)]
tech_stack:
  added: []
  patterns: [provider-abstraction, DispatchSemaphore+URLSession, per-provider pricing map]
key_files:
  created:
    - Sources/cellar/Core/AgentLoopProvider.swift
  modified:
    - Sources/cellar/Models/AIModels.swift
    - Sources/cellar/Core/AIService.swift
decisions:
  - "deepseek-chat chosen as default Deepseek model (deepseek-reasoner excluded — no function calling support)"
  - "OpenAI tool result messages are per-result (not array) — each tool result is a separate Message"
  - "DeepseekAgentProvider explicitly strips reasoning_content by only capturing .content and .toolCalls"
  - "agentCallAPI is a free function shared by both providers to avoid duplication"
  - "modelPricing is a module-level let map — O(1) lookup, easy to extend"
metrics:
  duration: "~12 min"
  completed: "2026-03-31"
  tasks: 2
  files: 3
---

# Phase 18 Plan 01: AgentLoopProvider Protocol + Implementations Summary

AgentLoopProvider protocol abstraction with AnthropicAgentProvider (Anthropic tool-use format) and DeepseekAgentProvider (OpenAI-compatible format) plus complete OpenAI tool-use request/response types for Deepseek API integration.

## What Was Built

### AIModels.swift additions
- `AIProvider.deepseek(apiKey: String)` case added to the provider enum
- `OpenAIToolDef` — tool definition in OpenAI format (`type: "function"`, nested `FunctionDef`)
- `OpenAIToolRequest` — OpenAI-compatible API request with `Message` (Codable for round-trip), `ToolCall`, `FunctionCall`
- `OpenAIToolResponse` — response decoder with `Choice`, `Message`, `ToolCall`, `Usage` (`prompt_tokens`/`completion_tokens`)

### AgentLoopProvider.swift (new file, 428 lines)
- `AgentLoopProviderResponse` — normalized response (textBlocks, toolCalls, stopReason, inputTokens, outputTokens)
- `AgentLoopProvider` protocol — 5 mutating methods + modelName + pricingPerToken
- `modelPricing` map — pricing for claude-sonnet-4-6, claude-opus-4-6, deepseek-chat, deepseek-reasoner
- `agentCallAPI` — shared DispatchSemaphore+URLSession helper
- `AnthropicAgentProvider` — wraps Anthropic API; stop_reason translation (end_turn/tool_use/max_tokens)
- `DeepseekAgentProvider` — wraps Deepseek API; finish_reason translation (stop/tool_calls/length)

### AIService.swift fix
- Added `.deepseek` case to `makeAPICall` switch (throws `.unavailable` — agent loop path used instead)

## Stop Reason Mapping

| Anthropic stop_reason | Deepseek finish_reason | AgentLoopProviderResponse.StopReason |
|----------------------|------------------------|--------------------------------------|
| end_turn             | stop                   | .endTurn                             |
| tool_use             | tool_calls             | .toolUse                             |
| max_tokens           | length                 | .maxTokens                           |
| other                | other                  | .other(value)                        |

## Key Design Decisions

1. **deepseek-chat as default** — deepseek-reasoner excluded; it does not support function calling
2. **Per-result tool messages** — OpenAI format requires one Message per tool result, not a batch
3. **reasoning_content excluded** — DeepseekAgentProvider only captures `content` and `toolCalls` from responses; reasoning_content never forwarded into conversation history
4. **Arguments as JSON string** — Deepseek arguments field is a JSON string; decoded via `JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8))`
5. **Provider owns message array** — AgentLoop never holds Anthropic/OpenAI Message types; all message management is internal to each provider

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Case] Added .deepseek handler to AIService.makeAPICall switch**
- **Found during:** Task 1
- **Issue:** Adding `.deepseek` to AIProvider enum made the switch in `AIService.makeAPICall` non-exhaustive, which would prevent compilation
- **Fix:** Added `.deepseek` case that throws `.unavailable` (the simple API call path doesn't use Deepseek — that goes through AgentLoopProvider in Plan 02)
- **Files modified:** Sources/cellar/Core/AIService.swift
- **Commit:** 0d42fc3

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 0d42fc3 | feat(18-01): add OpenAI tool-use types and .deepseek AIProvider case |
| 2 | 7ef529e | feat(18-01): add AgentLoopProvider protocol with Anthropic and Deepseek implementations |

## Self-Check

Verified:
- `Sources/cellar/Core/AgentLoopProvider.swift` exists (428 lines)
- `AIProvider.deepseek` case present in AIModels.swift
- `OpenAIToolRequest`, `OpenAIToolDef`, `OpenAIToolResponse` in AIModels.swift
- `protocol AgentLoopProvider` defined
- `struct AnthropicAgentProvider` conforms to protocol
- `struct DeepseekAgentProvider` conforms to protocol
- `modelPricing` covers all 4 models
- `swift build` completes with no errors

## Self-Check: PASSED

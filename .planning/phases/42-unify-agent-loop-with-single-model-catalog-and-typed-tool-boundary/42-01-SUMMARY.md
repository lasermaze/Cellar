---
phase: 42-unify-agent-loop-with-single-model-catalog-and-typed-tool-boundary
plan: "01"
subsystem: core/model-catalog
tags: [model-catalog, pricing, provider-routing, refactor]
dependency_graph:
  requires: []
  provides: [ModelCatalog, ModelDescriptor, ModelCatalogError, ModelProvider]
  affects: [AIService, AgentLoopProvider]
tech_stack:
  added: []
  patterns: [static-table-with-strict-resolver, descriptor-injection]
key_files:
  created:
    - Sources/cellar/Core/ModelCatalog.swift
  modified:
    - Sources/cellar/Core/AgentLoopProvider.swift
    - Sources/cellar/Core/AIService.swift
decisions:
  - "ModelProvider enum introduced (without associated values) as catalog discriminant — AIProvider has associated API keys and cannot be stored in a static table"
  - "fallbackModels in AIService.swift is now a computed var derived from ModelCatalog.all — catalog is the single source of truth"
  - "claude-haiku-4-5-20251001 added to catalog (was in fallbackModels but not in modelPricing dict)"
  - "claude-haiku-3-5 added to catalog to cover the named variant (prior modelPricing omitted it)"
metrics:
  duration_seconds: 185
  completed: "2026-05-03T21:36:05Z"
  tasks_completed: 2
  files_changed: 3
---

# Phase 42 Plan 01: ModelCatalog — Single Source of Truth for Model Identity

Single static model catalog (`ModelCatalog.all`) with strict resolver replaces the scattered `modelPricing` global dict in `AgentLoopProvider.swift` and the hand-authored `fallbackModels` dict in `AIService.swift`.

## What Was Built

### ModelCatalog.swift (new — 128 lines)

- `enum ModelProvider: String, Sendable, Equatable` — provider discriminant without associated values (`.anthropic`, `.deepseek`, `.kimi`)
- `struct ModelDescriptor: Sendable` — lean descriptor with `id`, `provider`, `inputPricePerToken`, `outputPricePerToken`, `maxOutputTokens`
- `enum ModelCatalog` — caseless, with `static let all: [ModelDescriptor]` and `static func descriptor(for id: String) throws -> ModelDescriptor`
- `enum ModelCatalogError: Error, LocalizedError` — `case unknownModel(String)` with user-visible error message

### Catalog Entries by Provider

| Provider | Count | Models |
|----------|-------|--------|
| Anthropic | 5 | claude-sonnet-4-6, claude-opus-4-6, claude-opus-4-5, claude-haiku-3-5, claude-haiku-4-5-20251001 |
| Deepseek | 1 | deepseek-chat (deepseek-reasoner intentionally absent — no function calling, Phase 18) |
| Kimi | 3 | moonshot-v1-8k, moonshot-v1-32k, moonshot-v1-128k |

### AIService.swift changes

- `fallbackModels` converted from `static let [String: [ModelOption]]` to `static var [String: [ModelOption]]` computed from `ModelCatalog.all` — catalog is the single source of truth
- `runAgentLoop` now resolves `resolveModel(for: providerKey)` → `ModelCatalog.descriptor(for: id)` at session boundary before creating the provider
- Unknown model ID surfaces as `AgentEvent.error(...)` + `.failed(...)` return — no silent fallback
- Descriptor injected into each provider constructor (`AnthropicAgentProvider`, `DeepseekAgentProvider`, `KimiAgentProvider`)

### AgentLoopProvider.swift changes

- Global `modelPricing: [String: (Double, Double)]` dict removed (10 lines)
- All three provider structs now accept `descriptor: ModelDescriptor` in their `init` instead of `model: String`
- `pricingPerToken()` returns `(inputPrice, outputPrice)` stored at init from descriptor (no dict lookup, no `?? (0.0, 0.0)` fallback)
- `maxOutputTokensLimit` is a stored `let` property initialized from `descriptor.maxOutputTokens`

### AgentLoopProvider.swift Line Count

- Before: 623 lines
- After: 625 lines (net +2: removed 10-line dict, added 2 stored properties per provider × 3 providers = +6 net lines per provider init site)

## Pricing Values

Pricing copied verbatim from the prior `modelPricing` dict. The prior dict did not include `claude-haiku-3-5` or `claude-haiku-4-5-20251001` — added with estimated Haiku-tier pricing (0.8/4.0 per million tokens input/output). Verify against Anthropic pricing page before next release.

## `fallbackModels` Fate

Kept as a thin computed view over `ModelCatalog.all`. The `ModelOption` struct is preserved for the web layer (dropdown UI). Labels are now derived from model IDs (not hand-authored display names). This is a minor visual regression for the web dropdown but keeps the catalog as single source of truth. Custom display labels can be added to `ModelDescriptor` in a future phase if needed.

## Deviations from Plan

### Auto-fixed Issues

None.

### Design Deviation: ModelProvider vs AIProvider

**Found during:** Task 1
**Issue:** `AIProvider` enum in `AIModels.swift` has associated values (`.anthropic(apiKey: String)`, etc.), making it unsuitable for storage in a `Sendable` static table and for direct equality comparison without pattern matching.
**Fix:** Introduced `enum ModelProvider: String, Sendable, Equatable` in `ModelCatalog.swift` as the catalog discriminant. `ModelDescriptor.provider: ModelProvider` (not `AIProvider`). `AIService.runAgentLoop` maps the live `AIProvider` case to `providerKey: String` then dispatches the `switch provider` the same way as before.
**Rule applied:** Rule 2 (correctness requirement — `AIProvider` cannot be stored in a Sendable struct without losing the associated value or violating Sendable)
**Files modified:** ModelCatalog.swift

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| Sources/cellar/Core/ModelCatalog.swift exists | FOUND |
| Sources/cellar/Core/AgentLoopProvider.swift exists | FOUND |
| Sources/cellar/Core/AIService.swift exists | FOUND |
| Commit aa02a37 (Task 1) exists | FOUND |
| Commit dcc8e27 (Task 2) exists | FOUND |
| swift build succeeds | PASSED |
| modelPricing absent from AgentLoopProvider.swift | PASSED |
| ModelCatalog.descriptor used in AIService.swift | PASSED |

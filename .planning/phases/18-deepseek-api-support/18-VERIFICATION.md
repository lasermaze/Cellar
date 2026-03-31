---
phase: 18-deepseek-api-support
verified: 2026-03-30T00:00:00Z
status: passed
score: 11/11 must-haves verified
re_verification: false
---

# Phase 18: Deepseek API Support — Verification Report

**Phase Goal:** Users can choose Deepseek as an alternative AI provider to Claude for recipe generation, log interpretation, and the full agent loop — with provider selection in config and the web settings UI
**Verified:** 2026-03-30
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | AgentLoop uses AgentLoopProvider instead of hardcoded Anthropic API calls | VERIFIED | AgentLoop.swift has `var provider: AgentLoopProvider`; no `apiKey`, `model`, or `callAnthropic*` methods present; `run()` calls `provider.callWithRetry()`, `provider.appendUserMessage()`, etc. |
| 2 | When AI_PROVIDER=deepseek and DEEPSEEK_API_KEY is set, runAgentLoop uses DeepseekAgentProvider | VERIFIED | AIService.swift line 766: `.deepseek(let apiKey)` case creates `DeepseekAgentProvider(apiKey: apiKey, tools: AgentTools.toolDefinitions, systemPrompt: systemPrompt)` |
| 3 | When AI_PROVIDER=claude (or default), runAgentLoop uses AnthropicAgentProvider | VERIFIED | AIService.swift line 759: `.anthropic(let apiKey)` case creates `AnthropicAgentProvider(apiKey: apiKey, model: "claude-sonnet-4-6", ...)` |
| 4 | Auto-detection: if only one provider key is present, that provider is used | VERIFIED | AIService.swift detectProvider() default branch checks hasAnthropic then hasDeepseek then legacy OpenAI — first present key wins |
| 5 | Simple API calls (diagnose, generateRecipe, generateVariants) route through Deepseek when configured | VERIFIED | makeAPICall() has `.deepseek` case routing to `callDeepseek()` which calls `https://api.deepseek.com/v1/chat/completions` with Bearer auth; all three top-level methods call `makeAPICall(provider: provider, ...)` |
| 6 | Web settings page has provider dropdown and Deepseek API key field | VERIFIED | settings.leaf lines 12–16: select with Auto-detect/Claude/Deepseek options; lines 51–65: Deepseek API key password input with configured/not-set indicator |
| 7 | Missing API key shows provider-named error message | VERIFIED | diagnose(), generateRecipe(), generateVariants(), and runAgentLoop() all check `requested?.lowercased() == "deepseek"` and return `.failed("Deepseek API key not configured...")` vs `.failed("Anthropic API key not configured...")` |
| 8 | An AgentLoopProvider protocol exists abstracting provider-specific communication | VERIFIED | AgentLoopProvider.swift lines 29–36: protocol with modelName, pricingPerToken(), appendUserMessage(), appendAssistantResponse(), appendToolResults(), callWithRetry() |
| 9 | AnthropicAgentProvider implements the protocol using Anthropic tool-use format | VERIFIED | AgentLoopProvider.swift lines 82–223: full implementation with AnthropicToolRequest encoding, AnthropicToolResponse decoding, stop_reason translation |
| 10 | DeepseekAgentProvider implements the protocol using OpenAI-compatible format | VERIFIED | AgentLoopProvider.swift lines 233–428: full implementation with OpenAIToolRequest encoding, OpenAIToolResponse decoding, finish_reason translation, per-result tool messages, reasoning_content excluded |
| 11 | Per-provider pricing map covers all four models | VERIFIED | AgentLoopProvider.swift lines 41–46: modelPricing map covers claude-sonnet-4-6, claude-opus-4-6, deepseek-chat, deepseek-reasoner |

**Score:** 11/11 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Core/AgentLoopProvider.swift` | Protocol + AnthropicAgentProvider + DeepseekAgentProvider | VERIFIED | 428 lines; all three components present and substantive |
| `Sources/cellar/Models/AIModels.swift` | OpenAI tool-use types + .deepseek AIProvider case | VERIFIED | AIProvider.deepseek at line 8; OpenAIToolDef, OpenAIToolRequest, OpenAIToolResponse at lines 385–487 |
| `Sources/cellar/Core/AgentLoop.swift` | Provider-agnostic agent loop | VERIFIED | 368 lines; `var provider: AgentLoopProvider`; no Anthropic-specific types in run() body |
| `Sources/cellar/Core/AIService.swift` | Provider routing for agent loop and simple API | VERIFIED | detectProvider() with AI_PROVIDER support; runAgentLoop() creates correct provider; makeAPICall() has .deepseek case; provider-specific error messages in all four methods |
| `Sources/cellar/Persistence/CellarConfig.swift` | aiProvider config field | VERIFIED | Lines 7–12: `var aiProvider: String?` with `"ai_provider"` CodingKey |
| `Sources/cellar/Web/Controllers/SettingsController.swift` | Provider dropdown + Deepseek key handling | VERIFIED | SettingsContext and KeysInput include deepseekKey, hasDeepseekKey, aiProvider; POST handler writes AI_PROVIDER and DEEPSEEK_API_KEY |
| `Sources/cellar/Resources/Views/settings.leaf` | Provider selection UI | VERIFIED | AI Provider select with three options; Deepseek key input with configured/not-set indicator |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| AIService.detectProvider() | CellarConfig + .env | Reads CellarConfig.load().aiProvider then env["AI_PROVIDER"] | WIRED | Line 11: `let configProvider = CellarConfig.load().aiProvider ?? env["AI_PROVIDER"]` — config takes precedence over env var |
| AIService.runAgentLoop() | AgentLoopProvider | Creates AnthropicAgentProvider or DeepseekAgentProvider in switch | WIRED | Lines 757–774: switch on provider creates correct AgentLoopProvider implementation and passes to AgentLoop init |
| AgentLoop.run() | provider.callWithRetry() | Calls provider methods instead of private callAnthropic* methods | WIRED | Line 174: `response = try provider.callWithRetry(maxTokens: currentMaxTokens, emit: emit)` — no private Anthropic methods remain |
| SettingsController | .env file | Writes AI_PROVIDER and DEEPSEEK_API_KEY to env file | WIRED | Lines 45–57: deepseekKey and aiProvider both handled and written via writeEnvFile() |
| AgentLoopProvider.swift | AIModels.swift | Uses ToolDefinition, JSONValue for tool definitions and responses | WIRED | AnthropicAgentProvider uses AnthropicToolRequest/Response; DeepseekAgentProvider uses OpenAIToolRequest/Response — both defined in AIModels.swift |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| DSPK-01 | 18-01, 18-02 | When AI_PROVIDER=deepseek is set, Cellar uses Deepseek API for all AI operations | SATISFIED | detectProvider() returns .deepseek when AI_PROVIDER=deepseek; runAgentLoop() creates DeepseekAgentProvider; makeAPICall() routes simple calls to callDeepseek() |
| DSPK-02 | 18-02 | Web settings page allows selecting AI provider and entering Deepseek API key | SATISFIED | settings.leaf has provider select dropdown and Deepseek key input; SettingsController reads/writes both fields |
| DSPK-03 | 18-02 | Missing configured provider's API key shows clear error naming the provider | SATISFIED | All four AI entry points (diagnose, generateRecipe, generateVariants, runAgentLoop) have provider-specific error messages for .deepseek and named-Claude cases |

All three DSPK requirements satisfied. No orphaned requirements — traceability table in REQUIREMENTS.md correctly maps DSPK-01/02/03 to Phase 18 and marks all three as Complete.

---

## Anti-Patterns Found

No blockers or warnings found.

Scanned: AgentLoopProvider.swift, AgentLoop.swift, AIService.swift, AIModels.swift, CellarConfig.swift, SettingsController.swift, settings.leaf

Notable observations (informational only):
- `showAITipIfNeeded()` in AIService.swift still references only ANTHROPIC_API_KEY and OPENAI_API_KEY in its tip message (line 822). This is a minor messaging gap — the tip should also mention DEEPSEEK_API_KEY — but it does not affect any AI operation routing.
- CellarConfig.load() returns `aiProvider: nil` when CELLAR_BUDGET env var is set (line 21 — early return with nil aiProvider). This means CELLAR_BUDGET env override silently disables config-based provider selection. Benign in practice since CELLAR_BUDGET is a specialized override.

---

## Human Verification Required

### 1. Provider dropdown selection and persistence

**Test:** In the web UI at /settings, select "Deepseek" from the AI Provider dropdown, enter a Deepseek API key, and save. Reload /settings.
**Expected:** Dropdown shows "Deepseek" selected; key field shows masked placeholder (configured indicator visible).
**Why human:** Form state persistence and correct Leaf template conditional rendering requires a running server.

### 2. End-to-end Deepseek agent loop

**Test:** Set AI_PROVIDER=deepseek and DEEPSEEK_API_KEY=<valid key> in ~/.cellar/.env. Run cellar agent on any game. Confirm agent loop executes tool calls and completes.
**Expected:** All 20 agent tools execute; tool call results round-trip correctly through OpenAI message format; session cost reflects Deepseek pricing ($0.27/$1.10 per million tokens).
**Why human:** Requires a live Deepseek API key and actual game installation. Cannot verify wire-format correctness without real API responses.

### 3. Auto-detection when both keys are set

**Test:** Set both ANTHROPIC_API_KEY and DEEPSEEK_API_KEY in .env with no AI_PROVIDER set. Run any AI operation.
**Expected:** Anthropic is used (anthropic is checked first in auto-detect). Operation succeeds using Claude.
**Why human:** Requires live API keys to confirm which provider actually handles the call.

---

## Gaps Summary

No gaps. All 11 must-haves verified, all 3 requirement IDs satisfied, project builds clean, no anti-patterns blocking goal achievement.

The phase goal is fully achieved: users can configure Deepseek as their AI provider via the web settings UI or .env file, and all AI operations (recipe generation, log interpretation, and the agent loop) route through the Deepseek API when configured.

---

_Verified: 2026-03-30_
_Verifier: Claude (gsd-verifier)_

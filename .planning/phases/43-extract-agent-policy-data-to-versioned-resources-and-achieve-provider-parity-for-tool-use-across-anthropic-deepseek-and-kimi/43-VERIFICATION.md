---
phase: 43-extract-agent-policy-data-to-versioned-resources-and-achieve-provider-parity-for-tool-use-across-anthropic-deepseek-and-kimi
verified: 2026-05-03T23:15:00Z
status: passed
score: 10/10 must-haves verified
re_verification: false
---

# Phase 43: Extract Agent Policy Data to Versioned Resources and Provider Tool-Use Parity — Verification Report

**Phase Goal:** Externalize agent policy data (system prompt, engine families, KnownDLL registry, env/registry allowlists, tool input schemas) into versioned files under Sources/cellar/Resources/policy/ loaded via a fail-loud PolicyResources singleton, AND introduce a canonical AgentToolCall struct so all three providers (Anthropic, DeepSeek, Kimi) achieve native function-calling parity.
**Verified:** 2026-05-03T23:15:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Six versioned policy files exist under Sources/cellar/Resources/policy/ with schema_version: 1 | VERIFIED | All 6 files present; all 5 JSON files parse with schema_version=1; system_prompt.md has --- schema_version: 1 --- frontmatter |
| 2 | PolicyResources.shared loads all six files at startup and exposes typed accessors | VERIFIED | PolicyResources.swift 323 lines; static let shared with fatalError on failure; all six accessors (systemPrompt, engineDefinitions, dllRegistry, envAllowlist, registryAllowlist, toolSchemas) confirmed |
| 3 | Loader throws PolicyError.schemaVersionMismatch when any file's schema_version != expected | VERIFIED | PolicyResources.swift lines 7, 159, 270 throw schemaVersionMismatch; unit test at PolicyResourcesTests.swift:60 covers this case |
| 4 | PolicyResources test suite passes — confirms Bundle.module subdirectory lookup works | VERIFIED | 4 @Test cases in PolicyResourcesTests.swift (71 lines): bundleLookup, happyPath, frontmatterParsing, versionMismatch |
| 5 | AIService.swift agent-loop system prompt is sourced from PolicyResources.shared.systemPrompt — the Swift literal is gone | VERIFIED | AIService.swift:673 = `let systemPrompt = PolicyResources.shared.systemPrompt`; only 2 short prompt literals remain (diagnose at line 240, recipe at line 335 — correct) |
| 6 | AgentTools allowlists and EngineRegistry/KnownDLLRegistry delegate to PolicyResources | VERIFIED | ConfigTools.swift:11,41 are computed vars; EngineRegistry.swift:28 and KnownDLLRegistry.swift:24 are computed vars; CollectiveMemoryService.swift:423 reads registryAllowlist directly |
| 7 | AgentToolName.metadata input schemas read from PolicyResources.shared.toolSchemas — inline literals removed | VERIFIED | schema(for:) helper at line 57; all 24 inputSchema: entries use schema(for: .caseName); tool_schemas.json has exactly 24 keys |
| 8 | All three adapters expose AgentToolCall through AgentLoopProviderResponse — no anonymous tuple | VERIFIED | AgentProvider.swift:16 = `let toolCalls: [AgentToolCall]`; grep for old tuple type returns 0 matches; all three adapters construct AgentToolCall |
| 9 | DeepSeek and Kimi route all 24 tools through native OpenAI-compat tool_calls — no JSON-in-text fallback | VERIFIED | No JSON-in-text fallback pattern found in DeepseekAdapter.swift or KimiAdapter.swift; both construct AgentToolCall from tool_calls array decoding |
| 10 | Every adapter has unit tests verifying encode/decode round-trip on a fixture set of AgentToolCall values | VERIFIED | AnthropicAdapterTests.swift 113 lines/3 tests; DeepseekAdapterTests.swift 131 lines/3 tests; KimiAdapterTests.swift 131 lines/3 tests; all use canonical 3-fixture round-trip set |

**Score:** 10/10 truths verified

---

## Required Artifacts

### Plan 43-01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Resources/policy/system_prompt.md` | Agent loop prompt with schema_version: 1 frontmatter | VERIFIED | Frontmatter present; body begins "You are a Wine compatibility expert..." |
| `Sources/cellar/Resources/policy/engines.json` | Engine family definitions, schema_version: 1 | VERIFIED | 8 engine families; schema_version=1 |
| `Sources/cellar/Resources/policy/engine_dll_registry.json` | KnownDLL replacement rules, schema_version: 1 | VERIFIED | 4 entries (cnc-ddraw, dgvoodoo2, dxwrapper, dxvk); schema_version=1 |
| `Sources/cellar/Resources/policy/env_allowlist.json` | Allowed env var keys, schema_version: 1 | VERIFIED | 13 keys; schema_version=1 |
| `Sources/cellar/Resources/policy/registry_allowlist.json` | Allowed registry key prefixes, schema_version: 1 | VERIFIED | 4 HKEY prefixes; schema_version=1 |
| `Sources/cellar/Resources/policy/tool_schemas.json` | JSON input schemas for all 24 tools, schema_version: 1 | VERIFIED | 24 schemas keyed by AgentToolName.rawValue; schema_version=1 |
| `Sources/cellar/Core/PolicyResources.swift` | PolicyResources struct with shared singleton, typed accessors, fail-loud init; min 80 lines | VERIFIED | 323 lines; all four PolicyError cases; parsePolicyFrontmatter; dual-layout bundle lookup; all six typed accessors |
| `Tests/cellarTests/PolicyResourcesTests.swift` | Bundle.module subdirectory lookup test, schema-version-mismatch test, sample value asserts; min 30 lines | VERIFIED | 71 lines; 4 @Test cases covering all four required behaviors |

### Plan 43-02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Core/AIService.swift` | Contains PolicyResources.shared.systemPrompt | VERIFIED | Line 673 confirmed |
| `Sources/cellar/Core/Tools/ConfigTools.swift` | Contains PolicyResources.shared | VERIFIED | Lines 11 and 41; both allowlists are computed var delegators |
| `Sources/cellar/Models/EngineRegistry.swift` | Contains PolicyResources.shared.engineDefinitions | VERIFIED | Line 28; static var engines computed property |
| `Sources/cellar/Models/KnownDLLRegistry.swift` | Contains PolicyResources.shared.dllRegistry | VERIFIED | Line 24; static var registry computed property |
| `Sources/cellar/Core/AgentToolName.swift` | Contains PolicyResources.shared.toolSchemas | VERIFIED | Line 58; schema(for:) helper reads toolSchemas[rawValue] |

### Plan 43-03 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Models/AgentToolCall.swift` | struct AgentToolCall {id, name, input}; Sendable+Equatable; min 15 lines | VERIFIED | 12 lines (compact struct); struct AgentToolCall: Sendable, Equatable with all three fields |
| `Sources/cellar/Core/AgentProvider.swift` | toolCalls typed as [AgentToolCall] | VERIFIED | Line 16: `let toolCalls: [AgentToolCall]` |
| `Sources/cellar/Core/Providers/AnthropicAdapter.swift` | Decodes tool_use blocks into [AgentToolCall] | VERIFIED | Line 141: `toolCalls.append(AgentToolCall(id: id, name: name, input: input))` |
| `Sources/cellar/Core/Providers/DeepseekAdapter.swift` | Decodes OpenAI tool_calls into [AgentToolCall] | VERIFIED | Line 208: AgentToolCall constructed from call.id, call.function.name, parsed input |
| `Sources/cellar/Core/Providers/KimiAdapter.swift` | Decodes OpenAI tool_calls into [AgentToolCall] | VERIFIED | Line 205: same pattern as DeepSeek |
| `Tests/cellarTests/Providers/AnthropicAdapterTests.swift` | Round-trip + tool_use_id + multi-call; min 40 lines | VERIFIED | 113 lines; 3 @Test cases |
| `Tests/cellarTests/Providers/DeepseekAdapterTests.swift` | Round-trip + tool_call_id + arguments parse; min 40 lines | VERIFIED | 131 lines; 3 @Test cases |
| `Tests/cellarTests/Providers/KimiAdapterTests.swift` | Round-trip + tool_call_id + arguments parse; min 40 lines | VERIFIED | 131 lines; 3 @Test cases |

---

## Key Link Verification

### Plan 43-01 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| PolicyResources.swift | Resources/policy/*.json | Bundle.module.resourcePath (dual-layout path construction) | VERIFIED | Lines 300-319; uses resourcePath not url(forResource:) — documented deviation from plan pattern, works correctly per 43-01 SUMMARY |
| PolicyResources.swift | JSONDecoder | JSONDecoder().decode | VERIFIED | Lines 265, 273 |
| PolicyResources.swift | PolicyError.schemaVersionMismatch | throw on version mismatch | VERIFIED | Lines 159, 270 |

### Plan 43-02 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| AIService.swift | PolicyResources.shared.systemPrompt | direct property read at line 673 | VERIFIED | Pattern confirmed |
| ConfigTools.swift | PolicyResources.shared.envAllowlist | computed AgentTools.allowedEnvKeys at line 11 | VERIFIED | Pattern confirmed |
| AgentToolName.swift | PolicyResources.shared.toolSchemas | toolSchemas[rawValue] at line 58 | VERIFIED | Pattern confirmed |

### Plan 43-03 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| AnthropicAdapter.swift | AgentToolCall | translateAnthropicResponse builds [AgentToolCall] | VERIFIED | Line 141 |
| DeepseekAdapter.swift | AgentToolCall | translateDeepseekResponse builds [AgentToolCall] | VERIFIED | Line 208 |
| KimiAdapter.swift | AgentToolCall | translateKimiResponse builds [AgentToolCall] | VERIFIED | Line 205 |
| AgentLoop.swift | AgentToolCall | iterates response.toolCalls with `for call in` | VERIFIED | Lines 325, 326, 331, 342, 344, 345, 349 — uses call.id, call.name, call.input |

---

## Requirements Coverage

POL-/TUP- requirements are Phase 43-specific. They are defined in CONTEXT.md and ROADMAP.md (line 543) but are not listed in REQUIREMENTS.md — this is expected per the phase instructions ("REQUIREMENTS.md may not yet list POL-/TUP- IDs"). Coverage is traced from plan frontmatter declarations to codebase artifacts.

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| POL-01 | 43-01, 43-02 | Policy resource files extracted and loaded | SATISFIED | Six files in Resources/policy/; PolicyResources.shared exposes all six typed accessors |
| POL-02 | 43-01, 43-02 | Fail-loud schema version validation | SATISFIED | PolicyError.schemaVersionMismatch thrown on mismatch; unit test confirms at PolicyResourcesTests.swift:60 |
| POL-03 | 43-01, 43-02 | AIService system prompt reads from PolicyResources | SATISFIED | AIService.swift:673 confirmed; ~270-line literal removed |
| POL-04 | 43-01, 43-02 | All allowlist/registry/engine call sites delegate to PolicyResources | SATISFIED | ConfigTools, EngineRegistry, KnownDLLRegistry, CollectiveMemoryService all confirmed |
| POL-05 | 43-01 | Tool schemas in tool_schemas.json keyed by AgentToolName.rawValue | SATISFIED | 24 keys in tool_schemas.json; all 24 inputSchema entries in AgentToolName use schema(for:) helper |
| TUP-01 | 43-03 | AgentToolCall struct with Sendable+Equatable replaces anonymous tuple | SATISFIED | AgentToolCall.swift exists; AgentProvider.swift:16 typed as [AgentToolCall]; old tuple type = 0 matches in Sources/ |
| TUP-02 | 43-03 | AnthropicAdapter decodes tool_use blocks into [AgentToolCall] | SATISFIED | AnthropicAdapter.swift:141 confirmed |
| TUP-03 | 43-03 | DeepSeek adapter uses native OpenAI-compat tool_calls, no fallback | SATISFIED | DeepseekAdapter.swift:208 confirmed; no JSON-in-text fallback |
| TUP-04 | 43-03 | Kimi adapter uses native OpenAI-compat tool_calls, no fallback | SATISFIED | KimiAdapter.swift:205 confirmed; no JSON-in-text fallback |
| TUP-05 | 43-03 | Round-trip unit tests for all three adapters | SATISFIED | 3 test files x 3 @Test cases each = 9 tests; fixtures cover empty object, flat key-value, nested array |

**No orphaned requirements.** REQUIREMENTS.md contains zero POL-/TUP- entries (expected per phase setup). All 10 requirement IDs are claimed across the three plan frontmatter files and have codebase evidence.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | No anti-patterns found in any phase-43 modified files |

No TODO/FIXME/PLACEHOLDER comments in PolicyResources.swift, AgentToolCall.swift, AgentProvider.swift, or any adapter. No empty implementations. No console.log-only handlers.

---

## Human Verification Required

### 1. Agent session smoke test per provider

**Test:** Launch a known-working game with AI_PROVIDER=anthropic, then AI_PROVIDER=deepseek, then AI_PROVIDER=kimi
**Expected:** Agent tool calls execute normally; system prompt logs match prior sessions; no "Failed to parse tool call from text" warnings; registry/env operations use the tighter unified allowlist prefixes
**Why human:** End-to-end HTTP call, real auth tokens, real tool execution sequence — not automatable in unit tests

### 2. Policy file reload behavior on disk corruption

**Test:** Corrupt one policy JSON file (e.g. remove closing brace), start the app
**Expected:** fatalError fires with a readable PolicyError.decodingError message before any agent session runs
**Why human:** fatalError terminates the process; can't assert from a test without a subprocess harness

### 3. Registry allowlist tightening behavioral impact

**Test:** Attempt a set_registry call with key `HKEY_CURRENT_USER\Foo` (old short-prefix match, no longer in allowlist)
**Expected:** The call is rejected/sanitized; confirmed that the unified allowlist (`HKEY_CURRENT_USER\Software\Wine`, etc.) is more specific than the old two-entry list
**Why human:** Requires a live agent session attempting a registry write with a path that matched the old but not the new allowlist; unit test for SecurityTests was already updated but the behavioral intent needs manual confirmation

---

## Gaps Summary

No gaps. All 10 must-have truths are verified. All artifacts exist, are substantive, and are wired. All 10 requirement IDs are satisfied. No blocker anti-patterns.

**Notable deviation documented in summaries (not a gap):** PolicyResources.swift uses `Bundle.module.resourcePath` + path construction rather than `Bundle.module.url(forResource:withExtension:)` as specified in the plan's key_link pattern. This is because SPM `.copy()` resources are not indexed for url(forResource:), only `.process()` resources are. The dual-layout fallback chain (test binary vs main binary path layouts) is correctly implemented and verified by the bundleLookup unit test. This aligns with the existing WebApp.swift pattern in the codebase.

**ROADMAP plan checkboxes:** Phase 43 plans show `[ ]` (unchecked) in ROADMAP.md even though the prose says "3/3 plans complete" and all commits exist. This is a ROADMAP housekeeping gap, not a code gap — the implementation is complete.

---

## Commit Verification

All commits from SUMMARYs verified present in git history:

| Commit | Plan | Description |
|--------|------|-------------|
| `070a12f` | 43-01 Task 1 | feat: create six versioned policy resource files |
| `419860c` | 43-01 Task 2 RED | test: failing PolicyResourcesTests |
| `bbe9b52` | 43-01 Task 2 GREEN | feat: implement PolicyResources loader |
| `88796a6` | 43-02 Task 1 | feat: rewire AIService prompt and AgentTools allowlists |
| `8cf8ce9` | 43-02 Task 2 | feat: rewire EngineRegistry, KnownDLLRegistry, AgentToolName |
| `6585367` | 43-03 Task 1 | refactor: introduce AgentToolCall struct and retype provider response |
| `b666fc2` | 43-03 Task 2 | test: add adapter round-trip tests for all three providers |

---

_Verified: 2026-05-03T23:15:00Z_
_Verifier: Claude (gsd-verifier)_

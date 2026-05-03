---
phase: 42-unify-agent-loop-with-single-model-catalog-and-typed-tool-boundary
verified: 2026-05-03T22:30:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
---

# Phase 42: Unify Agent Loop with Single Model Catalog and Typed Tool Boundary — Verification Report

**Phase Goal:** Collapse three scattered concerns (per-provider model pricing dicts, 623-line AgentLoopProvider protocol with 3 implementations, hand-authored toolDefinitions + two `switch toolName: String` blocks) into a single static `ModelCatalog`, a concrete `AgentProvider` struct with 3 adapters, and a typed `AgentToolName` enum with derived metadata.
**Verified:** 2026-05-03T22:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `AgentLoopProvider.swift` does NOT exist (deleted) | VERIFIED | `ls Sources/cellar/Core/AgentLoopProvider.swift` → No such file |
| 2 | No `switch toolName: String` blocks anywhere in `AgentTools.swift` or related files | VERIFIED | grep finds `switch tool` (typed) at line 156; zero `switch toolName` string-switch blocks |
| 3 | No per-provider `modelPricing` dictionaries | VERIFIED | grep for `modelPricing` in Sources/cellar/ returns zero code matches (one comment in ModelCatalog.swift: "originally sourced from the per-provider modelPricing dict") |
| 4 | `ModelCatalog.descriptor(for:)` is the single resolution path; throws on unknown | VERIFIED | `AIService.swift:976` calls `ModelCatalog.descriptor(for: resolvedModelID)`; error case surfaces via `onOutput?(.error(...))` + `.failed(...)` return — no silent `?? (0.0, 0.0)` anywhere |
| 5 | `AgentProvider` is a concrete struct (not protocol), holds `any ProviderAdapter` | VERIFIED | `AgentProvider.swift:59` declares `struct AgentProvider`; `private let adapter: any ProviderAdapter` |
| 6 | Three adapter classes (`AnthropicAdapter`, `DeepseekAdapter`, `KimiAdapter`) exist, each owning per-provider quirks | VERIFIED | `Sources/cellar/Core/Providers/` contains all three files; each is a `final class` conforming to `ProviderAdapter`; own distinct base URLs, auth header styles, message array types, and response decoders |
| 7 | `AgentToolName: String, CaseIterable` enum with per-case metadata; `toolDefinitions` derived from enum, not hand-authored | VERIFIED | `AgentToolName.swift:13` declares `enum AgentToolName: String, CaseIterable` with 24 cases; `AgentTools.swift:122-124` has `static var toolDefinitions: [ToolDefinition] { AgentToolName.allCases.map { $0.definition } }` |
| 8 | `swift build` passes with no errors | VERIFIED | `Build complete! (0.27s)` — no warnings or errors |
| 9 | `Tools/*.swift` signatures unchanged (Phase 31 carry-forward preserved) | VERIFIED | All 24 tool functions in `Core/Tools/*.swift` have `(input: JSONValue) -> String` or `(input: JSONValue) async -> String` signatures; zero modifications to those files |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Core/ModelCatalog.swift` | ModelDescriptor + ModelCatalog static table + strict resolver + ModelCatalogError | VERIFIED | 129 lines; contains `ModelProvider`, `ModelDescriptor`, `ModelCatalog.all` (9 entries: 5 Anthropic, 1 Deepseek, 3 Kimi), `ModelCatalog.descriptor(for:)`, `ModelCatalogError` |
| `Sources/cellar/Core/AgentProvider.swift` | Concrete AgentProvider struct + ProviderAdapter protocol | VERIFIED | 109 lines; `struct AgentProvider` at line 59; `protocol ProviderAdapter: AnyObject` at line 47; dispatch switch in `init` |
| `Sources/cellar/Core/Providers/AnthropicAdapter.swift` | Anthropic Messages API adapter | VERIFIED | 147 lines; `final class AnthropicAdapter: ProviderAdapter`; owns Anthropic message array, URL, auth, retry |
| `Sources/cellar/Core/Providers/DeepseekAdapter.swift` | Deepseek OpenAI-compat adapter with reasoning-content handling | VERIFIED | 208 lines; `final class DeepseekAdapter: ProviderAdapter`; owns `reasoning_content` strip comment, Deepseek base URL |
| `Sources/cellar/Core/Providers/KimiAdapter.swift` | Kimi OpenAI-compat adapter | VERIFIED | 205 lines; `final class KimiAdapter: ProviderAdapter`; Moonshot base URL, distinct from Deepseek |
| `Sources/cellar/Core/AgentToolName.swift` | AgentToolName enum + ToolMetadata + metadata table + accessors | VERIFIED | 611 lines; 24 cases; `private struct ToolMetadata: @unchecked Sendable`; static metadata table; `definition` and `pendingActionDescription(for:)` accessors; DEBUG `assertMetadataComplete()` |
| `Sources/cellar/Core/AgentTools.swift` | Typed dispatch; `toolDefinitions` derived from enum; pending-action via enum | VERIFIED | 225 lines (was 746); typed `switch tool: AgentToolName` at line 156; `toolDefinitions` computed from `allCases.map`; `trackPendingAction` deleted, replaced by `tool.pendingActionDescription(for: input)` |

Note: `AgentLoopProvider.swift` absent — confirmed deleted.

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `AIService.swift` | `ModelCatalog.swift` | `ModelCatalog.descriptor(for: resolvedModelID)` | WIRED | Line 976; error caught and surfaced via `onOutput?(.error(...))` |
| `AIService.swift` | `AgentProvider.swift` | `AgentProvider(descriptor:apiKey:tools:systemPrompt:)` | WIRED | Line 995; single construction replaces three-way switch |
| `AgentLoop.swift` | `AgentProvider.swift` | `var provider: AgentProvider` | WIRED | Line 147; typed concrete field; `provider.callWithRetry`, `provider.appendUserMessage`, etc. used throughout loop |
| `AgentProvider.swift` | `Providers/*Adapter.swift` | `switch descriptor.provider` in `init` | WIRED | Lines 71–78; `AnthropicAdapter`, `DeepseekAdapter`, `KimiAdapter` constructed by provider case |
| `AgentTools.swift` | `AgentToolName.swift` | `switch AgentToolName(rawValue: toolName)` | WIRED | Lines 140–181; `guard let tool = AgentToolName(rawValue: toolName)` then exhaustive `switch tool` |
| `AgentTools.swift` | `AgentToolName.swift` | `tool.pendingActionDescription(for: input)` | WIRED | Line 184; single call replaces old `trackPendingAction` method with inline string switch |

---

### Note on Remaining `kimi`/`moonshot` String Comparisons

`AIService.swift` still contains four `kimi`/`moonshot` string comparisons (lines 226, 310, 438, 661). These are **not** the session-boundary routing branches targeted by Plan 01. They are provider-unavailable error messages displayed when `detectProvider()` returns `.unavailable` and the user's config references a provider by name — e.g. "Kimi API key not configured." These pre-date Phase 42 and are a separate concern. The session-boundary routing at line 976 is correctly catalog-driven; these error-message paths do not affect routing or pricing.

---

### Requirements Coverage

No formal requirement IDs assigned to Phase 42. Coverage assessed against CONTEXT.md locked decisions:

| Locked Decision | Status | Evidence |
|----------------|--------|---------|
| Single static model catalog in `ModelCatalog.swift` | SATISFIED | File exists, `ModelCatalog.all` has 9 entries across 3 providers |
| Unknown model IDs throw strict error (no `?? (0.0, 0.0)`) | SATISFIED | `ModelCatalog.descriptor(for:)` throws `ModelCatalogError.unknownModel`; `AIService` catches and surfaces it |
| `ModelProvider` enum (not `AIProvider`) as catalog discriminant | SATISFIED | SUMMARY notes deviation: `AIProvider` has associated values; `ModelProvider: String, Equatable` introduced in `ModelCatalog.swift` |
| `AgentLoopProvider` protocol deleted entirely | SATISFIED | File absent; zero grep matches for `AgentLoopProvider\b` in Sources/ |
| Three explicit adapters (`AnthropicAdapter`, `DeepseekAdapter`, `KimiAdapter`) | SATISFIED | All three exist in `Core/Providers/`; no shared `OpenAICompatHelpers.swift` |
| `AgentProvider` concrete struct at loop boundary | SATISFIED | `AgentLoop.provider: AgentProvider` at line 147 |
| Phase 18 decision preserved (provider owns message array) | SATISFIED | Each adapter holds a private `var messages: [...]`; `AgentLoop` never accesses adapter-specific types |
| `AgentToolName: String, CaseIterable` enum, 24 cases | SATISFIED | Confirmed 24 cases; raw values match wire strings |
| `toolDefinitions` derived from `allCases`, hand-authored array deleted | SATISFIED | `AgentTools.swift` line 123 |
| Both `switch toolName: String` blocks eliminated | SATISFIED | Zero matches for `switch toolName` in `AgentTools.swift` |
| `Tools/*.swift` signatures unchanged (Phase 31 carry-forward) | SATISFIED | All signatures verified as `(input: JSONValue) -> String` / `async -> String` |
| `swift build` green | SATISFIED | `Build complete!` confirmed |

---

### Anti-Patterns Found

None. No TODO/FIXME/PLACEHOLDER comments, no empty implementations, no placeholder return values detected in phase-modified files.

---

### Human Verification Required

The following items cannot be verified programmatically and require a live session:

**1. Pricing values in ModelCatalog match live provider pricing pages**
- Test: Compare `ModelCatalog.all` entries against Anthropic, Deepseek, and Moonshot AI current pricing pages
- Expected: Token prices match published rates; SUMMARY notes `claude-haiku-3-5` and `claude-haiku-4-5-20251001` used estimated pricing (0.8/4.0 per million)
- Why human: Pricing pages are external; cannot verify against live web from code

**2. Session launch works with all three providers**
- Test: Configure each provider key and launch a session with a Claude model, deepseek-chat, and moonshot-v1-128k
- Expected: Session starts, tool calls dispatch, cost accumulates, stop/confirm work identically to pre-Phase-42 behavior
- Why human: Integration test requires real API keys and a live Wine session

**3. Pending-action descriptions still appear correctly in UI**
- Test: Launch an agent session, observe a `run_wine_command`-style tool call (e.g. `install_winetricks`, `place_dll`) — confirm the pending-action description text in the UI matches prior format (e.g. "install_winetricks(dotnet48)")
- Expected: Description text generated by `pendingActionDescription(for:)` closure matches old switch-case output
- Why human: UI rendering requires a running session

---

### Gaps Summary

No gaps found. All three plans (42-01, 42-02, 42-03) delivered their goals:

- **Plan 01:** `ModelCatalog` created; pricing and routing consolidated; `fallbackModels` derives from catalog; `AgentLoopProvider.swift` stripped of per-provider pricing dicts.
- **Plan 02:** `AgentProvider` concrete struct created; three adapter classes created; `AgentLoopProvider.swift` deleted; `AgentLoop.provider` retyped to concrete; `AIService` construction unified.
- **Plan 03:** `AgentToolName` 24-case enum created with full metadata table; both string-switch blocks eliminated; hand-authored `toolDefinitions` array deleted; `trackPendingAction` method deleted; build green.

The one notable design deviation (introducing `ModelProvider` instead of reusing `AIProvider`) was correctly handled — `AIProvider` has associated values that preclude `Sendable` static storage; the deviation is sound and documented in the SUMMARY.

---

_Verified: 2026-05-03T22:30:00Z_
_Verifier: Claude (gsd-verifier)_

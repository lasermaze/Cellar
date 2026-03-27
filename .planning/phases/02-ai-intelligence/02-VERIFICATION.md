---
phase: 02-ai-intelligence
verified: 2026-03-27T18:15:00Z
status: passed
score: 15/15 must-haves verified
re_verification: false
---

# Phase 2: AI Intelligence Verification Report

**Phase Goal:** The launch pipeline uses AI to interpret crash logs in plain English and to generate recipes for games that have no bundled recipe
**Verified:** 2026-03-27T18:15:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (Plan 02-01)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | AIService.detectProvider() returns .anthropic when ANTHROPIC_API_KEY is set | VERIFIED | `AIService.swift:11` — checks env["ANTHROPIC_API_KEY"] first, returns `.anthropic(apiKey: key)` |
| 2 | AIService.detectProvider() returns .openai when only OPENAI_API_KEY is set | VERIFIED | `AIService.swift:14` — checks env["OPENAI_API_KEY"] second, returns `.openai(apiKey: key)` |
| 3 | AIService.detectProvider() returns .unavailable when no key is set | VERIFIED | `AIService.swift:17` — returns `.unavailable` as final branch |
| 4 | AIService.diagnose() returns a Diagnosis with plain-English explanation and optional WineFix | VERIFIED | `AIService.swift:73-118` — full implementation with `parseDiagnosisResponse()` mapping to `AIDiagnosis(explanation:suggestedFix:)` |
| 5 | AIService.generateRecipe() returns a valid Recipe struct | VERIFIED | `AIService.swift:148-251` — full implementation decoding AI response to `Recipe` via `JSONDecoder`, validates `executable` non-empty |
| 6 | API failures retry 3 times before returning .failed | VERIFIED | `AIService.swift:53-66` — `withRetry(maxAttempts: 3)` loop with `Thread.sleep(1.0)` between attempts; catches and returns `.failed(error.localizedDescription)` |
| 7 | RecipeEngine.findBundledRecipe() checks ~/.cellar/recipes/ for user-generated recipes | VERIFIED | `RecipeEngine.swift:34-38` — Strategy 2b uses `CellarPaths.userRecipeFile(for: gameId)` before substring scan fallback |
| 8 | RecipeEngine.saveUserRecipe() writes JSON to ~/.cellar/recipes/{gameId}.json | VERIFIED | `RecipeEngine.swift:61-72` — creates `CellarPaths.userRecipesDir`, encodes with `prettyPrinted+sortedKeys`, writes atomically to `CellarPaths.userRecipeFile(for: recipe.id)` |

### Observable Truths (Plan 02-02)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | When WineErrorParser returns no actionable fix, LaunchCommand calls AIService.diagnose() and prints a plain-English explanation | VERIFIED | `LaunchCommand.swift:169-214` — `hasActionableFix` check gates the `AIService.diagnose()` call; `print("\nAI diagnosis: \(diagnosis.explanation)")` on success |
| 2 | AI-suggested WineFix is injected into the retry loop and auto-applied (winetricks install, env var, DLL override) | VERIFIED | `LaunchCommand.swift:177-208` — all three WineFix cases handled: winetricks installs via WinetricksRunner, setEnvVar mutates `envConfigs[configIndex].environment[key]`, setDLLOverride appends to WINEDLLOVERRIDES |
| 3 | When no bundled recipe exists, AddCommand calls AIService.generateRecipe() after the installer runs | VERIFIED | `AddCommand.swift:201-269` — `if recipe == nil` block after post-install scan calls `AIService.generateRecipe(gameName:gameId:installedFiles:)` |
| 4 | AI-generated recipe is displayed with full transparency (same as bundled) and auto-saved to ~/.cellar/recipes/ | VERIFIED | `AddCommand.swift:225-242` — prints environment, registry, deps; calls `RecipeEngine.saveUserRecipe(aiRecipe)` |
| 5 | When AI is unavailable and no recipe exists, user is prompted whether to continue with defaults | VERIFIED | `AddCommand.swift:251-268` — both `.unavailable` and `.failed` cases print prompt and call `readLine()`, throwing `.failure` if user declines |
| 6 | One-time AI tip is shown when provider is unavailable during add flow | VERIFIED | `AddCommand.swift:252` — `AIService.showAITipIfNeeded()` called in `.unavailable` case; sentinel file prevents repeat at `CellarPaths.aiTipSentinel` |
| 7 | AI diagnosis is silent when provider unavailable during launch (not an error) | VERIFIED | `LaunchCommand.swift:210-211` — `.unavailable: break` — no print, no error |

**Score:** 15/15 truths verified

---

## Required Artifacts

### Plan 02-01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Models/AIModels.swift` | AIProvider enum, AIServiceError, AIDiagnosis, AIResult<T>, Anthropic/OpenAI Codable types | VERIFIED | 106 lines; all types present with CodingKeys for snake_case; `firstText` and `firstContent` computed vars on responses |
| `Sources/cellar/Core/AIService.swift` | diagnose() and generateRecipe() with provider routing, HTTP calls, retry logic | VERIFIED | 383 lines; detectProvider, callAPI (semaphore bridge), withRetry, diagnose, generateRecipe, showAITipIfNeeded, makeAPICall, callAnthropic, callOpenAI, extractJSON, parseWineFix |
| `Sources/cellar/Persistence/CellarPaths.swift` | userRecipesDir and userRecipeFile(for:) paths | VERIFIED | `userRecipesDir` at line 13, `userRecipeFile(for:)` at line 15, `aiTipSentinel` at line 19 |
| `Sources/cellar/Core/RecipeEngine.swift` | saveUserRecipe() and user-recipes search pass in findBundledRecipe() | VERIFIED | `saveUserRecipe()` at line 61; Strategy 2b user-recipes search at lines 34-38 |

### Plan 02-02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Commands/LaunchCommand.swift` | AI diagnosis branch after WineErrorParser, before retry | VERIFIED | `AIService.diagnose` present at line 172; inside `if !depInstalled` after winetricks fix check |
| `Sources/cellar/Commands/AddCommand.swift` | AI recipe generation after post-install scan, tip display | VERIFIED | `AIService.generateRecipe` present at line 224; `AIService.showAITipIfNeeded()` at line 252 |

---

## Key Link Verification

### Plan 02-01 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `AIService.swift` | `AIModels.swift` | uses Codable request/response types | VERIFIED | `AnthropicRequest`, `AnthropicResponse`, `OpenAIRequest`, `OpenAIResponse` used in `callAnthropic()` and `callOpenAI()` |
| `AIService.swift` | `Recipe.swift` | generateRecipe returns Recipe | VERIFIED | `AIResult<Recipe>` return type; `JSONDecoder().decode(Recipe.self, from: data)` in `parseRecipeResponse()` |
| `AIService.swift` | `WineErrorParser.swift` | diagnose returns WineFix | VERIFIED | `WineFix?` in `AIDiagnosis.suggestedFix`; `parseWineFix()` maps to `.installWinetricks`, `.setEnvVar`, `.setDLLOverride` |
| `RecipeEngine.swift` | `CellarPaths.swift` | saveUserRecipe uses CellarPaths.userRecipesDir | VERIFIED | `CellarPaths.userRecipesDir` at line 62; `CellarPaths.userRecipeFile(for: recipe.id)` at line 69 |

### Plan 02-02 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `LaunchCommand.swift` | `AIService.swift` | calls diagnose() when WineErrorParser has no fix | VERIFIED | `AIService.diagnose(stderr: truncatedStderr, gameId: game)` at line 172 inside `if !hasActionableFix` |
| `AddCommand.swift` | `AIService.swift` | calls generateRecipe() when no bundled recipe | VERIFIED | `AIService.generateRecipe(gameName: gameName, gameId: gameId, installedFiles: fileContext)` at line 224 inside `if recipe == nil` |
| `AddCommand.swift` | `RecipeEngine.swift` | saves AI recipe via RecipeEngine.saveUserRecipe() | VERIFIED | `RecipeEngine.saveUserRecipe(aiRecipe)` at line 242 in the `.success` case |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| RECIPE-03 | 02-01, 02-02 | AI generates a candidate recipe for games without a bundled recipe | SATISFIED | `AIService.generateRecipe()` fully implemented; `AddCommand` calls it when `recipe == nil`; result saved via `RecipeEngine.saveUserRecipe()`; user prompted on failure/unavailable |
| LAUNCH-04 | 02-01, 02-02 | AI interprets Wine crash logs and provides human-readable diagnosis | SATISFIED | `AIService.diagnose()` fully implemented with plain-English `explanation` field; `LaunchCommand` calls it when `WineErrorParser` finds no actionable fix; explanation printed inline with "AI diagnosis: " prefix |

Both requirements mapped to Phase 2 in REQUIREMENTS.md are satisfied. No orphaned requirements found.

---

## Build Verification

`swift build` output: `Build complete! (0.10s)` — zero errors, zero warnings.

All four documented commits verified present in git history:
- `d6adf8f` — AIModels + AIService + CellarPaths additions
- `eec26cd` — RecipeEngine.saveUserRecipe() + Strategy 2b search pass
- `cb34fc5` — LaunchCommand AI diagnosis wiring
- `068e27f` — AddCommand AI recipe generation wiring

---

## Anti-Patterns Found

No blockers or warnings detected:
- No TODO/FIXME/PLACEHOLDER comments in phase files
- No stub return values (`return null`, `return {}`)
- No console-log-only implementations
- No raw AI JSON exposed to the user — all output goes through structured field extraction

Notable pattern: `ResultBox: @unchecked Sendable` class wrapper in `AIService.callAPI()` — this is an intentional Swift 6 compliance workaround documented in the summary, not a code smell.

---

## Human Verification Required

The following behaviors are structurally correct in code but require a live AI API key to test end-to-end:

### 1. Diagnosis Quality

**Test:** Set `ANTHROPIC_API_KEY`, run a game known to fail, observe the printed "AI diagnosis: ..." line.
**Expected:** 2-3 sentence plain-English explanation that correctly identifies the failure type (e.g., missing DirectX component, not raw error codes).
**Why human:** Cannot verify quality of AI-generated text programmatically.

### 2. Recipe Generation Accuracy

**Test:** Set `ANTHROPIC_API_KEY`, run `cellar add` on an installer without a bundled recipe, observe the printed recipe fields and check `~/.cellar/recipes/{gameId}.json`.
**Expected:** A plausible recipe with a non-empty `executable` field and sensible environment/deps for the game; the JSON file exists and is valid.
**Why human:** Correctness of AI-generated recipe content cannot be verified statically.

### 3. One-Time Tip Suppression

**Test:** Run `cellar add` with no API key configured twice, confirm tip only appears on first run.
**Expected:** Tip printed on first run; sentinel file `~/.cellar/.ai-tip-shown` created; no tip on second run.
**Why human:** Requires live filesystem state that changes between runs.

### 4. User Prompt Accept/Decline Flow

**Test:** Run `cellar add` with no API key; when prompted "Continue with defaults? [y/n]", test both `y` (proceeds to save GameEntry) and `n` (exits with failure).
**Expected:** `y` completes the add flow with default settings; `n` prints "Aborted" and returns non-zero exit code.
**Why human:** Interactive stdin flow cannot be exercised by static analysis.

---

## Summary

Phase 2 goal is fully achieved. All 15 observable truths are verified against the actual codebase. Both requirements (RECIPE-03 and LAUNCH-04) are satisfied:

- `AIService` is a complete, self-contained module with provider auto-detection, synchronous HTTP calls to Anthropic and OpenAI, structured JSON prompts, response parsing, winetricks verb allowlist, retry logic, and one-time tip display.
- `LaunchCommand` calls `AIService.diagnose()` as a third fallback after winetricks fix and before advancing to the next variant — AI-suggested fixes (winetricks, env var, DLL override) are all auto-applied.
- `AddCommand` calls `AIService.generateRecipe()` when no bundled recipe exists, displays the result transparently, saves it to `~/.cellar/recipes/`, and handles all three `AIResult` cases gracefully.
- The build is clean with zero errors.

---

_Verified: 2026-03-27T18:15:00Z_
_Verifier: Claude (gsd-verifier)_

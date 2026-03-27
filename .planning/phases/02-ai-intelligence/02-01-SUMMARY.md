---
phase: 02-ai-intelligence
plan: 01
subsystem: ai
tags: [ai, anthropic, openai, urlsession, foundation, codable, json, wine, recipe]

# Dependency graph
requires:
  - phase: 01-cossacks-launches
    provides: WineErrorParser + WineFix enum, Recipe struct + RecipeEngine, WineResult, CellarPaths
  - phase: 01.1-reactive-dependencies
    provides: WinetricksRunner, LaunchCommand retry loop infrastructure
provides:
  - AIService with diagnose() and generateRecipe() methods
  - AIModels: Codable request/response types for Anthropic and OpenAI APIs
  - CellarPaths.userRecipesDir, userRecipeFile(for:), aiTipSentinel paths
  - RecipeEngine.saveUserRecipe() and ~/.cellar/recipes/ search pass in findBundledRecipe()
affects: [02-02, LaunchCommand, AddCommand]

# Tech tracking
tech-stack:
  added: [URLSession with DispatchSemaphore bridge, Foundation JSONEncoder/JSONDecoder (already present)]
  patterns:
    - ResultBox class wrapper for Swift 6 Sendable compliance in URLSession dataTask closure
    - AIResult<T> enum (success/unavailable/failed) mirrors existing WineErrorParser pattern
    - Retry loop with Thread.sleep(1s) between attempts — simple fixed backoff
    - extractJSON() strips markdown code fences from AI responses before parsing

key-files:
  created:
    - Sources/cellar/Models/AIModels.swift
    - Sources/cellar/Core/AIService.swift
  modified:
    - Sources/cellar/Persistence/CellarPaths.swift
    - Sources/cellar/Core/RecipeEngine.swift

key-decisions:
  - "detectProvider() checks ANTHROPIC_API_KEY first — prefer Claude if both keys set"
  - "URLSession.shared used exclusively (not custom session) to prevent semaphore deadlock on background delegate queue"
  - "ResultBox @unchecked Sendable class used for URLSession dataTask result capture — avoids Swift 6 captured-var mutation warning"
  - "Winetricks verb validation against known-safe allowlist prevents AI hallucinated verb names"
  - "AIResult<T> named to avoid shadowing Swift.Result"
  - "CellarPaths additions (userRecipesDir, userRecipeFile, aiTipSentinel) added in Task 1 commit as Rule 3 fix to unblock AIService compilation"

patterns-established:
  - "AIService is purely static — no instance state, consistent with RecipeEngine/WineErrorParser pattern"
  - "extractJSON() defensive helper handles both bare JSON and markdown-fenced AI responses"
  - "AIDiagnosis wraps WineFix? so callers only see the structured fix, not raw AI text"

requirements-completed: [RECIPE-03, LAUNCH-04]

# Metrics
duration: 3min
completed: 2026-03-27
---

# Phase 2 Plan 1: AI Intelligence Foundation Summary

**AIService module with Anthropic/OpenAI provider routing, structured JSON prompts for Wine diagnosis and recipe generation, retry logic, and user-recipe persistence via RecipeEngine**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-27T17:42:20Z
- **Completed:** 2026-03-27T17:45:31Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- AIService.swift: provider auto-detection, synchronous HTTP calls via DispatchSemaphore bridge, diagnose() with WineFix mapping, generateRecipe() with Recipe decoding, showAITipIfNeeded() with sentinel file
- AIModels.swift: all Codable types for Anthropic Messages API and OpenAI Chat Completions API
- RecipeEngine.saveUserRecipe() writes pretty-printed JSON to ~/.cellar/recipes/ with atomic write
- findBundledRecipe() now checks ~/.cellar/recipes/ (Strategy 2b) before CWD substring fallback

## Task Commits

Each task was committed atomically:

1. **Task 1: Create AIModels and AIService** - `d6adf8f` (feat)
2. **Task 2: Extend CellarPaths and RecipeEngine** - `eec26cd` (feat)

**Plan metadata:** (this commit — docs)

## Files Created/Modified

- `Sources/cellar/Models/AIModels.swift` - AIProvider enum, AIServiceError, AIDiagnosis, AIResult<T>, AnthropicRequest/Response, OpenAIRequest/Response Codable types
- `Sources/cellar/Core/AIService.swift` - detectProvider(), callAPI() with semaphore bridge, withRetry(), diagnose(), generateRecipe(), showAITipIfNeeded(), provider routing helpers
- `Sources/cellar/Persistence/CellarPaths.swift` - added userRecipesDir, userRecipeFile(for:), aiTipSentinel
- `Sources/cellar/Core/RecipeEngine.swift` - added saveUserRecipe(), user-recipes search pass in findBundledRecipe()

## Decisions Made

- Used `URLSession.shared` (not custom session) to avoid semaphore deadlock — background delegate queue delivers dataTask callback without blocking main thread
- `ResultBox` class with `@unchecked Sendable` for capturing mutable result in URLSession closure (same pattern as StderrCapture in WineProcess)
- `AIResult<T>` name chosen to avoid shadowing `Swift.Result`
- CellarPaths additions committed in Task 1 (not Task 2) as they were required to compile AIService.showAITipIfNeeded()

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] CellarPaths paths added in Task 1 to unblock AIService compilation**
- **Found during:** Task 1 (AIService compilation)
- **Issue:** AIService.showAITipIfNeeded() references CellarPaths.aiTipSentinel; Task 2 was planned to add it but Task 1 couldn't compile without it
- **Fix:** Added userRecipesDir, userRecipeFile(for:), and aiTipSentinel to CellarPaths in the Task 1 commit
- **Files modified:** Sources/cellar/Persistence/CellarPaths.swift
- **Verification:** Build complete
- **Committed in:** d6adf8f (Task 1 commit)

**2. [Rule 1 - Bug] ResultBox class wrapper for Swift 6 Sendable compliance**
- **Found during:** Task 1 (first build attempt)
- **Issue:** `var result` captured in URLSession.dataTask closure triggers Swift 6 warning: "mutation of captured var in concurrently-executing code"
- **Fix:** Introduced `ResultBox: @unchecked Sendable` class to hold the result value; mutation now happens on a reference type which doesn't trigger the captured-var warning
- **Files modified:** Sources/cellar/Core/AIService.swift
- **Verification:** Build complete with zero errors
- **Committed in:** d6adf8f (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both auto-fixes necessary for correct compilation. No scope creep.

## Issues Encountered

None — straightforward implementation following research patterns.

## User Setup Required

None — no external service configuration required at build time. ANTHROPIC_API_KEY or OPENAI_API_KEY set by user at runtime enables AI features; both are optional.

## Next Phase Readiness

- AIService module ready for Plan 02-02 to wire into LaunchCommand and AddCommand
- diagnose() signature matches LaunchCommand integration point from RESEARCH.md
- generateRecipe() signature matches AddCommand integration point from RESEARCH.md
- saveUserRecipe() and the ~/.cellar/recipes/ search pass are in place for end-to-end recipe persistence

---
*Phase: 02-ai-intelligence*
*Completed: 2026-03-27*

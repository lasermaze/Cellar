---
phase: 02-ai-intelligence
plan: "02"
subsystem: ai
tags: [ai, wine, recipe, diagnosis, launch, add]

# Dependency graph
requires:
  - phase: 02-01
    provides: AIService with diagnose(), generateRecipe(), showAITipIfNeeded(); AIResult<T>; AIDiagnosis; RecipeEngine.saveUserRecipe()
provides:
  - LaunchCommand calls AIService.diagnose() in retry loop when WineErrorParser has no actionable fix
  - AddCommand calls AIService.generateRecipe() after post-install scan when no bundled recipe exists
  - AI-suggested WineFix auto-applied in LaunchCommand (winetricks install, env var, DLL override)
  - AI recipe displayed transparently and auto-saved to ~/.cellar/recipes/ in AddCommand
  - User prompted to continue with defaults when AI unavailable or failed in AddCommand
  - One-time AI setup tip shown via showAITipIfNeeded() when provider unavailable in AddCommand
affects: [launch-flow, add-flow, self-healing-retry]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "AI integration as optional enhancement: silent on unavailable, explicit on failure"
    - "activeRecipe pattern: let recipe from store, var activeRecipe for AI augmentation"
    - "depInstalled flag reused to prevent configIndex advance on AI env/DLL fix application"

key-files:
  created: []
  modified:
    - Sources/cellar/Commands/LaunchCommand.swift
    - Sources/cellar/Commands/AddCommand.swift

key-decisions:
  - "LaunchCommand AI diagnosis is silent when provider unavailable — not having an API key is not an error during launch"
  - "AI fix in LaunchCommand reuses depInstalled flag to prevent configIndex advance, keeping same retry-loop semantics"
  - "AddCommand uses var activeRecipe = recipe pattern to allow AI augmentation while keeping recipe let-bound from store"
  - "AI recipe generation fires only when recipe == nil — bundled recipes always take precedence"

patterns-established:
  - "AI-optional pattern: .unavailable case handled silently in launch context, with prompt fallback in add context"
  - "Transparency display: AI recipe fields printed same way as bundled recipe fields before save"

requirements-completed: [LAUNCH-04, RECIPE-03]

# Metrics
duration: 3min
completed: 2026-03-27
---

# Phase 2 Plan 02: AI Command Integration Summary

**AI diagnosis wired into LaunchCommand retry loop and AI recipe generation wired into AddCommand post-install flow, completing the AI intelligence feature**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-27T17:46:02Z
- **Completed:** 2026-03-27T17:49:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- LaunchCommand now calls AIService.diagnose() when WineErrorParser finds no actionable fix, printing plain-English explanation and auto-applying the suggested WineFix (winetricks install, env var, or DLL override)
- AddCommand now calls AIService.generateRecipe() after post-install scan when no bundled recipe exists, displaying the AI recipe with full transparency and saving it via RecipeEngine.saveUserRecipe()
- Both commands handle all three AIResult cases (success, unavailable, failed) with appropriate degradation

## Task Commits

Each task was committed atomically:

1. **Task 1: AI diagnosis in LaunchCommand retry loop** - `cb34fc5` (feat)
2. **Task 2: AI recipe generation in AddCommand** - `068e27f` (feat)

**Plan metadata:** (to be committed with SUMMARY.md)

## Files Created/Modified

- `Sources/cellar/Commands/LaunchCommand.swift` - AI diagnosis branch added inside `if !depInstalled` block after winetricks fix check; AI-suggested fixes auto-applied via reused depInstalled flag
- `Sources/cellar/Commands/AddCommand.swift` - AI recipe generation block added between executable discovery and GameEntry save; activeRecipe pattern introduced; GameEntry.recipeId uses activeRecipe?.id ?? gameId

## Decisions Made

- LaunchCommand AI is silent on `.unavailable` (no API key is not a launch error) but prints a message on `.failed`
- AI fix application in LaunchCommand reuses the existing `depInstalled` flag to prevent configIndex advance — keeps retry loop semantics intact without new state
- `var activeRecipe: Recipe? = recipe` introduced in AddCommand so the `recipe` binding from `RecipeEngine.findBundledRecipe` stays a `let` while AI-generated recipe can augment it
- AI recipe generation only triggers when `recipe == nil` — bundled recipes always take precedence, no API calls wasted

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. (AI features degrade gracefully when ANTHROPIC_API_KEY or OPENAI_API_KEY are not set.)

## Next Phase Readiness

- Phase 02 complete — all AI intelligence features wired end-to-end
- LaunchCommand: self-healing retry loop now has AI as a third fallback after winetricks fix and variant cycling
- AddCommand: unknown games now get AI-generated recipes with full transparency and persistence
- End-to-end pipeline ready for live testing with actual Wine errors and real installers

---
*Phase: 02-ai-intelligence*
*Completed: 2026-03-27*

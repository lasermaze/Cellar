# Phase 3: Repair Loop - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

When a launch fails, Cellar automatically retries with AI-suggested variant configurations before declaring failure. The existing retry loop (bundled retryVariants + single-fix AI diagnosis) is extended with a second stage: after bundled variants are exhausted, AI generates full alternative recipe variants informed by cumulative error history. Working variants are saved for future launches.

Requirements: RECIPE-04

</domain>

<decisions>
## Implementation Decisions

### Variant Generation Strategy
- AI generates **full recipe variants** (complete environment config), not just single-fix tweaks
- AI variants only kick in **after bundled retryVariants are exhausted** — bundled variants are fast, free, and tried first
- Existing single-fix logic (WineErrorParser + AI diagnosis) stays as-is within each attempt
- AI receives **cumulative history**: game name, current recipe, error logs from ALL prior attempts, and what configs were already tried — avoids repeating failed approaches
- AI variant scope limited to **environment variables and DLL overrides only** — no registry edits during retry loop (registry changes persist in the bottle and leave residue on failure)

### Retry Budget & Stopping
- **3 AI-generated variants** after bundled variants are exhausted — separate budget from the existing retry loop
- No wall-clock time limit on the overall loop — attempt count is the natural stopping point
- **Stale-output hang detection** on game launches: if Wine produces no stdout/stderr for 5 minutes, assume hung and kill the process (reuse WinetricksRunner's OutputMonitor/NSLock pattern)
- Hung launch treated as a failed attempt — move to next variant
- Existing maxTotalAttempts cap may need adjustment to accommodate the new AI variant budget

### Learning from Success
- When user confirms "reached menu" after an AI variant, **save the working config as the user recipe** at ~/.cellar/recipes/
- **Show + auto-save**: display the winning config diff ("Saving: WINEDLLOVERRIDES=d3d9=native, MESA_GL_VERSION=3.0") then save automatically — no approval prompt (consistent with bundled recipe auto-apply behavior)
- **AI overrides win**: saved user recipe includes AI variant changes on top of bundled recipe base config; user recipe takes precedence over bundled recipe on future launches
- Bundled recipe still exists as fallback if user resets their game

### Failure Reporting
- **Structured summary** after exhausting all variants: list each attempt with variant description, config changes, error category, and AI reasoning (1 sentence per attempt)
- End with best diagnosis + AI-generated manual suggestions (1-2 actionable next steps like "try winecfg and change X" or "this game may need a specific Wine version")
- **Inline AI reasoning during retry**: before each AI variant, show "AI analysis: [reasoning]. Trying: [key config changes]..." — user sees the thought process in real-time (consistent with Phase 2's inline diagnosis)
- **Save repair report** to ~/.cellar/logs/{game}/repair-report-{timestamp}.txt with all attempts, AI reasoning, configs tried, and suggestions — useful for community sharing (Phase 5)
- After failure, **print path only** to report and logs — no interactive prompts after the loop

### Claude's Discretion
- Exact AI prompt engineering for variant generation
- How cumulative history is structured in the prompt (token budget management)
- Adjustment to maxTotalAttempts constant
- Repair report file format details
- How OutputMonitor integrates into WineProcess (vs. being a wrapper)
- Whether to add a new AIService method or extend the existing diagnose() call

</decisions>

<specifics>
## Specific Ideas

- The hang detection gap is real: current WineProcess.run() blocks forever if Wine loops. Phase 3 must add stale-output detection to game launches (reuse WinetricksRunner's OutputMonitor pattern with NSLock wrapper for Swift 6 Sendable compliance).
- AI variant generation is the "recipe refinement loop" deferred from Phase 2 — feed errors back to AI for progressively different approaches.
- The repair report file feeds forward into Phase 5 (Community) — when users share recipes, the repair history shows what was tried.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `WinetricksRunner` + `OutputMonitor`: Stale-output detection pattern (5 min timeout, NSLock wrapper, wineserver cleanup) — reuse for game launch hang detection
- `AIService.diagnose()`: Already calls AI with stderr + game ID, returns structured `AIDiagnosis` with `WineFix` — extend for full variant generation
- `WineErrorParser`: First-pass free diagnosis, stays as the initial filter before AI
- `WineFix` enum: installWinetricks, setEnvVar, setDLLOverride — AI variants will produce collections of these
- `RecipeEngine`: Loads bundled recipes (findBundledRecipe) — Phase 2 added user recipe saving to ~/.cellar/recipes/
- `Recipe` / `RetryVariant` structs: Already model the variant concept with environment dictionaries

### Established Patterns
- NSLock + @unchecked Sendable wrapper class for thread-safe state in readability handlers (WineProcess.StderrCapture, WinetricksRunner.OutputMonitor)
- WineResult structured returns: exitCode, stderr, elapsed, timedOut, logPath
- Informative output: labeled attempts ("Trying variant 2/3..."), inline diagnosis, transparency on config changes
- AI silent on .unavailable — no API key is not an error

### Integration Points
- `LaunchCommand.swift` retry loop (line 86-231): Main integration point — extend with AI variant generation stage after configIndex exhaustion
- `AIService`: New method for variant generation (distinct from diagnose — generates full environment configs, not single fixes)
- `WineProcess.run()`: Needs stale-output timeout support (currently synchronous with no timeout)
- `RecipeEngine`: User recipe save/load for persisting working AI variants
- `CellarPaths`: Add repair report path helper

</code_context>

<deferred>
## Deferred Ideas

- Confidence scoring on variants (track which approaches work reliably across launches) — RECIPE-05, v2
- Automatic bottle reset between retry attempts (clean slate for each variant) — would need Phase 4's reset capability
- Community-sourced variant suggestions (check if others solved this game) — Phase 5
- Permutation-based variants without AI (combinatorial env var exploration) — could complement AI approach

</deferred>

---

*Phase: 03-repair-loop*
*Context gathered: 2026-03-27*

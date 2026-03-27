---
status: testing
phase: 03-repair-loop
source: [03-01-SUMMARY.md, 03-02-SUMMARY.md]
started: 2026-03-27T20:10:00Z
updated: 2026-03-27T20:30:00Z
---

## Current Test

number: 2
name: AI variant injection after bundled variants fail
expected: |
  Launch a game that hangs (produces no output for an extended period). After 5 minutes of no stdout/stderr activity, Cellar should kill the process and wineserver, print a message about the stall, and move on to the next variant — not hang forever.
awaiting: user response

## Tests

### 1. Hung launch detection
expected: Launch a game that hangs (no output for 5 min). Cellar kills the process, reports the stall, and advances to the next variant attempt instead of hanging forever.
result: skipped
reason: Requires a game that hangs — Cossacks crashes with DirectDraw error instead

### 2. AI variant injection after bundled variants fail
expected: When all bundled recipe variants fail, Cellar calls the AI for alternative configurations. You should see "AI analysis: ..." with reasoning, followed by additional retry attempts labeled with the AI-suggested variant descriptions. Requires ANTHROPIC_API_KEY or OPENAI_API_KEY set.
result: [pending]

### 3. Retry attempt labeling
expected: During a multi-attempt launch, each attempt is labeled (e.g., "Attempt 2: Base recipe configuration...", "Attempt 3: AI variant - disable d3d..."). You can see which config is being tried and whether it's a bundled or AI-generated variant.
result: [pending]

### 4. Winning AI variant saved as recipe
expected: If an AI-suggested variant succeeds (you answer "y" to the menu prompt), Cellar prints the config diff and saves it as a user recipe to ~/.cellar/recipes/{gameId}.json. On next launch, this saved recipe is used automatically.
result: [pending]

### 5. Repair report on full exhaustion
expected: After all attempts (bundled + AI variants) fail, Cellar writes a repair report to ~/.cellar/logs/{gameId}/repair-report-{timestamp}.txt and prints its path. The report contains attempt history, per-attempt environments, errors, and best diagnosis.
result: [pending]

### 6. AI unavailable graceful fallback
expected: With no AI API key set, the repair loop still works — it exhausts bundled variants normally and skips the AI variant stage without crashing or showing errors about missing keys.
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 5
skipped: 1

## Gaps

[none yet]

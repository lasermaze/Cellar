---
status: testing
phase: 06-implement-agentic-launch-architecture-with-ai-tool-use-loop
source: 06-01-SUMMARY.md, 06-02-SUMMARY.md, 06-03-SUMMARY.md
started: 2026-03-27T23:10:00Z
updated: 2026-03-27T23:10:00Z
---

## Current Test

number: 2
name: Agent loop launches with API key
expected: |
  Running `cellar launch <game>` with `ANTHROPIC_API_KEY` set starts the AI agent loop. You see agent reasoning output prefixed with "Agent:" and tool call indicators like "-> inspect_game", "-> launch_game". The agent drives the full inspect-configure-launch cycle without hardcoded escalation levels.
awaiting: user response

## Tests

### 1. Project compiles cleanly
expected: Running `swift build` completes with no errors. Warnings in unrelated files are acceptable.
result: pass

### 2. Agent loop launches with API key
expected: Running `cellar launch <game>` with `ANTHROPIC_API_KEY` set starts the AI agent loop. You see agent reasoning output prefixed with "Agent:" and tool call indicators like "-> inspect_game", "-> launch_game". The agent drives the full inspect-configure-launch cycle without hardcoded escalation levels.
result: [pending]

### 3. Agent inspects game before acting
expected: During an agent launch session, the agent calls `inspect_game` early to gather exe type (PE32/PE32+), DLL imports, bottle state, and existing recipe — before attempting any configuration or launch.
result: [pending]

### 4. Agent asks user for validation
expected: After launching the game, the agent calls `ask_user` to check if the game reached the menu or displayed correctly. You see a question prompt and can respond with text.
result: [pending]

### 5. Agent saves recipe on success
expected: When you confirm the game works, the agent calls `save_recipe` to persist the working configuration. A recipe file is created or updated under `~/.cellar/`.
result: [pending]

### 6. Graceful degradation without API key
expected: Running `cellar launch <game>` without any API key set prints "No AI API key configured" and falls back to recipe-only single launch. The game still launches using the bundled recipe with env vars applied, followed by the existing validation prompt.
result: [pending]

### 7. Agent failure falls back to recipe launch
expected: If the AI agent loop fails (e.g., API error), the command falls back to `recipeFallbackLaunch()` — the game still launches using the bundled recipe path rather than erroring out.
result: [pending]

### 8. Agent respects guardrails
expected: The agent loop caps at 20 tool call iterations. Game launches are capped at 8 per session. Winetricks verbs are validated against the allowlist. DLL placement only accepts entries from KnownDLLRegistry.
result: [pending]

## Summary

total: 8
passed: 1
issues: 0
pending: 7
skipped: 0

## Gaps

[none yet]

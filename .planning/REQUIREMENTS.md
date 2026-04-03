# Requirements: Cellar

**Defined:** 2026-04-03
**Core Value:** Any user can go from "I have these old game files" to "the game launches and works" without manually configuring Wine.

## v1.0-v1.2 Requirements (Validated)

Shipped and confirmed in v1.0, v1.1, v1.2. See MILESTONES.md for details.

## v1.3 Requirements

Requirements for v1.3 Agent Loop Rewrite. Each maps to roadmap phases.

### Bug Fixes

- [ ] **BUG-01**: Memory saves reliably when user clicks "Game Works" in web UI — no race condition, no fire-and-forget
- [ ] **BUG-02**: Stop button halts agent within 1 iteration of being clicked — not blocked by in-flight API calls
- [ ] **BUG-03**: Agent cannot exit the loop without saving when it has a working config — no endTurn escape hatch
- [ ] **BUG-04**: Zero data races between web routes and agent loop — thread-safe control channel replaces bare vars

### Architecture

- [ ] **ARCH-01**: Tool execution returns typed `ToolResult` enum (success/stop/error) — eliminates string matching for control flow
- [ ] **ARCH-02**: Thread-safe `AgentControl` class with lock-protected flags replaces `@unchecked Sendable` bare vars on AgentTools
- [ ] **ARCH-03**: `LoopState` struct consolidates all mutable loop state (12 scattered vars → 1 struct)
- [ ] **ARCH-04**: Main loop body is ≤150 lines with no inline budget/spin/logging logic

### Middleware

- [ ] **MW-01**: `AgentMiddleware` protocol with `beforeTool`, `afterTool`, `afterStep` hooks
- [ ] **MW-02**: `BudgetTracker` middleware handles 50%/80%/100% budget thresholds — extracted from loop body
- [ ] **MW-03**: `SpinDetector` middleware detects repeating tool patterns and injects pivot nudges — extracted from loop body
- [ ] **MW-04**: `EventLogger` middleware writes tool invocations and results to structured JSONL event log

### Event Log

- [ ] **LOG-01**: Append-only JSONL event log at `~/.cellar/logs/<gameId>-<timestamp>.jsonl`
- [ ] **LOG-02**: Events include: sessionStarted, llmCalled, toolInvoked, toolCompleted, envChanged, gameLaunched, spinDetected, budgetWarning, sessionEnded
- [ ] **LOG-03**: Event log can generate a resume summary for injection into next session's initial message
- [ ] **LOG-04**: SessionHandoff still works as fallback — event log is preferred when available

### Integration

- [ ] **INT-01**: `AIService.runAgentLoop()` creates middleware chain, event log, and AgentControl; performs post-loop save with `await`
- [ ] **INT-02**: `ActiveAgents` stores `AgentControl` alongside `AgentTools` — web routes use control for stop/confirm
- [ ] **INT-03**: LaunchController stop/confirm routes use `AgentControl.abort()`/`.confirm()` instead of setting bare vars
- [ ] **INT-04**: `prepareStep` hook available for per-iteration adjustments (context trimming, message injection)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Tool implementation changes | Tool files (SaveTools, DiagnosticTools, etc.) still return String — ToolResult wrapping happens in execute() |
| Provider protocol changes | AgentLoopProvider and all implementations (Anthropic/Deepseek/Kimi) unchanged |
| System prompt changes | Prompt content unchanged — only the loop mechanics change |
| New tools | No new agent tools in this milestone |
| Wine noise filtering | Agent intelligence improvement — separate milestone |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUG-01 | Phase 34 | Pending |
| BUG-02 | Phase 35 | Pending |
| BUG-03 | Phase 33 | Pending |
| BUG-04 | Phase 31 | Pending |
| ARCH-01 | Phase 31 | Pending |
| ARCH-02 | Phase 31 | Pending |
| ARCH-03 | Phase 31 | Pending |
| ARCH-04 | Phase 33 | Pending |
| MW-01 | Phase 32 | Pending |
| MW-02 | Phase 32 | Pending |
| MW-03 | Phase 32 | Pending |
| MW-04 | Phase 32 | Pending |
| LOG-01 | Phase 32 | Pending |
| LOG-02 | Phase 32 | Pending |
| LOG-03 | Phase 36 | Pending |
| LOG-04 | Phase 36 | Pending |
| INT-01 | Phase 35 | Pending |
| INT-02 | Phase 35 | Pending |
| INT-03 | Phase 35 | Pending |
| INT-04 | Phase 35 | Pending |

**Coverage:**
- v1.3 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

---
*Requirements defined: 2026-04-03*
*Last updated: 2026-04-03 after v1.3 roadmap created*

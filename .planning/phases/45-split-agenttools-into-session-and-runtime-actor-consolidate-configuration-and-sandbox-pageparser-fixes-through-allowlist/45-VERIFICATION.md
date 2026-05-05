---
phase: 45-split-agenttools-into-session-and-runtime-actor-consolidate-configuration-and-sandbox-pageparser-fixes-through-allowlist
verified: 2026-05-03T00:00:00Z
status: passed
score: 11/11 must-haves verified
re_verification: false
---

# Phase 45: Split AgentTools / Allowlist / Configuration Verification Report

**Phase Goal:** Gate fetch_page behind a PolicyResources domain allowlist (wine/gaming sites only, explicit blocked-URL error with search_web hint). Consolidate AgentTools' six constructor params into a SessionConfiguration struct. Extract all mutable session state into a new AgentSession final class.
**Verified:** 2026-05-03
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | fetch_page called with a winehq.org URL succeeds (domain is allowed) | VERIFIED | `fetch_page_domains.json` contains "winehq.org"; gate uses `hasSuffix(".\($0)")` which allows subdomains |
| 2  | fetch_page called with an unknown domain returns a JSON error with hint key | VERIFIED | ResearchTools.swift lines 158-161: returns `{"error": "Domain not in allowlist", "url": ..., "hint": "Use search_web to find relevant pages first"}` |
| 3  | fetch_page with raw.githubusercontent.com succeeds (suffix match via githubusercontent.com) | VERIFIED | `githubusercontent.com` in JSON; gate: `host.hasSuffix(".githubusercontent.com")` matches `raw.githubusercontent.com` |
| 4  | PolicyResources.shared.fetchPageAllowlist is a non-empty Set<String> at startup | VERIFIED | PolicyResources.swift line 144: `let fetchPageAllowlist: Set<String>`; loader block 8 at lines 264-279; test "fetchPageAllowlist covers all required wine/gaming domains" passes |
| 5  | AgentTools.init accepts a single SessionConfiguration value | VERIFIED | AgentTools.swift line 52: `init(config: SessionConfiguration)` |
| 6  | All tool extensions reference session state via session.X (not bare self.X) | VERIFIED | grep of bare state property names in Core/Tools/ returns zero matches; `session.X` pattern confirmed in all 5 extension files |
| 7  | AIService.runAgentLoop public signature unchanged (six individual params) | VERIFIED | AIService.swift lines 642-651: still accepts gameId, entry, executablePath, wineURL, bottleURL, wineProcess as separate params |
| 8  | AgentTools has no mutable session-state properties directly | VERIFIED | grep for all 11 state property declarations in AgentTools.swift returns zero matches |
| 9  | All 11 session-state properties live in AgentSession | VERIFIED | AgentSession.swift: accumulatedEnv, launchCount, maxLaunches, installedDeps, lastLogFile, pendingActions, lastAppliedActions, previousDiagnostics, hasSubstantiveFailure, sessionShortId, draftBuffer all present |
| 10 | AIService post-loop uses tools.session.X for all session state access | VERIFIED | AIService.swift lines 875, 881, 915-921, 930, 934: all use `tools.session.X`; bare `tools.pendingActions` etc. return zero matches |
| 11 | Build succeeds with zero errors | VERIFIED | `swift build` exits 0; "Build complete! (0.28s)"; all PolicyResourcesTests pass (10/10) |

**Score:** 11/11 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Resources/policy/fetch_page_domains.json` | Plain JSON array of 8 allowed apex domains | VERIFIED | 8 entries: winehq.org, pcgamingwiki.com, protondb.com, steampowered.com, steamcommunity.com, github.com, githubusercontent.com, reddit.com |
| `Sources/cellar/Core/PolicyResources.swift` | fetchPageAllowlist: Set<String> property + loader | VERIFIED | Property declared line 144; loader block 8 at lines 264-279 using JSONDecoder |
| `Sources/cellar/Core/Tools/ResearchTools.swift` | Domain gate before URLRequest creation | VERIFIED | Gate inserted lines 151-162, before `var request = URLRequest(url: pageURL)` at line 165 |
| `Sources/cellar/Core/SessionConfiguration.swift` | Immutable struct with 6 let fields | VERIFIED | struct SessionConfiguration with gameId, entry, executablePath, bottleURL, wineURL, wineProcess |
| `Sources/cellar/Core/AgentTools.swift` | let config: SessionConfiguration, let session: AgentSession, no bare state | VERIFIED | Lines 20 and 48; no state property declarations remain |
| `Sources/cellar/Core/AgentSession.swift` | final class with all 11 mutable session-state properties | VERIFIED | All 11 properties present including lazy draftBuffer initialized from let sessionShortId |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| ResearchTools.swift | PolicyResources.shared.fetchPageAllowlist | hasSuffix subdomain check | WIRED | Line 156-157: `.contains(where: { host == $0 || host.hasSuffix(".\($0)") })` |
| PolicyResources.swift | fetch_page_domains.json | JSONDecoder().decode([String].self) | WIRED | Lines 264-279; block 8 follows identical winetricks_verbs pattern |
| AIService.swift | AgentTools(config: SessionConfiguration(...)) | Internal construction | WIRED | Confirmed — build passes and post-loop uses tools.session.X |
| Tool extensions | session state properties | session.X (unqualified in extensions) | WIRED | All 5 extension files use unqualified `session.X` (valid Swift inside AgentTools extension scope); zero bare self.accumulatedEnv etc. |
| AIService.swift | tools.session.pendingActions etc. | post-loop section | WIRED | 8 occurrences of tools.session.X confirmed; no bare tools.X session accesses remain |
| captureHandoff() in AgentTools.swift | session.accumulatedEnv / session.installedDeps / session.launchCount | direct session access | WIRED | Lines 70-73 of AgentTools.swift confirmed |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ALLOW-01 | 45-01 | fetch_page domain allowlist | SATISFIED | fetch_page_domains.json exists, PolicyResources loads it, ResearchTools gate verified |
| CFG-01 | 45-02 | SessionConfiguration consolidation | SATISFIED | SessionConfiguration.swift exists, AgentTools.init(config:) present, tool extensions migrated |
| SPLIT-01 | 45-03 | AgentSession extraction | SATISFIED | AgentSession.swift exists with all 11 properties, AgentTools has no bare mutable state |

### Anti-Patterns Found

None. No TODO/FIXME/placeholder comments in modified files. No stub implementations. No orphaned artifacts.

### Human Verification Required

None. All behaviors are verifiable through static analysis and build/test execution.

---

_Verified: 2026-05-03_
_Verifier: Claude (gsd-verifier)_

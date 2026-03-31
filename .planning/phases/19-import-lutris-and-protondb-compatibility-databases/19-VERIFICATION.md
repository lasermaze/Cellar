---
phase: 19-import-lutris-and-protondb-compatibility-databases
verified: 2026-03-31T20:30:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
---

# Phase 19: Import Lutris and ProtonDB Compatibility Databases Verification Report

**Phase Goal:** Give the agent access to Lutris and ProtonDB community compatibility data so it can make better config decisions before and during diagnosis. A single unified lookup queries both sources, extracts actionable config hints, and injects them into the agent's context. A new tool allows deeper on-demand queries.

**Verified:** 2026-03-31T20:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `CompatibilityService.fetchReport(for:)` queries Lutris API by game name with fuzzy matching and returns actionable Wine config extracted from installer scripts | VERIFIED | Lines 204-263 of CompatibilityService.swift: full pipeline — Lutris search, Jaccard similarity scoring at 0.3 threshold, installer extraction (env vars, DLL overrides, winetricks verbs, registry edits) |
| 2 | When a Steam AppID is discovered from Lutris providerGames, ProtonDB tier rating is fetched and included in the report | VERIFIED | Lines 211-213: `providerGames.first(where: { $0.service == "steam" }).map { $0.slug }` then parallel `fetchProtonDBSummary(appId:)` at lines 228-233 |
| 3 | Proton-specific flags (PROTON_*, STEAM_*, LD_PRELOAD etc.) are stripped from extracted env vars before report is returned | VERIFIED | Lines 467-482: `protonOnlyPrefixes` list and `filterPortableEnvVars` applied at line 243 before report assembly |
| 4 | Results are cached for 30 days under `~/.cellar/research/lutris/` and `~/.cellar/research/protondb/` | VERIFIED | CellarPaths lines 100-107 define both dirs; `readCache`/`writeCache` helpers used throughout; `isStale(ttlDays: 30)` default |
| 5 | When Lutris or ProtonDB APIs are unreachable, fetchReport returns nil without throwing — the caller is never interrupted | VERIFIED | `performFetch` returns `nil` on error; each fetch method returns nil/[] on failure; `fetchReport` guard-returns nil propagating the silence |
| 6 | Compatibility data is auto-injected into the agent's initial message before diagnosis, alongside collective memory context | VERIFIED | AIService.swift lines 834-850: `compatContext` fetched, then injected via `compatReport.formatForAgent()` into `contextParts` after collective memory |
| 7 | The agent has a `query_compatibility` tool it can call on-demand during the agent loop for deeper lookups | VERIFIED | AgentTools.swift lines 569-611: tool definition #20, dispatch case, and `queryCompatibility` handler at line 2364 all present |
| 8 | The system prompt tells the agent how to interpret ProtonDB tiers and Lutris config hints | VERIFIED | AIService.swift lines 776-783: `## Compatibility Data` section with ProtonDB tier guidance and Lutris hint application instructions |
| 9 | When compatibility data is unavailable (API down, no match), the agent proceeds normally with no error surfaced | VERIFIED | AIService.swift line 849: `if let compatReport = compatContext` — nil compatContext simply skips the append; initialMessage is identical to pre-Phase-19 behavior |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Core/CompatibilityService.swift` | Unified Lutris + ProtonDB fetch, parse, cache, filter, format service | VERIFIED | 523 lines; substantive full pipeline implementation; no stubs or TODO markers |
| `Sources/cellar/Persistence/CellarPaths.swift` | `lutrisCompatCacheDir` and `protondbCompatCacheDir` path helpers | VERIFIED | Lines 100-107: both static computed properties returning correct subdirs of `researchCacheDir` |
| `Sources/cellar/Core/AIService.swift` | `CompatibilityService.fetchReport()` call in `runAgentLoop()`, result injected into contextParts | VERIFIED | Lines 834-850: fetch call + contextParts injection both present |
| `Sources/cellar/Core/AgentTools.swift` | `query_compatibility` tool definition and handler | VERIFIED | Tool definition at line 570, dispatch at line 611, handler at line 2364 |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `CompatibilityService.swift` | `https://lutris.net/api/games?search={name}` | URLSession dataTask with 5s timeout | WIRED | `performFetch` wraps URLSession; `request.timeoutInterval = 5`; URL built at lines 278-280 |
| `CompatibilityService.swift` | `https://www.protondb.com/api/v1/reports/summaries/{appId}.json` | URLSession dataTask with 5s timeout | WIRED | Lines 349-353: URL constructed, `request.timeoutInterval = 5`, via same `performFetch` helper |
| `CompatibilityService.swift` | `CellarPaths` | `lutrisCompatCacheDir`, `protondbCompatCacheDir` | WIRED | Lines 272, 315, 343: `CellarPaths.lutrisCompatCacheDir` and `CellarPaths.protondbCompatCacheDir` used in all three fetch methods |
| `AIService.swift runAgentLoop()` | `CompatibilityService.fetchReport()` | Static method call before initialMessage construction | WIRED | Line 835: `let compatContext = CompatibilityService.fetchReport(for: entry.name)` |
| `AgentTools.swift toolDefinitions` | `CompatibilityService.fetchReport()` | `query_compatibility` tool handler | WIRED | Line 2370: `CompatibilityService.fetchReport(for: gameName)` in `queryCompatibility` handler |
| `AIService.swift systemPrompt` | Agent behavior | `## Compatibility Data` guidance section | WIRED | Lines 776-783: section present in system prompt string |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| COMPAT-01 | 19-01-PLAN.md | Agent queries Lutris API by game name with fuzzy matching and extracts actionable Wine config from installer scripts (env vars, DLL overrides, winetricks verbs, registry edits) | SATISFIED | `fetchLutrisGame` (fuzzy match), `fetchLutrisInstallers`, `extractFromInstallers` all fully implemented |
| COMPAT-02 | 19-01-PLAN.md | Agent queries ProtonDB for tier rating using Steam AppID discovered from Lutris, with Proton-specific flags filtered out | SATISFIED | `fetchProtonDBSummary`, Steam AppID extraction from `providerGames`, `filterPortableEnvVars` with 8-prefix list |
| COMPAT-03 | 19-02-PLAN.md | Compatibility data auto-injected into agent's initial message before diagnosis; `query_compatibility` tool available for on-demand lookups | SATISFIED | AIService contextParts injection + AgentTools tool #20 + system prompt guidance all verified |

**REQUIREMENTS.md status column:** Currently marked "Planned" for all three (lines 250-252 in REQUIREMENTS.md). This is a documentation lag — the implementation is complete. Requirements should be updated to "Complete".

---

### Anti-Patterns Found

None. Scanned `CompatibilityService.swift`, relevant sections of `AIService.swift`, and `AgentTools.swift` for TODO/FIXME/placeholder markers, empty implementations, and stub patterns. All clear.

---

### Human Verification Required

#### 1. Lutris API Live Lookup

**Test:** Run `cellar launch <game>` for a game known to be on Lutris (e.g. "Deus Ex"). Check the agent's initial message in the launch log for a `--- COMPATIBILITY DATA ---` block.
**Expected:** Block appears with ProtonDB tier and/or Lutris env vars/winetricks verbs.
**Why human:** Requires live network access to Lutris API and a game that actually has Lutris installers.

#### 2. query_compatibility Tool Invocation

**Test:** Trigger a launch where the agent encounters an unfamiliar game variant and observe whether it calls `query_compatibility` mid-session.
**Expected:** Agent calls the tool with a varied game name and receives formatted compatibility output.
**Why human:** Requires observing agent behavior in a real session; cannot verify tool invocation heuristics programmatically.

#### 3. Silent Failure on Network Unavailability

**Test:** Block outbound connections (e.g. disable Wi-Fi) and run `cellar launch <game>`.
**Expected:** Agent proceeds normally, initial message contains no COMPATIBILITY DATA block, no error is displayed.
**Why human:** Requires controlled network condition to trigger the nil path.

---

### Gaps Summary

No gaps found. All must-haves from both plans are verified in the codebase. The build compiles cleanly. All four documented commits (8b45502, d1ed9d2, 3f58ad2, 2922fd5) exist in git history.

One non-blocking documentation item: REQUIREMENTS.md tracking table still shows COMPAT-01/02/03 as "Planned" rather than "Complete" (lines 250-252). This does not affect functionality.

---

_Verified: 2026-03-31T20:30:00Z_
_Verifier: Claude (gsd-verifier)_

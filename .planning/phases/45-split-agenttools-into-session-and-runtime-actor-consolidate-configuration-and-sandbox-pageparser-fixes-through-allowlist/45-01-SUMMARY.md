---
phase: 45-split-agenttools-into-session-and-runtime-actor-consolidate-configuration-and-sandbox-pageparser-fixes-through-allowlist
plan: "01"
subsystem: security
tags: [policy-resources, allowlist, fetch-page, domain-gate, swift-testing, tdd]

# Dependency graph
requires:
  - phase: 43-extract-agent-policy-data-to-versioned-resources
    provides: PolicyResources struct, winetricks_verbs.json plain-array loading pattern
provides:
  - fetch_page_domains.json policy file with 8 allowed domains
  - PolicyResources.fetchPageAllowlist property (Set<String>)
  - Domain gate in ResearchTools.fetchPage (before network call)
  - Subdomain suffix matching (appdb.winehq.org, raw.githubusercontent.com)
affects:
  - ResearchTools (fetchPage blocked for unknown domains)
  - PolicyResources (new property at startup)
  - Any phase touching fetch_page tool behavior

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Plain JSON array loading: same pattern as winetricks_verbs.json block #7 — no schema_version wrapper"
    - "Subdomain suffix matching: host == domain || host.hasSuffix('.domain') — dot-prefixed prevents evil-winehq.org false match"

key-files:
  created:
    - Sources/cellar/Resources/policy/fetch_page_domains.json
  modified:
    - Sources/cellar/Core/PolicyResources.swift
    - Sources/cellar/Core/Tools/ResearchTools.swift
    - Tests/cellarTests/PolicyResourcesTests.swift

key-decisions:
  - "fetch_page_domains.json is a plain JSON array (no schema_version wrapper) — follows winetricks_verbs.json pattern established in Phase 44"
  - "Domain gate returns JSON error with hint key guiding agent to use search_web instead of blocking silently"
  - "Subdomain suffix check uses dot-prefixed hasSuffix so evil-winehq.org cannot bypass the winehq.org entry"
  - "github.com and githubusercontent.com are separate entries — different apex domains (gist.github.com vs raw.githubusercontent.com)"

patterns-established:
  - "Domain allowlist pattern: load plain JSON array from policy/, expose as Set<String> on PolicyResources"
  - "Gate pattern: guard let host = url.host, contains(where: host == $0 || host.hasSuffix('.$0')), return jsonResult error with hint"

requirements-completed: [ALLOW-01]

# Metrics
duration: 8min
completed: 2026-05-05
---

# Phase 45 Plan 01: fetch_page Domain Allowlist Summary

**Domain gate added to ResearchTools.fetchPage via fetch_page_domains.json policy file and PolicyResources.fetchPageAllowlist, blocking off-allowlist URLs with a hint to use search_web**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-05T00:04:23Z
- **Completed:** 2026-05-05T00:12:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Created `fetch_page_domains.json` with 8 allowed domains including both `github.com` and `githubusercontent.com` as separate entries
- Added `fetchPageAllowlist: Set<String>` to `PolicyResources` struct, loaded using the winetricks_verbs.json plain-array pattern as block #8
- Inserted domain gate in `ResearchTools.fetchPage` before any network call: guards on host existence, then suffix-based subdomain check, returns actionable JSON error with hint key
- Added 3 new tests: `fetchPageAllowlistNonEmpty`, `fetchPageAllowlistCoverage`, `fetchPageSubdomainMatching` — all 10 `PolicyResourcesTests` pass

## Task Commits

1. **Task 1: fetch_page_domains.json + PolicyResources.fetchPageAllowlist** - `5c3a875` (feat)
2. **Task 2: Domain gate in ResearchTools.fetchPage** - `bd4ecc9` (feat)

## Files Created/Modified

- `Sources/cellar/Resources/policy/fetch_page_domains.json` - Plain JSON array of 8 allowed apex domains
- `Sources/cellar/Core/PolicyResources.swift` - Added `fetchPageAllowlist: Set<String>` property and loading block #8
- `Sources/cellar/Core/Tools/ResearchTools.swift` - Inserted domain allowlist check before URLRequest creation
- `Tests/cellarTests/PolicyResourcesTests.swift` - Added 3 new tests + assertions in loaderHappyPath

## Decisions Made

- `fetch_page_domains.json` uses plain JSON array (no schema_version wrapper) — follows the winetricks_verbs.json pattern from Phase 44, keeping it simple since no migration path is needed
- Domain gate returns `{"error": "Domain not in allowlist", "url": ..., "hint": "Use search_web to find relevant pages first"}` — actionable error guides agent rather than silent block
- Subdomain check uses `host.hasSuffix(".\(entry)")` with a dot prefix — prevents `evil-winehq.org` from matching `winehq.org` (critical security edge case tested explicitly)
- `github.com` and `githubusercontent.com` are separate entries in the allowlist — they are distinct apex domains serving different content

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `PolicyResources.fetchPageAllowlist` is live at startup and gates all `fetch_page` calls
- Phase 45 plan 02 and 03 can proceed independently — no blockers
- Any future domain additions are a one-line JSON change to `fetch_page_domains.json`

---
*Phase: 45-split-agenttools-into-session-and-runtime-actor-consolidate-configuration-and-sandbox-pageparser-fixes-through-allowlist*
*Completed: 2026-05-05*

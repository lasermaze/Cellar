---
phase: 14-memory-entry-schema
plan: "01"
subsystem: database
tags: [swift, codable, cryptokit, json, collective-memory]

requires: []
provides:
  - CollectiveMemoryEntry Codable struct with full schema (schemaVersion, gameId, gameName, config, environment, environmentHash, reasoning, engine, graphicsApi, confirmations, lastConfirmed)
  - WorkingConfig struct (environment vars, DLL overrides, registry records, launch args, setup deps)
  - EnvironmentFingerprint struct with computeHash() and current() factory
  - slugify() free function for deterministic filesystem-safe game IDs
  - 12 swift-testing tests covering round-trip, forward-compat, slugify, hash
affects:
  - 15-memory-read-path
  - 16-memory-write-path

tech-stack:
  added: [CryptoKit (system framework — no SPM change)]
  patterns:
    - Co-located schema types in single Swift file (matches SuccessDatabase.swift)
    - Default synthesized Codable for unknown-field forward-compatibility (no custom init(from:))
    - unicodeScalars iteration for locale-independent slugify

key-files:
  created:
    - Sources/cellar/Models/CollectiveMemoryEntry.swift
    - Tests/cellarTests/CollectiveMemoryEntryTests.swift
  modified: []

key-decisions:
  - "Default synthesized Codable on all structs — unknown future JSON fields silently ignored without custom init(from:)"
  - "slugify() uses unicodeScalars + CharacterSet.alphanumerics for determinism across all locales"
  - "EnvironmentFingerprint.canonicalString uses sorted key order (arch|macosVersion|wineFlavor|wineVersion) to ensure hash stability"
  - "CryptoKit SHA-256 first 16 hex chars as environment hash — no new SPM dependency"

patterns-established:
  - "Schema structs in Sources/cellar/Models/ with CodingKeys for snake_case JSON mapping"
  - "Factory static func current() on environment types for automatic system value detection"

requirements-completed: [SCHM-01, SCHM-02, SCHM-03]

duration: 3min
completed: 2026-03-30
---

# Phase 14 Plan 01: Memory Entry Schema Summary

**CollectiveMemoryEntry, WorkingConfig, and EnvironmentFingerprint Codable structs with SHA-256 environment hashing and locale-independent slugify(), verified by 12 swift-testing tests**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-31T00:56:29Z
- **Completed:** 2026-03-31T00:58:44Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Defined the complete collective memory entry schema as three Codable structs with snake_case JSON keys
- Implemented EnvironmentFingerprint.computeHash() using CryptoKit SHA-256, returning a 16-char hex prefix for environment-keyed deduplication in Phase 16
- slugify() converts display names to filesystem-safe slugs deterministically via unicodeScalars (no locale sensitivity)
- 12 swift-testing tests verify round-trip encoding, optional field nil decoding, unknown-field forward-compatibility, slugify edge cases, and hash determinism

## Task Commits

1. **Task 1: CollectiveMemoryEntry.swift** - `2ce97ef` (feat)
2. **Task 2: CollectiveMemoryEntryTests.swift** - `c2121c1` (test)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `Sources/cellar/Models/CollectiveMemoryEntry.swift` - WorkingConfig, EnvironmentFingerprint, CollectiveMemoryEntry structs + slugify()
- `Tests/cellarTests/CollectiveMemoryEntryTests.swift` - 12 swift-testing tests covering SCHM-01, SCHM-02, SCHM-03

## Decisions Made

- Default synthesized Codable on all structs so unknown future JSON fields are silently ignored without writing custom init(from:) — clean forward-compatibility
- slugify() uses unicodeScalars + CharacterSet.alphanumerics to avoid locale-sensitive lowercasing/normalization APIs
- Canonical string uses sorted key order (arch|macosVersion|wineFlavor|wineVersion) so hash is stable regardless of insertion order
- CryptoKit (system framework) used for SHA-256 — no new SPM dependency added

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added `import Foundation` to test file**
- **Found during:** Task 2 (test compilation)
- **Issue:** JSONEncoder/JSONDecoder/Data not in scope — test file missing Foundation import
- **Fix:** Added `import Foundation` at top of CollectiveMemoryEntryTests.swift
- **Files modified:** Tests/cellarTests/CollectiveMemoryEntryTests.swift
- **Verification:** All 12 tests pass after fix
- **Committed in:** c2121c1 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary fix for test compilation. No scope creep.

## Issues Encountered

- Missing Foundation import in test file caused JSONEncoder/JSONDecoder/Data not found errors on first build. Fixed inline per Rule 3.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Schema data contract is locked and tested — Phase 15 (Read Path) and Phase 16 (Write Path) can build directly on these types
- All three requirement IDs satisfied: SCHM-01 (round-trip), SCHM-02 (slugify), SCHM-03 (forward-compat)
- DLLOverrideRecord and RegistryRecord from SuccessDatabase.swift reused as planned — same module, no import needed

---
*Phase: 14-memory-entry-schema*
*Completed: 2026-03-30*

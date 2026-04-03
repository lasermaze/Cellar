---
phase: 26-iso-disc-image-support-for-game-installation
plan: "01"
subsystem: core
tags: [hdiutil, disc-image, iso, bin, cue, installer-discovery, wine]

# Dependency graph
requires: []
provides:
  - DiscImageHandler struct with mount(), discoverInstaller(), detach(), volumeLabel() API
  - .iso/.img mounting via hdiutil attach -readonly -nobrowse -plist
  - .bin mounting via CRawDiskImage fallback and hdiutil convert CDR fallback
  - .cue companion .bin resolution with case-insensitive directory search
  - autorun.inf parsing with isoLatin1 encoding and backslash normalization
  - Three-tier installer discovery: autorun.inf > common names > all-exe listing
  - User prompt for multi-exe disc selection
  - Volume label extraction with generic label filtering
affects:
  - 26-02 (AddCommand integration will call DiscImageHandler directly)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "DiscImageHandler follows GuidedInstaller struct pattern — no class, no state, pure method dispatch"
    - "runHdiutil() captures stdout as Data, stderr for error messages — same pattern as runStreamingProcess()"
    - "parseMountInfo() walks system-entities plist array for mount-point + dev-entry pair"
    - "detach() never throws — silently suppresses all errors, retries with -force"

key-files:
  created:
    - Sources/cellar/Core/DiscImageHandler.swift
  modified: []

key-decisions:
  - "Separate DiscImageHandler struct (not inlined in AddCommand) — follows GuidedInstaller/WinetricksRunner isolation pattern"
  - "CRawDiskImage attempted first for .bin; convert to CDR only as fallback — avoids unnecessary temp files"
  - "Case-insensitive path resolution for autorun.inf installer paths — old disc images often have inconsistent casing"
  - "volumeLabel() returns nil for generic labels (CDROM, DISC, DVD, etc.) so callers fall back to filename"
  - ".img extension treated same as .iso (many renamed disc images use .img)"

patterns-established:
  - "DiscImageError cases include Try this: suggestions per project convention"
  - "hdiutil called with -readonly -nobrowse -plist for machine-parseable non-Finder-visible mounts"
  - "Orphaned block devices detached before throwing noVolumesMounted — no leaked dev entries"

requirements-completed:
  - "disc image mounting"
  - "installer discovery within mounted volumes"
  - "cleanup/unmount after install"

# Metrics
duration: 2min
completed: 2026-04-02
---

# Phase 26 Plan 01: DiscImageHandler Summary

**DiscImageHandler struct with hdiutil-based .iso/.bin/.cue mounting, three-tier autorun.inf/common-names/all-exe installer discovery, and never-throw detach with CDR conversion fallback**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-02T19:39:05Z
- **Completed:** 2026-04-02T19:41:12Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Created DiscImageHandler struct in Sources/cellar/Core/ following GuidedInstaller isolation pattern
- Implemented mount() with .iso direct attach, .bin CRawDiskImage + convert-to-CDR fallback, and .cue companion .bin resolution
- Implemented discoverInstaller() with priority: autorun.inf parsing (isoLatin1, backslash normalization) → common names → all-exe listing with user prompt
- Implemented detach() that never throws, retries with -force, and cleans up temp CDR directories
- All DiscImageError cases include user-friendly "Try this:" suggestions per project convention

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DiscImageHandler with mount, discover, and detach methods** - `cf7c24b` (feat)

**Plan metadata:** (pending — docs commit)

## Files Created/Modified
- `Sources/cellar/Core/DiscImageHandler.swift` - Full DiscImageHandler with mount/discoverInstaller/detach/volumeLabel plus private hdiutil helpers

## Decisions Made
- Separate DiscImageHandler struct rather than inlining in AddCommand — same isolation pattern as GuidedInstaller and WinetricksRunner; AddCommand integration (Plan 02) becomes a small readable change
- CRawDiskImage attempted first for .bin to avoid unnecessary conversion; CDR temp files only created when needed
- Case-insensitive path resolution for autorun.inf installer paths — critical for old disc images where casing varies
- volumeLabel() filters generic labels (CDROM, DISC, DVD) returning nil so callers fall back to image filename
- .img extension supported same as .iso — many old disc images distributed as renamed .img files

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- DiscImageHandler provides clean API: mount(imageURL:) -> MountResult, discoverInstaller(at:) -> URL, detach(mountResult:)
- AddCommand integration (Plan 02) can detect .iso/.bin/.cue extensions, call mount(), swap installerURL, use defer { detach() }
- No blockers

---
*Phase: 26-iso-disc-image-support-for-game-installation*
*Completed: 2026-04-02*

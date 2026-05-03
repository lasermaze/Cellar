---
phase: 43-extract-agent-policy-data-to-versioned-resources-and-achieve-provider-parity-for-tool-use-across-anthropic-deepseek-and-kimi
plan: 01
subsystem: agent
tags: [policy-resources, bundle, spm, schema-versioning, tdd]

requires:
  - phase: 42-unify-agent-loop-with-single-model-catalog-and-typed-tool-boundary
    provides: AgentToolName enum with rawValue = tool wire names; used as key in tool_schemas.json

provides:
  - Six versioned policy files under Sources/cellar/Resources/policy/ (schema_version: 1)
  - PolicyResources struct: singleton loader with typed accessors for all six policy artifacts
  - parsePolicyFrontmatter() internal helper for YAML-style frontmatter extraction
  - PolicyError enum with four error cases (fail-loud init)

affects:
  - 43-02 (rewires AIService/AgentTools/EngineRegistry callers to read from PolicyResources)
  - AgentToolName.swift (inputSchema literals can be replaced with PolicyResources.shared.toolSchemas)
  - Sources/cellar/Core/Tools/ConfigTools.swift (allowedEnvKeys, allowedRegistryPrefixes)
  - Sources/cellar/Core/AIService.swift (agent-loop systemPrompt literal ~line 673)
  - Sources/cellar/Models/EngineRegistry.swift (static engines array)
  - Sources/cellar/Models/KnownDLLRegistry.swift (static registry array)

tech-stack:
  added: []
  patterns:
    - "versioned-policy-file: schema_version field in every policy JSON/MD for forward-compatible evolution"
    - "dual-layout-bundle-lookup: try resourcePath+/policy first (test binary), then resourcePath+/Resources/policy (main binary)"
    - "private-file-structs: EnginesFile/KnownDLLFile/etc. in PolicyResources.swift keep Codable blast radius local — no Codable added to runtime types"
    - "fail-loud-singleton: static let shared fatalError on load; init() throws lets tests inspect error"

key-files:
  created:
    - Sources/cellar/Resources/policy/system_prompt.md
    - Sources/cellar/Resources/policy/engines.json
    - Sources/cellar/Resources/policy/engine_dll_registry.json
    - Sources/cellar/Resources/policy/env_allowlist.json
    - Sources/cellar/Resources/policy/registry_allowlist.json
    - Sources/cellar/Resources/policy/tool_schemas.json
    - Sources/cellar/Core/PolicyResources.swift
    - Tests/cellarTests/PolicyResourcesTests.swift
  modified: []

key-decisions:
  - "Bundle.module.resourcePath used (not url(forResource:)) — SPM .copy() resources are not indexed for url(forResource:withExtension:); resourcePath + manual path construction is the proven approach (see WebApp.swift)"
  - "Dual-layout lookup: resourcePath already points to Resources/ in test binary but to bundle root in main binary — both paths tried at init time"
  - "DLLPlacementTarget not Codable — mapped from camelCase string in JSON to enum at PolicyResources init; keeps existing enum unchanged"
  - "parsePolicyFrontmatter() is internal (not private) — test 3 calls it directly without going through PolicyResources.init()"
  - "_loadVersionedEnvAllowlist test hook is internal static func — exposes Data injection point for version-mismatch test without requiring a test-only initializer on PolicyResources"
  - "No Codable added to EngineDefinition, KnownDLL, CompanionFile — private EngineDefinitionFile/KnownDLLFile structs in PolicyResources.swift keep the blast radius narrow (43-02 decision)"

patterns-established:
  - "PolicyVersionProbe: separate top-level struct for schema_version check avoids nesting Decodable types in generic functions (Swift 6 restriction)"

requirements-completed: [POL-01, POL-02, POL-03, POL-04, POL-05]

duration: 10min
completed: 2026-05-03
---

# Phase 43 Plan 01: Extract Policy Data to Versioned Resources Summary

**Six versioned policy files under Resources/policy/ and a fail-loud PolicyResources singleton loader verified by four unit tests**

## Performance

- **Duration:** 10 min
- **Started:** 2026-05-03T22:18:27Z
- **Completed:** 2026-05-03T22:28:27Z
- **Tasks:** 2
- **Files modified:** 8 (all new)

## Accomplishments

- Verbatim extraction of agent-loop system prompt (~270 lines) into `system_prompt.md` with `schema_version: 1` frontmatter
- Five JSON policy files with `"schema_version": 1`: engines (8 families), DLL registry (4 entries), env allowlist (13 keys), registry allowlist (4 prefixes), tool schemas (24 tools)
- `PolicyResources.swift` loader with dual-layout SPM bundle path resolution, private file structs for decode isolation, and `fatalError` at the `shared` singleton site
- `PolicyResourcesTests.swift` with 4 passing tests (TDD red-green): bundle lookup, happy-path, frontmatter parser, version-mismatch throw
- Zero behavior change: no existing callers wired yet (43-02 scope)

## Task Commits

1. **Task 1: Six policy resource files** - `070a12f` (feat)
2. **Task 2 RED: Failing tests** - `419860c` (test)
3. **Task 2 GREEN: PolicyResources loader** - `bbe9b52` (feat)

## Files Created/Modified

- `Sources/cellar/Resources/policy/system_prompt.md` — Agent-loop system prompt verbatim with YAML frontmatter (schema_version: 1)
- `Sources/cellar/Resources/policy/engines.json` — 8 engine families (GSC/DMCR, Unreal 1, Build, id Tech 2/3, Unity, UE4/5, Westwood, Blizzard)
- `Sources/cellar/Resources/policy/engine_dll_registry.json` — 4 KnownDLL entries with companion files (cnc-ddraw, dgvoodoo2, dxwrapper, dxvk)
- `Sources/cellar/Resources/policy/env_allowlist.json` — 13 allowed env keys for set_environment
- `Sources/cellar/Resources/policy/registry_allowlist.json` — 4 allowed HKEY prefix paths for set_registry
- `Sources/cellar/Resources/policy/tool_schemas.json` — 24 tool JSON schemas keyed by AgentToolName.rawValue
- `Sources/cellar/Core/PolicyResources.swift` — PolicyResources struct + PolicyError enum + parsePolicyFrontmatter helper (130 lines)
- `Tests/cellarTests/PolicyResourcesTests.swift` — 4 passing tests

## Decisions Made

- `Bundle.module.url(forResource:withExtension:)` does NOT work with SPM `.copy("Resources")` — uses `resourcePath` + path construction instead (same approach as WebApp.swift)
- Dual-layout bundle lookup: test binary has `resourcePath` = `<bundle>/Resources`, main binary has `resourcePath` = `<bundle>`. Both tried at init time via fallback chain.
- No Codable conformance added to `EngineDefinition`, `KnownDLL`, or `CompanionFile` — private `*File` structs in PolicyResources.swift decode from JSON then map to runtime types.
- `parsePolicyFrontmatter` is `internal` (not file-private) so Test 3 can call it in isolation without constructing a full PolicyResources.
- `_loadVersionedEnvAllowlist(from:expectedVersion:)` test hook exposes Data injection for version-mismatch test.
- `@unchecked Sendable` on PolicyResources — singleton loaded once at startup, all fields immutable after init.
- `PolicyVersionProbe` promoted to file-level struct to avoid Swift 6 error about Decodable types nested in generic functions.

## Call Sites 43-02 Must Rewire

| File | Line | What to Replace |
|------|------|-----------------|
| `Sources/cellar/Core/AIService.swift` | ~673 | `let systemPrompt = """ ... """` (agent-loop only; leave diagnose/recipe/variants at ~240/335/462) |
| `Sources/cellar/Core/AIService.swift` | ~998 | `tools: AgentTools.toolDefinitions` (still from AgentToolName enum; tool schemas now in PolicyResources) |
| `Sources/cellar/Core/Tools/ConfigTools.swift` | 11 | `static let allowedEnvKeys: Set<String>` |
| `Sources/cellar/Core/Tools/ConfigTools.swift` | 55 | `private static let allowedRegistryPrefixes: [String]` |
| `Sources/cellar/Models/EngineRegistry.swift` | 28 | `static let engines: [EngineDefinition]` |
| `Sources/cellar/Models/KnownDLLRegistry.swift` | 23 | `static let registry: [KnownDLL]` |
| `Sources/cellar/Core/AgentToolName.swift` | 44-578 | `inputSchema: JSONValue` per-case literals in metadata table |

## Deviations from Plan

None - plan executed exactly as written.

The only mid-execution discovery was that `Bundle.module.url(forResource:withExtension:)` does not work with `.copy()` resources (only `.process()` resources get indexed), which required the `resourcePath`-based approach. This is a clarification, not a deviation from plan intent — the plan cited WikiService as the Bundle.module pattern, and WebApp.swift already uses `resourcePath`.

## Issues Encountered

- Swift 6 does not allow Decodable types nested in generic functions (`VersionProbe` struct inside `decodeVersionedData<T>` caused compile error) — resolved by promoting to file-level `PolicyVersionProbe`.
- Test binary `Bundle.module.resourcePath` already points to `Resources/` subdirectory (unlike main binary). Added dual-layout fallback in `resolvedPolicyDirectory()`.

## Next Phase Readiness

- `PolicyResources.shared` is callable and all six loaders verified green
- 43-02 can immediately start rewiring callers — no API changes expected from this plan
- The call-site table above gives 43-02 precise file/line targets

---
*Phase: 43-extract-agent-policy-data-to-versioned-resources-and-achieve-provider-parity-for-tool-use-across-anthropic-deepseek-and-kimi*
*Completed: 2026-05-03*

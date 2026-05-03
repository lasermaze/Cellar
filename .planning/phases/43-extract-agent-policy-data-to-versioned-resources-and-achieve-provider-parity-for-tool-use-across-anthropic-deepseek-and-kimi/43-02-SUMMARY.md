---
phase: 43-extract-agent-policy-data-to-versioned-resources-and-achieve-provider-parity-for-tool-use-across-anthropic-deepseek-and-kimi
plan: 02
subsystem: agent
tags: [policy-resources, refactor, call-site-rewire, allowlist, schema-delegation]

requires:
  - phase: 43-01
    provides: PolicyResources.shared singleton with all six typed accessors; six versioned policy files under Resources/policy/

provides:
  - All inline policy literals removed from Swift sources — AIService, ConfigTools, EngineRegistry, KnownDLLRegistry, AgentToolName, CollectiveMemoryService now delegate to PolicyResources.shared
  - Future policy edits go exclusively to Resources/policy/* JSON/MD files

affects:
  - Sources/cellar/Core/AIService.swift (agent-loop systemPrompt now from PolicyResources)
  - Sources/cellar/Core/Tools/ConfigTools.swift (allowlists delegating)
  - Sources/cellar/Models/EngineRegistry.swift (engines computed var)
  - Sources/cellar/Models/KnownDLLRegistry.swift (registry computed var)
  - Sources/cellar/Core/AgentToolName.swift (inputSchema per-case via helper)
  - Sources/cellar/Core/CollectiveMemoryService.swift (no longer hardcodes registry prefixes)

tech-stack:
  added: []
  patterns:
    - "computed-var delegator: static var foo: T { PolicyResources.shared.foo } pattern replaces static let foo: T = [...] for all five data sources"
    - "schema(for:) helper: private static func in AgentToolName extension avoids 24 inline callsites while keeping PolicyResources dependency localized"

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Core/Tools/ConfigTools.swift
    - Sources/cellar/Models/EngineRegistry.swift
    - Sources/cellar/Models/KnownDLLRegistry.swift
    - Sources/cellar/Core/AgentToolName.swift
    - Sources/cellar/Core/CollectiveMemoryService.swift
    - Tests/cellarTests/SecurityTests.swift

key-decisions:
  - "private static func schema(for:) in AgentToolName rather than per-case inlining — keeps delegation pattern visible in one place; fallback is a minimally-valid empty-object schema (signals missing JSON key, does not crash)"
  - "SecurityTests.sanitizeEntryTruncatesRegistryKey updated: old test used HKEY_CURRENT_USER\\ (bare), which no longer matches tighter unified allowlist — corrected to HKEY_CURRENT_USER\\Software\\ (this IS intended behavior tightening per plan)"
  - "ConfigTools.allowedRegistryPrefixes kept private — CollectiveMemoryService reads PolicyResources.shared.registryAllowlist directly (no visibility change needed)"

requirements-completed: [POL-01, POL-02, POL-03, POL-04]

duration: 10min
completed: 2026-05-03
---

# Phase 43 Plan 02: Rewire Call Sites to PolicyResources Summary

**All six inline policy literals removed from Swift sources — AIService, ConfigTools, EngineRegistry, KnownDLLRegistry, AgentToolName, and CollectiveMemoryService now delegate to PolicyResources.shared**

## Performance

- **Duration:** 10 min
- **Started:** 2026-05-03T22:32:21Z
- **Completed:** 2026-05-03T22:42:21Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Replaced ~270-line agent-loop system prompt literal in AIService.swift with `PolicyResources.shared.systemPrompt` (1 line)
- Replaced `static let allowedEnvKeys: Set<String>` and `private static let allowedRegistryPrefixes: [String]` in ConfigTools with computed var delegators
- Removed duplicate `allowedRegistryPrefixes` local var in CollectiveMemoryService.sanitizeEntry (now reads `PolicyResources.shared.registryAllowlist`)
- Replaced `static let engines: [EngineDefinition]` in EngineRegistry with computed var (8 engine definitions removed)
- Replaced `static let registry: [KnownDLL]` in KnownDLLRegistry with computed var (4 DLL entries removed)
- Added `private static func schema(for:) -> JSONValue` helper in AgentToolName; replaced all 24 per-case `inputSchema:` inline JSONValue literals with `schema(for: .caseName)` calls
- Updated SecurityTests to use tighter allowlist-compatible prefix (intended behavior change per plan)
- Zero fallback-schema uses: all 24 tool names resolved from tool_schemas.json (verified by passing AgentToolDefinitionTests)

## Task Commits

1. **Task 1: Rewire AIService + ConfigTools + CollectiveMemoryService** - `88796a6` (feat)
2. **Task 2: Rewire EngineRegistry + KnownDLLRegistry + AgentToolName** - `8cf8ce9` (feat)

## Files Modified (LOC delta)

| File | Removed | Added | Net |
|------|---------|-------|-----|
| Sources/cellar/Core/AIService.swift | ~273 (literal) | 1 | -272 |
| Sources/cellar/Core/Tools/ConfigTools.swift | 15 (two let arrays) | 2 (two computed vars) | -13 |
| Sources/cellar/Core/CollectiveMemoryService.swift | 1 (short literal) | 1 (delegation) | 0 |
| Sources/cellar/Models/EngineRegistry.swift | ~75 (8-engine literal) | 2 | -73 |
| Sources/cellar/Models/KnownDLLRegistry.swift | ~65 (4-DLL literal) | 1 | -64 |
| Sources/cellar/Core/AgentToolName.swift | ~400 (24 inline schemas) | 10 (helper + 24 calls) | -390 |
| Tests/cellarTests/SecurityTests.swift | 1 (old prefix) | 1 (new prefix) | 0 |

**Total:** ~829 lines removed, ~17 lines added.

## Tool Schema Coverage

All 24 `AgentToolName.allCases` raw values are present in `tool_schemas.json`:
`ask_user`, `check_file_access`, `fetch_page`, `inspect_game`, `install_winetricks`, `launch_game`, `list_windows`, `place_dll`, `query_compatibility`, `query_successdb`, `query_wiki`, `read_game_file`, `read_log`, `read_registry`, `save_failure`, `save_recipe`, `save_success`, `search_web`, `set_environment`, `set_registry`, `trace_launch`, `update_wiki`, `verify_dll_override`, `write_game_file`.

No fallback schemas were triggered — zero missing keys.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SecurityTests registry prefix mismatch after allowlist unification**
- **Found during:** Task 1 targeted test run
- **Issue:** `sanitizeEntry truncates registry key to 200 chars` used `HKEY_CURRENT_USER\` (bare) as the test key prefix. After unification with the longer `registry_allowlist.json` prefixes, this bare prefix no longer matches any allowed prefix — so the key is correctly dropped rather than passed through. Test expected `count == 200`, got `nil`.
- **Fix:** Updated test to use `HKEY_CURRENT_USER\\Software\\` (matches `"HKEY_CURRENT_USER\\Software\\"` in `registry_allowlist.json`). This is the intended behavior: the unified allowlist is tighter than the old two-entry short list.
- **Files modified:** Tests/cellarTests/SecurityTests.swift
- **Commit:** 88796a6

## CollectiveMemoryService Old vs New Allowlist

Old (hardcoded in CollectiveMemoryService.sanitizeEntry):
```
["HKEY_CURRENT_USER\\", "HKEY_LOCAL_MACHINE\\"]
```

New (from registry_allowlist.json via PolicyResources.shared.registryAllowlist):
```
["HKEY_CURRENT_USER\\Software\\Wine",
 "HKEY_CURRENT_USER\\Software\\",
 "HKEY_LOCAL_MACHINE\\Software\\Wine",
 "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\DirectX"]
```

The new list is strictly more specific. Any registry record that matched under the old list (e.g. `HKEY_CURRENT_USER\Foo`) will now be dropped unless it starts with `HKEY_CURRENT_USER\Software\`. This is the intended unification — agents should only be allowed to set Wine-relevant registry paths.

## Self-Check: PASSED

- `PolicyResources.shared.systemPrompt` in AIService.swift: FOUND
- `PolicyResources.shared.envAllowlist` in ConfigTools.swift: FOUND
- `PolicyResources.shared.registryAllowlist` in CollectiveMemoryService.swift: FOUND
- `PolicyResources.shared.engineDefinitions` in EngineRegistry.swift: FOUND
- `PolicyResources.shared.dllRegistry` in KnownDLLRegistry.swift: FOUND
- `PolicyResources.shared.toolSchemas` in AgentToolName.swift: FOUND
- Commit 88796a6: FOUND
- Commit 8cf8ce9: FOUND
- `grep -rn 'allowedEnvKeys: Set<String> = \[' Sources/cellar`: 0 matches
- `grep -rn 'static let registry: \[KnownDLL\] = \[' Sources/cellar`: 0 matches
- `grep -rn 'static let engines: \[EngineDefinition\] = \[' Sources/cellar`: 0 matches
- `let systemPrompt = """` remaining in AIService: 2 (diagnose + recipe short prompts — correct)

---
*Phase: 43-extract-agent-policy-data-to-versioned-resources-and-achieve-provider-parity-for-tool-use-across-anthropic-deepseek-and-kimi*
*Completed: 2026-05-03*

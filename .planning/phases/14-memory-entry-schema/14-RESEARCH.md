# Phase 14: Memory Entry Schema - Research

**Researched:** 2026-03-30
**Domain:** Swift Codable schema design, SHA-256 hashing, JSON forward-compatibility
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Entry fields:**
- Minimal entry: working config + environment fingerprint + reasoning summary + metadata (no full SuccessRecord mirror)
- WorkingConfig contains: environment vars, DLL overrides, registry edits, launch args, setup deps
- Reasoning is a single summary string (natural language paragraph), not a structured step array
- Engine and graphicsApi included as optional top-level fields (enables cross-game matching in Phase 15)
- Game file is a flat JSON array of entries — no grouping by environment hash in the file structure
- Entries include: schemaVersion, gameId (slug), gameName, config, environment, environmentHash, reasoning, engine?, graphicsApi?, confirmations, lastConfirmed

**Game ID strategy:**
- Slugified game name: lowercase, strip special chars, hyphens for spaces, collapse multiples
- Slugify function owned by the schema module (not reusing GameEntry.id which is user-local)
- File path: `entries/{slug}.json`
- Collisions accepted — entries differentiated by environment fingerprint, not filename
- gameName field preserves original display name alongside the slug

**Forward compatibility:**
- Integer schemaVersion per entry (matches SuccessRecord pattern), starting at 1
- Unknown fields silently ignored by Swift JSONDecoder (default behavior, SCHM-03 satisfied)
- Entries with higher schemaVersion still used if all required v1 fields decode — schemaVersion is informational, not a gate
- Bump version only when adding new required fields; optional fields added freely

**Environment fingerprint:**
- 4 fields: arch (arm64/x86_64), wineVersion, macosVersion, wineFlavor
- Full version strings stored (e.g., "9.0.2" not "9.0") — precision retained, Phase 15 agent reasoning handles compatibility judgment
- SHA-256 hash (16-char hex prefix) of sorted canonical fields for dedup (stored as environmentHash)
- Static factory method `EnvironmentFingerprint.current(wineVersion:wineFlavor:)` captures arch and macOS version automatically
- Canonical format: `"arch=arm64|macosVersion=15.3.1|wineFlavor=game-porting-toolkit|wineVersion=9.0.2"` (sorted keys, pipe-separated)

### Claude's Discretion

- Exact field naming conventions (camelCase Swift vs snake_case JSON via CodingKeys)
- Whether to use a single file or separate files for types (CollectiveMemoryEntry.swift vs split)
- Hash truncation length (16 hex chars recommended but flexible)
- Test approach for round-trip encoding/decoding

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 14 is a pure schema-definition phase: create Swift types for the collective memory entry, establish how game IDs are slugified for filenames, and implement a static environment fingerprint factory. No GitHub I/O is involved — everything is data modelling and local computation.

The project already establishes the key patterns: `SuccessRecord` in `SuccessDatabase.swift` is the structural model to follow for `CollectiveMemoryEntry`, `GitHubModels.swift` demonstrates CodingKeys-based snake_case JSON mapping, and `Security.framework` (already imported) can provide SHA-256 via `CC_SHA256` from CommonCrypto or via `CryptoKit`. Since no new SPM dependencies are allowed per v1.2 roadmap decisions, the hash must use a system framework.

The three success criteria map cleanly to three implementation tasks: (1) define types and verify round-trip, (2) define `entries/{slug}.json` file structure (flat array), and (3) verify unknown-field tolerance via Swift's default `JSONDecoder` behavior.

**Primary recommendation:** Model `CollectiveMemoryEntry.swift` after `SuccessRecord` — single file containing all sub-types, snake_case JSON via CodingKeys, schemaVersion as `Int`, and `EnvironmentFingerprint.current()` as a static factory. Use `CryptoKit.SHA256` for hashing (available on macOS 10.15+; project targets macOS 14).

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCHM-01 | Collective memory entry stores working config, agent reasoning chain, and environment fingerprint (Wine version, macOS version, CPU arch, wine flavor) | `CollectiveMemoryEntry` struct with `WorkingConfig`, `EnvironmentFingerprint`, and `reasoning: String` fields; `EnvironmentFingerprint.current(wineVersion:wineFlavor:)` static factory |
| SCHM-02 | Each game has one JSON file (`entries/{game-id}.json`) containing an array of entries from different agents/environments | `slugify(_:)` function produces deterministic game ID; file is a flat `[CollectiveMemoryEntry]` JSON array |
| SCHM-03 | Entry includes schema version field for forward-compatible evolution | `schemaVersion: Int` field + Swift `JSONDecoder` ignores unknown keys by default (verified behavior) |
</phase_requirements>

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Foundation | macOS 14+ | `Codable`, `JSONEncoder`/`JSONDecoder`, `ProcessInfo` | Already used everywhere in project |
| CryptoKit | macOS 10.15+ (system) | SHA-256 hash for `environmentHash` | No new SPM dep; `import CryptoKit` only; available on project's minimum platform |
| Security.framework | system | Already imported in `GitHubAuthService.swift` | Alternative hash path via `CC_SHA256` if CryptoKit unavailable, but CryptoKit preferred |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| swift-testing | 0.12.0 (already in Package.swift) | `@Test`, `@Suite`, `#expect` for round-trip tests | All new tests in this phase |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CryptoKit.SHA256 | CommonCrypto CC_SHA256 | CommonCrypto is C API, more verbose; CryptoKit is idiomatic Swift and already on target platform |
| Single CollectiveMemoryEntry.swift | Split files per type | Keeping in one file matches SuccessDatabase.swift pattern (all related types colocated); easier for Phase 15/16 consumers to import |

**Installation:** No new dependencies — all imports are system frameworks or already in Package.swift.

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/cellar/Models/
├── CollectiveMemoryEntry.swift   # All schema types: CollectiveMemoryEntry,
│                                 # WorkingConfig, EnvironmentFingerprint,
│                                 # slugify(), EnvironmentFingerprint.current()
Tests/cellarTests/
└── CollectiveMemoryEntryTests.swift  # Round-trip, unknown-field, slugify tests
```

### Pattern 1: Codable Struct with CodingKeys (established project pattern)

**What:** Swift structs conform to `Codable` with an explicit `CodingKeys` enum mapping camelCase Swift properties to snake_case JSON keys.

**When to use:** All serialized model types in this project — consistent with `GitHubModels.swift`, `SuccessRecord`, `GameEntry`.

**Example (from existing `GitHubModels.swift`):**
```swift
struct GitHubAppConfig: Codable {
    let appID: String
    let installationID: String

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case installationID = "installation_id"
    }
}
```

**Apply to `CollectiveMemoryEntry`:**
```swift
struct CollectiveMemoryEntry: Codable {
    let schemaVersion: Int          // = 1
    let gameId: String              // slug, e.g. "cossacks-european-wars"
    let gameName: String            // display name, e.g. "Cossacks: European Wars"
    let config: WorkingConfig
    let environment: EnvironmentFingerprint
    let environmentHash: String     // 16-char hex prefix of SHA-256
    let reasoning: String           // natural language paragraph from agent
    let engine: String?
    let graphicsApi: String?
    let confirmations: Int          // starts at 1, incremented by Phase 16
    let lastConfirmed: String       // ISO 8601 string

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case gameId = "game_id"
        case gameName = "game_name"
        case config
        case environment
        case environmentHash = "environment_hash"
        case reasoning
        case engine
        case graphicsApi = "graphics_api"
        case confirmations
        case lastConfirmed = "last_confirmed"
    }
}
```

### Pattern 2: schemaVersion as Int (matches SuccessRecord)

**What:** `schemaVersion: Int` stored in every entry. Starting at 1. Bumped only when adding required fields.

**Existing precedent (from `SuccessDatabase.swift`):**
```swift
struct SuccessRecord: Codable {
    let schemaVersion: Int       // 1
    // ...
}
```

**Key behavior:** `JSONDecoder` does not use `schemaVersion` as a decoding gate — it simply decodes what fields exist. Entries with unknown future fields decode fine (ignored by default). Entries from older schema with missing optional fields decode fine (Swift optional = nil). This satisfies SCHM-03 without any custom decode logic.

### Pattern 3: WorkingConfig (subset of SuccessRecord fields)

**What:** A focused subset of the working configuration — enough to recreate the launch without the full SuccessRecord detail.

```swift
struct WorkingConfig: Codable {
    let environment: [String: String]       // env vars (e.g. WINEDLLOVERRIDES)
    let dllOverrides: [DLLOverrideRecord]   // reuse existing type from SuccessDatabase.swift
    let registry: [RegistryRecord]          // reuse existing type
    let launchArgs: [String]
    let setupDeps: [String]                 // winetricks verbs installed

    enum CodingKeys: String, CodingKey {
        case environment
        case dllOverrides = "dll_overrides"
        case registry
        case launchArgs = "launch_args"
        case setupDeps = "setup_deps"
    }
}
```

**Note:** `DLLOverrideRecord` and `RegistryRecord` already exist in `SuccessDatabase.swift`. Reuse them directly — no duplication needed.

### Pattern 4: EnvironmentFingerprint with static factory

**What:** A Codable struct for the 4-field environment identity, plus a static factory that captures system info automatically.

```swift
struct EnvironmentFingerprint: Codable {
    let arch: String            // "arm64" or "x86_64"
    let wineVersion: String     // e.g. "9.0.2"
    let macosVersion: String    // e.g. "15.3.1"
    let wineFlavor: String      // e.g. "game-porting-toolkit" or "wine-stable"

    enum CodingKeys: String, CodingKey {
        case arch
        case wineVersion = "wine_version"
        case macosVersion = "macos_version"
        case wineFlavor = "wine_flavor"
    }

    /// Canonical string for hashing: sorted keys, pipe-separated.
    var canonicalString: String {
        "arch=\(arch)|macosVersion=\(macosVersion)|wineFlavor=\(wineFlavor)|wineVersion=\(wineVersion)"
    }

    /// Detect arch and macOS version from the running system.
    /// wineVersion and wineFlavor are passed in from WineProcess (already known at call site).
    static func current(wineVersion: String, wineFlavor: String) -> EnvironmentFingerprint {
        let arch = detectArch()          // "arm64" or "x86_64"
        let macosVersion = detectMacOS() // e.g. "15.3.1"
        return EnvironmentFingerprint(
            arch: arch,
            wineVersion: wineVersion,
            macosVersion: macosVersion,
            wineFlavor: wineFlavor
        )
    }
}
```

### Pattern 5: SHA-256 hash via CryptoKit

**What:** Compute the `environmentHash` from the fingerprint's canonical string.

```swift
import CryptoKit

extension EnvironmentFingerprint {
    /// Returns a 16-character hex prefix of the SHA-256 of the canonical string.
    func computeHash() -> String {
        let data = Data(canonicalString.utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }
}
```

**Why CryptoKit:** Available on macOS 10.15+, project targets macOS 14. No new SPM dependency. Idiomatic Swift API. `SHA256.hash(data:)` is a one-liner.

**Important:** `import CryptoKit` added only to `CollectiveMemoryEntry.swift`. No changes to `Package.swift`.

### Pattern 6: slugify() function

**What:** Deterministic game-name-to-slug conversion. Must produce identical output on all machines given the same input string.

```swift
/// Convert a game display name to a filesystem-safe slug.
/// "Cossacks: European Wars" → "cossacks-european-wars"
/// Rules: lowercase, replace non-alphanumeric with hyphens, collapse runs, strip leading/trailing
func slugify(_ name: String) -> String {
    name
        .lowercased()
        .unicodeScalars
        .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
        .joined()
        .components(separatedBy: "-")
        .filter { !$0.isEmpty }
        .joined(separator: "-")
}
```

**Critical property:** Deterministic — same input always produces same output. Uses only ASCII-safe operations. No locale dependency.

### Pattern 7: arch detection

**What:** Get the current process architecture without shell subprocess.

```swift
private static func detectArch() -> String {
    #if arch(arm64)
    return "arm64"
    #else
    return "x86_64"
    #endif
}
```

**Why compile-time:** `#if arch(arm64)` is a compile-time check. On Apple Silicon running native arm64 binary it returns "arm64". On Intel or Rosetta2 it returns "x86_64". This matches the Wine process behavior (Rosetta runs as x86_64).

**Why not `uname -m`:** Subprocess overhead unnecessary; compile-time check is faster, simpler, and more reliable.

### Pattern 8: macOS version detection

**What:** Get the running macOS version string.

```swift
private static func detectMacOS() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}
```

**Source:** `ProcessInfo.processInfo.operatingSystemVersion` is the standard Foundation API for macOS version detection. Returns `OperatingSystemVersion` struct with `majorVersion`, `minorVersion`, `patchVersion` components.

### Anti-Patterns to Avoid

- **Mirroring full SuccessRecord fields in WorkingConfig:** Out of scope per user decisions. WorkingConfig is minimal — only what's needed for Phase 15 context injection.
- **Treating schemaVersion as a decoding gate:** Do NOT add `init(from:)` that throws on version mismatch. The user decided schemaVersion is informational only — old code reads new entries, new code reads old entries.
- **Using `GameEntry.id` as the game slug:** User decided: slugify is owned by the schema module. GameEntry.id is user-local and may differ from the community slug.
- **Subprocess for arch detection:** `uname -m` via `Process` adds launch overhead and failure modes. Use `#if arch()` compiler directive instead.
- **Grouping entries by environment hash in the JSON file:** Out of scope. File structure is a flat `[CollectiveMemoryEntry]` array.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON encoding/decoding | Custom serializer | `Swift Codable` + `JSONEncoder`/`JSONDecoder` | Handles optional fields, unknown keys, type coercion automatically |
| SHA-256 | Custom hash implementation | `CryptoKit.SHA256` | Cryptographically correct; one-liner API; system framework |
| Unknown field tolerance | Custom `init(from:)` decoder | Default `JSONDecoder` behavior | Swift JSONDecoder ignores unknown keys by default — zero code needed |
| macOS version | Shell `sw_vers` | `ProcessInfo.processInfo.operatingSystemVersion` | No subprocess; built-in Foundation API |

**Key insight:** Swift's `JSONDecoder` is already forward-compatible out of the box. No custom decode logic is needed for SCHM-03 — just declare optional fields as `Optional` and required fields as non-optional.

---

## Common Pitfalls

### Pitfall 1: CodingKeys completeness
**What goes wrong:** Adding a new field to the struct but forgetting to add it to `CodingKeys` — the field gets silently dropped from JSON output (uses `codingKey.stringValue` which defaults to property name, but if any `CodingKeys` case is missing the entire custom enum applies and missing cases fall back to property name only if the enum is exhaustive).
**Why it happens:** Swift requires `CodingKeys` to be exhaustive if declared — but if you declare it, ALL keys must be present.
**How to avoid:** Every property in the struct must have a corresponding case in the `CodingKeys` enum. Add them in parallel.
**Warning signs:** Round-trip test shows decoded value has nil for a field that was set.

### Pitfall 2: JSONDecoder and unknown fields (SCHM-03 is free)
**What goes wrong:** Developer adds custom `init(from:)` to "handle" unknown fields, inadvertently breaking the default ignore behavior.
**Why it happens:** Misunderstanding Swift's default behavior.
**How to avoid:** Do NOT override `init(from:)`. The default synthesized Codable implementation already ignores unknown keys. SCHM-03 is satisfied with zero custom code.
**Verification:** Add a test that decodes a JSON string with extra fields — it must not throw.

### Pitfall 3: Slugify non-determinism
**What goes wrong:** Slug differs across machines due to locale-sensitive string operations (e.g., `lowercased()` with locale, locale-dependent regex).
**Why it happens:** Some string APIs are locale-sensitive by default.
**How to avoid:** Use `.lowercased()` without locale parameter (uses root locale in Swift String). Use `unicodeScalars` character iteration and `CharacterSet.alphanumerics` for class matching. Avoid `NSRegularExpression` with locale flags.
**Warning signs:** Game "Château" produces different slugs on French vs English locale settings.

### Pitfall 4: Hash collisions in environmentHash prefix
**What goes wrong:** Two different environments produce the same 16-char hex prefix.
**Why it happens:** 16 hex chars = 64 bits of collision resistance. Probability of collision among <1000 entries is negligible (birthday attack at ~4 billion pairs). Not a real concern at project scale.
**How to avoid:** 16 chars is fine. User confirmed this is acceptable. Document it.

### Pitfall 5: `confirmations` field semantics
**What goes wrong:** Phase 14 creates the schema with `confirmations: Int`. Phase 16 increments it. If Phase 14 initializes it to 0, the first writer must set it to 1. If Phase 14 initializes to 1, the semantics are "this entry represents 1 confirmed working config."
**How to avoid:** Initialize `confirmations` to `1` at entry creation (Phase 16). The schema just stores it as `Int` with no minimum constraint.

---

## Code Examples

Verified patterns from existing project codebase:

### Encoder configuration (from SuccessDatabase.swift)
```swift
// Source: Sources/cellar/Core/SuccessDatabase.swift:103
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(record)
```
Use the same `[.prettyPrinted, .sortedKeys]` configuration for collective memory entries — human-readable files in the community repo.

### Decoder usage (from SuccessDatabase.swift)
```swift
// Source: Sources/cellar/Core/SuccessDatabase.swift:93
return try? JSONDecoder().decode(SuccessRecord.self, from: data)
```
Plain `JSONDecoder()` with no special configuration — this is the forward-compatible pattern.

### Decoding an array (for the entries/{slug}.json file structure)
```swift
// Phase 15 will use this pattern:
let entries = try JSONDecoder().decode([CollectiveMemoryEntry].self, from: data)
```

### swift-testing round-trip test pattern (from EngineRegistryTests.swift)
```swift
// Source: Tests/cellarTests/EngineRegistryTests.swift
import Testing
@testable import cellar

@Suite("CollectiveMemoryEntry Tests")
struct CollectiveMemoryEntryTests {

    @Test("CollectiveMemoryEntry round-trips through JSON encode/decode")
    func roundTripEncoding() throws {
        let entry = CollectiveMemoryEntry(
            schemaVersion: 1,
            gameId: "cossacks-european-wars",
            gameName: "Cossacks: European Wars",
            // ... all fields ...
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        let decoded = try JSONDecoder().decode(CollectiveMemoryEntry.self, from: data)
        #expect(decoded.gameId == entry.gameId)
        #expect(decoded.environmentHash == entry.environmentHash)
        // ... etc
    }
}
```

### CryptoKit SHA-256 (system framework, macOS 10.15+)
```swift
import CryptoKit

let data = Data("arch=arm64|macosVersion=15.3.1|wineFlavor=game-porting-toolkit|wineVersion=9.0.2".utf8)
let digest = SHA256.hash(data: data)
let hex = digest.map { String(format: "%02x", $0) }.joined()
let prefix16 = String(hex.prefix(16))
// prefix16 = deterministic 16-char hex string
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual JSON serialization | Swift Codable (synthesized) | Swift 4 (2017) | Zero boilerplate for simple structs |
| CommonCrypto C API | CryptoKit Swift API | macOS 10.15 (2019) | Type-safe, idiomatic, one-liner SHA-256 |

**Deprecated/outdated:**
- CommonCrypto (`CC_SHA256`): Still works, but CryptoKit is the preferred Swift API for new code on macOS 10.15+. Project targets macOS 14 so CryptoKit is fully available.

---

## Open Questions

1. **Which file should `DLLOverrideRecord` and `RegistryRecord` live in after this phase?**
   - What we know: They currently live in `SuccessDatabase.swift`. `WorkingConfig` will reference them.
   - What's unclear: Should they stay in `SuccessDatabase.swift` (shared) or be duplicated/moved to `CollectiveMemoryEntry.swift`?
   - Recommendation: Keep them in `SuccessDatabase.swift` and import via `@testable import cellar`. No duplication. Both files are in the same module.

2. **`confirmations` field: stored in the community repo as read-only from Phase 14's perspective?**
   - What we know: Phase 14 defines the schema. Phase 16 writes entries (initially `confirmations: 1`). Phase 16 also does dedup (increments to 2+ if same env hash already exists).
   - What's unclear: Should Phase 14's schema include a `confirmedBy: [String]?` field for Phase 16's dedup logic?
   - Recommendation: Keep it simple — `confirmations: Int` only. Phase 16 can add `confirmedBy` in a schema bump if needed. Don't anticipate Phase 16 requirements in Phase 14.

---

## Validation Architecture

> `workflow.nyquist_validation` not present in `.planning/config.json` — section included per standard research format using detected test infrastructure.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | swift-testing 0.12.0 |
| Config file | Package.swift (testTarget "cellarTests" with Testing dependency) |
| Quick run command | `swift test --filter CollectiveMemoryEntry` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCHM-01 | `CollectiveMemoryEntry` encodes/decodes all fields (config, reasoning, environment fingerprint) intact | unit | `swift test --filter CollectiveMemoryEntryTests/roundTripEncoding` | ❌ Wave 0 |
| SCHM-02 | `slugify()` produces deterministic slug; same input = same output; special chars handled | unit | `swift test --filter CollectiveMemoryEntryTests/slugifyDeterministic` | ❌ Wave 0 |
| SCHM-03 | `JSONDecoder` decodes entry with extra unknown fields without error | unit | `swift test --filter CollectiveMemoryEntryTests/unknownFieldsIgnored` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `swift test --filter CollectiveMemoryEntry`
- **Per wave merge:** `swift test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `Tests/cellarTests/CollectiveMemoryEntryTests.swift` — covers SCHM-01, SCHM-02, SCHM-03

*(No framework install needed — swift-testing already in Package.swift)*

---

## Sources

### Primary (HIGH confidence)
- Project codebase: `Sources/cellar/Core/SuccessDatabase.swift` — SuccessRecord Codable pattern, schemaVersion, JSONEncoder config
- Project codebase: `Sources/cellar/Models/GitHubModels.swift` — CodingKeys snake_case mapping pattern
- Project codebase: `Sources/cellar/Persistence/CellarPaths.swift` — `defaultMemoryRepo` constant
- Project codebase: `Tests/cellarTests/EngineRegistryTests.swift` — swift-testing pattern in use
- Project codebase: `Package.swift` — swift-testing 0.12.0 already present; CryptoKit available on macOS 14 target
- Apple Documentation: `ProcessInfo.operatingSystemVersion` — standard macOS version detection (Foundation API, stable)
- Swift Language Reference: `#if arch(arm64)` — compile-time architecture check (stable since Swift 1)
- Swift Language Reference: Synthesized `Codable` ignores unknown keys by default (stable since Swift 4)

### Secondary (MEDIUM confidence)
- CryptoKit availability on macOS 10.15+ — confirmed by Apple platform availability; project targets macOS 14 so no floor issues

### Tertiary (LOW confidence)
- None — all claims verified from codebase or official platform documentation

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; everything verified in project codebase and Apple system framework docs
- Architecture: HIGH — directly modelled on existing project patterns (`SuccessRecord`, `GitHubModels`)
- Pitfalls: HIGH — derived from known Swift Codable behaviors and project codebase review

**Research date:** 2026-03-30
**Valid until:** 2026-05-30 (stable APIs — Swift Codable and CryptoKit are long-term stable)

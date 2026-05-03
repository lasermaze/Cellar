import Foundation

// MARK: - PolicyError

enum PolicyError: Error, CustomStringConvertible {
    case missingResource(String)
    case schemaVersionMismatch(file: String, expected: Int, got: Int)
    case malformedFrontmatter(String)
    case decodingError(file: String, underlying: Error)

    var description: String {
        switch self {
        case .missingResource(let path):
            return "PolicyResources: missing required resource '\(path)'"
        case .schemaVersionMismatch(let file, let expected, let got):
            return "PolicyResources: schema version mismatch in '\(file)' — expected \(expected), got \(got)"
        case .malformedFrontmatter(let detail):
            return "PolicyResources: malformed YAML frontmatter — \(detail)"
        case .decodingError(let file, let underlying):
            return "PolicyResources: failed to decode '\(file)': \(underlying)"
        }
    }
}

// MARK: - Frontmatter Parser (internal for tests)

/// Parse `---\nschema_version: N\n---\nbody` markdown frontmatter.
/// Returns `(schemaVersion, body)`.
/// Throws `PolicyError.malformedFrontmatter` on any structural issue.
func parsePolicyFrontmatter(_ raw: String) throws -> (version: Int, body: String) {
    let lines = raw.components(separatedBy: "\n")
    guard lines.first == "---" else {
        throw PolicyError.malformedFrontmatter("document must begin with '---'")
    }
    // Find closing ---
    guard let closeIndex = lines.dropFirst().firstIndex(of: "---") else {
        throw PolicyError.malformedFrontmatter("no closing '---' found")
    }
    // Scan frontmatter lines between opening and closing ---
    let frontmatterLines = lines[1..<closeIndex]
    var version: Int?
    for line in frontmatterLines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("schema_version:") {
            let valueStr = trimmed.dropFirst("schema_version:".count)
                .trimmingCharacters(in: .whitespaces)
            if let v = Int(valueStr) {
                version = v
            } else {
                throw PolicyError.malformedFrontmatter("schema_version is not an integer: '\(valueStr)'")
            }
        }
    }
    guard let parsedVersion = version else {
        throw PolicyError.malformedFrontmatter("schema_version key not found in frontmatter")
    }
    let bodyLines = lines[(closeIndex + 1)...]
    let body = bodyLines.joined(separator: "\n")
    return (parsedVersion, body)
}

// MARK: - Private File-Level Decodable Structs

// These are intentionally separate from the runtime types (EngineDefinition, KnownDLL, etc.)
// so we do NOT add Codable conformance to existing structs. Mapping is local to this file.

private struct EnginesFile: Decodable {
    let schema_version: Int
    let engines: [EngineDefinitionFile]
}

private struct EngineDefinitionFile: Decodable {
    let name: String
    let family: String
    let file_patterns: [String]
    let pe_import_signals: [String]
    let string_signatures: [String]
    let typical_graphics_api: String?
}

private struct DLLRegistryFile: Decodable {
    let schema_version: Int
    let dlls: [KnownDLLFile]
}

private struct CompanionFileRecord: Decodable {
    let filename: String
    let content: String
}

private struct KnownDLLFile: Decodable {
    let name: String
    let dll_file_name: String
    let github_owner: String
    let github_repo: String
    let asset_pattern: String
    let description: String
    let required_overrides: [String: String]
    let companion_files: [CompanionFileRecord]
    let preferred_target: String   // camelCase case name of DLLPlacementTarget
    let is_system_dll: Bool
    let variants: [String: String]
}

private struct EnvAllowlistFile: Decodable {
    let schema_version: Int
    let allowed_keys: [String]
}

private struct RegistryAllowlistFile: Decodable {
    let schema_version: Int
    let allowed_prefixes: [String]
}

private struct ToolSchemasFile: Decodable {
    let schema_version: Int
    let schemas: [String: JSONValue]
}

// MARK: - Private helpers for versioned JSON decoding

private struct PolicyVersionProbe: Decodable { let schema_version: Int }

// MARK: - PolicyResources

struct PolicyResources: @unchecked Sendable {
    let systemPrompt: String
    let engineDefinitions: [EngineDefinition]
    let dllRegistry: [KnownDLL]
    let envAllowlist: Set<String>
    let registryAllowlist: [String]
    let toolSchemas: [String: JSONValue]

    // MARK: Shared singleton — fail loud at startup

    static let shared: PolicyResources = {
        do { return try PolicyResources() }
        catch { fatalError("PolicyResources failed to load: \(error)") }
    }()

    // MARK: Internal init (throws) used by shared and tests

    init() throws {
        let policyDir = try PolicyResources.resolvedPolicyDirectory()

        // 1. system_prompt.md
        let promptURL = policyDir.appendingPathComponent("system_prompt.md")
        guard FileManager.default.fileExists(atPath: promptURL.path) else {
            throw PolicyError.missingResource("policy/system_prompt.md")
        }
        let rawPrompt: String
        do {
            rawPrompt = try String(contentsOf: promptURL, encoding: .utf8)
        } catch {
            throw PolicyError.decodingError(file: "policy/system_prompt.md", underlying: error)
        }
        let (promptVersion, promptBody) = try parsePolicyFrontmatter(rawPrompt)
        guard promptVersion == 1 else {
            throw PolicyError.schemaVersionMismatch(file: "policy/system_prompt.md", expected: 1, got: promptVersion)
        }
        self.systemPrompt = promptBody

        // 2. engines.json
        let enginesFile: EnginesFile = try PolicyResources.loadVersionedJSON(
            at: policyDir.appendingPathComponent("engines.json"),
            name: "policy/engines.json",
            expectedVersion: 1
        )
        self.engineDefinitions = enginesFile.engines.map { file in
            EngineDefinition(
                name: file.name,
                family: file.family,
                filePatterns: file.file_patterns,
                peImportSignals: file.pe_import_signals,
                stringSignatures: file.string_signatures,
                typicalGraphicsApi: file.typical_graphics_api
            )
        }

        // 3. engine_dll_registry.json
        let dllFile: DLLRegistryFile = try PolicyResources.loadVersionedJSON(
            at: policyDir.appendingPathComponent("engine_dll_registry.json"),
            name: "policy/engine_dll_registry.json",
            expectedVersion: 1
        )
        self.dllRegistry = dllFile.dlls.map { file in
            let target: DLLPlacementTarget
            switch file.preferred_target {
            case "syswow64": target = .syswow64
            case "system32": target = .system32
            default:         target = .gameDir
            }
            return KnownDLL(
                name: file.name,
                dllFileName: file.dll_file_name,
                githubOwner: file.github_owner,
                githubRepo: file.github_repo,
                assetPattern: file.asset_pattern,
                description: file.description,
                requiredOverrides: file.required_overrides,
                companionFiles: file.companion_files.map {
                    CompanionFile(filename: $0.filename, content: $0.content)
                },
                preferredTarget: target,
                isSystemDLL: file.is_system_dll,
                variants: file.variants
            )
        }

        // 4. env_allowlist.json
        let envFile: EnvAllowlistFile = try PolicyResources.loadVersionedJSON(
            at: policyDir.appendingPathComponent("env_allowlist.json"),
            name: "policy/env_allowlist.json",
            expectedVersion: 1
        )
        self.envAllowlist = Set(envFile.allowed_keys)

        // 5. registry_allowlist.json
        let regFile: RegistryAllowlistFile = try PolicyResources.loadVersionedJSON(
            at: policyDir.appendingPathComponent("registry_allowlist.json"),
            name: "policy/registry_allowlist.json",
            expectedVersion: 1
        )
        self.registryAllowlist = regFile.allowed_prefixes

        // 6. tool_schemas.json
        let schemasFile: ToolSchemasFile = try PolicyResources.loadVersionedJSON(
            at: policyDir.appendingPathComponent("tool_schemas.json"),
            name: "policy/tool_schemas.json",
            expectedVersion: 1
        )
        self.toolSchemas = schemasFile.schemas
    }

    // MARK: - Internal helpers (exposed for unit tests)

    /// Load and decode a versioned JSON file from a URL. Throws on missing file,
    /// decode failure, or schema_version mismatch.
    static func loadVersionedJSON<T: Decodable>(
        at url: URL,
        name: String,
        expectedVersion: Int
    ) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PolicyError.missingResource(name)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PolicyError.decodingError(file: name, underlying: error)
        }
        return try decodeVersionedData(data, name: name, expectedVersion: expectedVersion)
    }

    /// Decode versioned JSON from raw Data. Exposed separately so tests can inject synthetic data.
    static func decodeVersionedData<T: Decodable>(
        _ data: Data,
        name: String,
        expectedVersion: Int
    ) throws -> T {
        // First decode just the version wrapper to check schema_version
        let probe: PolicyVersionProbe
        do {
            probe = try JSONDecoder().decode(PolicyVersionProbe.self, from: data)
        } catch {
            throw PolicyError.decodingError(file: name, underlying: error)
        }
        guard probe.schema_version == expectedVersion else {
            throw PolicyError.schemaVersionMismatch(file: name, expected: expectedVersion, got: probe.schema_version)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PolicyError.decodingError(file: name, underlying: error)
        }
    }

    /// Test hook: load env allowlist from raw Data (bypasses Bundle lookup).
    @discardableResult
    static func _loadVersionedEnvAllowlist(from data: Data, expectedVersion: Int) throws -> Set<String> {
        let file: EnvAllowlistFile = try decodeVersionedData(
            data,
            name: "policy/env_allowlist.json",
            expectedVersion: expectedVersion
        )
        return Set(file.allowed_keys)
    }

    // MARK: - Private: Bundle path resolution

    /// Resolve the `policy/` directory within Bundle.module.
    ///
    /// SPM `.copy("Resources")` behaviour varies by build context:
    /// - In the main binary: `resourcePath` = `<bundle>`, files at `<bundle>/Resources/policy/`
    /// - In the test binary: `resourcePath` = `<bundle>/Resources`, files at `<bundle>/Resources/policy/`
    ///
    /// We try both layouts so both contexts work.
    private static func resolvedPolicyDirectory() throws -> URL {
        guard let resourcePath = Bundle.module.resourcePath else {
            throw PolicyError.missingResource("Bundle.module.resourcePath is nil")
        }
        let base = URL(fileURLWithPath: resourcePath)

        // Layout A: resourcePath already IS the Resources/ dir (test target)
        let directCandidate = base.appendingPathComponent("policy")
        if FileManager.default.fileExists(atPath: directCandidate.path) {
            return directCandidate
        }

        // Layout B: resourcePath is the bundle root, files at <bundle>/Resources/policy/
        let nestedCandidate = base
            .appendingPathComponent("Resources")
            .appendingPathComponent("policy")
        if FileManager.default.fileExists(atPath: nestedCandidate.path) {
            return nestedCandidate
        }

        throw PolicyError.missingResource(
            "policy/ directory not found in Bundle.module (tried \(directCandidate.path) and \(nestedCandidate.path))"
        )
    }
}

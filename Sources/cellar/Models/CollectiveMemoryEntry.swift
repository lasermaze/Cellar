import Foundation
import CryptoKit

// MARK: - Working Config

/// Environment variables, DLL overrides, registry edits, launch args, and setup deps
/// that constitute a working game configuration.
struct WorkingConfig: Codable {
    var environment: [String: String]
    var dllOverrides: [DLLOverrideRecord]
    var registry: [RegistryRecord]
    var launchArgs: [String]
    var setupDeps: [String]

    enum CodingKeys: String, CodingKey {
        case environment
        case dllOverrides = "dll_overrides"
        case registry
        case launchArgs = "launch_args"
        case setupDeps = "setup_deps"
    }
}

// MARK: - Environment Fingerprint

/// Captures the Wine + macOS environment in which a config was verified to work.
struct EnvironmentFingerprint: Codable {
    let arch: String
    let wineVersion: String
    let macosVersion: String
    let wineFlavor: String

    enum CodingKeys: String, CodingKey {
        case arch
        case wineVersion = "wine_version"
        case macosVersion = "macos_version"
        case wineFlavor = "wine_flavor"
    }

    /// Sorted-key canonical string used as SHA-256 input.
    var canonicalString: String {
        "arch=\(arch)|macosVersion=\(macosVersion)|wineFlavor=\(wineFlavor)|wineVersion=\(wineVersion)"
    }

    /// Returns the first 16 hex characters of the SHA-256 hash of the canonical string.
    func computeHash() -> String {
        let data = Data(canonicalString.utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    /// Factory that detects the current arch and macOS version automatically.
    static func current(wineVersion: String, wineFlavor: String) -> EnvironmentFingerprint {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif

        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let macosVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        return EnvironmentFingerprint(
            arch: arch,
            wineVersion: wineVersion,
            macosVersion: macosVersion,
            wineFlavor: wineFlavor
        )
    }
}

// MARK: - Collective Memory Entry

/// A shared collective memory entry describing a working Wine configuration for a specific game
/// in a specific environment. Stored as entries/{gameId}.json in the collective memory repo.
struct CollectiveMemoryEntry: Codable {
    let schemaVersion: Int
    let gameId: String
    let gameName: String
    let config: WorkingConfig
    let environment: EnvironmentFingerprint
    let environmentHash: String
    let reasoning: String
    let engine: String?
    let graphicsApi: String?
    let confirmations: Int
    let lastConfirmed: String

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

// MARK: - slugify

/// Converts a game display name into a deterministic, filesystem-safe slug.
/// Example: "Cossacks: European Wars" -> "cossacks-european-wars"
func slugify(_ input: String) -> String {
    // Use unicodeScalars to avoid locale-sensitive APIs
    let lowercased = input.lowercased()
    var result = ""
    var lastWasHyphen = false

    for scalar in lowercased.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            result.append(Character(scalar))
            lastWasHyphen = false
        } else {
            if !lastWasHyphen && !result.isEmpty {
                result.append("-")
                lastWasHyphen = true
            }
        }
    }

    // Strip trailing hyphen
    while result.hasSuffix("-") {
        result.removeLast()
    }

    return result
}

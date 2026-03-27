import Foundation

struct Recipe: Codable {
    let id: String
    let name: String
    let version: String
    let source: String
    let executable: String
    let wineTested: String?
    let environment: [String: String]
    let registry: [RegistryEntry]
    let launchArgs: [String]
    let notes: String?

    // New optional fields (AGENT-12) — backward-compatible, existing JSON loads without modification
    let setupDeps: [String]?          // winetricks verbs to install before game installer
    let installDir: String?           // expected install directory inside bottle for verification
    let retryVariants: [RetryVariant]? // alternative env configs to try on failure

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case source
        case executable
        case wineTested = "wine_tested_with"
        case environment
        case registry
        case launchArgs = "launch_args"
        case notes
        case setupDeps = "setup_deps"
        case installDir = "install_dir"
        case retryVariants = "retry_variants"
    }
}

struct RetryVariant: Codable {
    let description: String
    let environment: [String: String]
}

struct RegistryEntry: Codable {
    let description: String
    let regContent: String

    enum CodingKeys: String, CodingKey {
        case description
        case regContent = "reg_content"
    }
}

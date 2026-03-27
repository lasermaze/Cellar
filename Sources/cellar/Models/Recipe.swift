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
    }
}

struct RegistryEntry: Codable {
    let description: String
    let regContent: String

    enum CodingKeys: String, CodingKey {
        case description
        case regContent = "reg_content"
    }
}

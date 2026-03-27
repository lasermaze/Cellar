import Foundation

struct GameEntry: Codable {
    let id: String
    let name: String
    let installPath: String
    var executablePath: String?    // discovered by BottleScanner after install (AGENT-06)
    let recipeId: String?
    let addedAt: Date
    var lastLaunched: Date?
    var lastResult: LaunchResult?
}

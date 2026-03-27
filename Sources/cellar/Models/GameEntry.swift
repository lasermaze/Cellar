import Foundation

struct GameEntry: Codable {
    let id: String
    let name: String
    let installPath: String
    let recipeId: String?
    let addedAt: Date
    var lastLaunched: Date?
    var lastResult: LaunchResult?
}

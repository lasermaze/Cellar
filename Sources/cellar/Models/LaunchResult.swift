import Foundation

struct LaunchResult: Codable {
    let timestamp: Date
    let reachedMenu: Bool
    let attemptCount: Int      // how many launch attempts were made (AGENT-11)
    let diagnosis: String?     // WineErrorParser diagnosis summary if failed (AGENT-11)
}

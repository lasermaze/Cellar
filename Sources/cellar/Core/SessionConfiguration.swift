import Foundation

/// Immutable per-session context injected into AgentTools at construction.
/// Replaces the six individual constructor parameters (gameId, entry,
/// executablePath, bottleURL, wineURL, wineProcess).
struct SessionConfiguration {
    let gameId: String
    let entry: GameEntry
    let executablePath: String
    let bottleURL: URL
    let wineURL: URL
    let wineProcess: WineProcess
}

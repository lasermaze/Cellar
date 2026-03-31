import Foundation

/// Captures agent session state when a session ends without completing (budget/iterations/error).
/// Written to ~/.cellar/sessions/<gameId>.json and consumed on next launch.
struct SessionHandoff: Codable {
    let gameId: String
    let timestamp: String
    let stopReason: String
    let iterationsUsed: Int
    let estimatedCostUSD: Double
    let accumulatedEnv: [String: String]
    let installedDeps: [String]
    let launchCount: Int
    let lastStatus: String

    // MARK: - Persistence

    static func write(_ handoff: SessionHandoff) {
        do {
            try FileManager.default.createDirectory(
                at: CellarPaths.sessionsDir,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(handoff)
            try data.write(to: CellarPaths.sessionFile(for: handoff.gameId), options: .atomic)
        } catch {
            // Silent failure — handoff is best-effort
        }
    }

    static func read(gameId: String) -> SessionHandoff? {
        let url = CellarPaths.sessionFile(for: gameId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionHandoff.self, from: data)
    }

    static func delete(gameId: String) {
        try? FileManager.default.removeItem(at: CellarPaths.sessionFile(for: gameId))
    }

    // MARK: - Formatting

    /// Format the handoff as a context block for injection into the next agent's initial message.
    func formatForAgent() -> String {
        var lines: [String] = []

        lines.append("--- PREVIOUS SESSION ---")
        lines.append("A prior agent session ran for \(iterationsUsed) iterations ($\(String(format: "%.2f", estimatedCostUSD))) and stopped: \(stopReason).")
        lines.append("")

        if !accumulatedEnv.isEmpty {
            lines.append("Environment configured:")
            for (key, value) in accumulatedEnv.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key)=\(value)")
            }
            lines.append("")
        }

        if !installedDeps.isEmpty {
            lines.append("Winetricks installed: \(installedDeps.joined(separator: ", "))")
            lines.append("")
        }

        lines.append("Launches attempted: \(launchCount) of 8")
        lines.append("")

        if !lastStatus.isEmpty {
            lines.append("Last status from previous agent:")
            lines.append("  \"\(lastStatus)\"")
            lines.append("")
        }

        lines.append("DO NOT repeat approaches that already failed. Build on what was learned. The bottle already has any DLLs placed and registry entries from the previous session.")
        lines.append("--- END PREVIOUS SESSION ---")

        return lines.joined(separator: "\n")
    }
}

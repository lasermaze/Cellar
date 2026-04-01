import Foundation

/// Codable persistence model for cross-launch diagnostic tracking.
/// Stored at ~/.cellar/diagnostics/<gameId>/latest.json
struct DiagnosticRecord: Codable {
    let gameId: String
    let timestamp: String         // ISO8601
    let errorSummary: [String]    // e.g. ["graphics: DirectDraw initialization failed"]
    let successSummary: [String]
    let lastActions: [String]     // e.g. ["install_winetricks(d3dx9)"]
    let errorCount: Int
    let successCount: Int

    // MARK: - Persistence

    static func write(_ record: DiagnosticRecord) {
        do {
            try FileManager.default.createDirectory(
                at: CellarPaths.diagnosticsDir(for: record.gameId),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            try data.write(to: CellarPaths.diagnosticFile(for: record.gameId), options: .atomic)
        } catch {
            // Silent failure — diagnostics are best-effort
        }
    }

    static func readLatest(gameId: String) -> DiagnosticRecord? {
        let url = CellarPaths.diagnosticFile(for: gameId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DiagnosticRecord.self, from: data)
    }

    // MARK: - Formatting

    /// Format the record as a context block for injection into the agent's initial message.
    func formatForAgent() -> String {
        var lines: [String] = []
        lines.append("--- PREVIOUS SESSION DIAGNOSTICS ---")
        lines.append("Last run: \(errorCount) errors, \(successCount) successes")
        if !errorSummary.isEmpty {
            lines.append("Errors: \(errorSummary.joined(separator: "; "))")
        }
        if !lastActions.isEmpty {
            lines.append("Last actions applied: \(lastActions.joined(separator: ", "))")
        }
        lines.append("--- END PREVIOUS SESSION DIAGNOSTICS ---")
        return lines.joined(separator: "\n")
    }

    // MARK: - Factory

    /// Build a DiagnosticRecord from a WineDiagnostics result.
    static func from(diagnostics: WineDiagnostics, gameId: String, lastActions: [String]) -> DiagnosticRecord {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())

        let errors = diagnostics.allErrors()
        let successes = diagnostics.allSuccesses()

        let errorSummary: [String] = errors.map { error in
            let categoryName: String
            switch error.category {
            case .missingDLL: categoryName = "missingDLL"
            case .crash: categoryName = "crash"
            case .graphics: categoryName = "graphics"
            case .configuration: categoryName = "configuration"
            case .unknown: categoryName = "unknown"
            case .audio: categoryName = "audio"
            case .input: categoryName = "input"
            case .font: categoryName = "font"
            case .memory: categoryName = "memory"
            }
            return "\(categoryName): \(error.detail)"
        }

        let successSummary: [String] = successes.map { s in
            let categoryName: String
            switch s.subsystem {
            case .missingDLL: categoryName = "missingDLL"
            case .crash: categoryName = "crash"
            case .graphics: categoryName = "graphics"
            case .configuration: categoryName = "configuration"
            case .unknown: categoryName = "unknown"
            case .audio: categoryName = "audio"
            case .input: categoryName = "input"
            case .font: categoryName = "font"
            case .memory: categoryName = "memory"
            }
            return "\(categoryName): \(s.detail)"
        }

        return DiagnosticRecord(
            gameId: gameId,
            timestamp: timestamp,
            errorSummary: errorSummary,
            successSummary: successSummary,
            lastActions: lastActions,
            errorCount: errors.count,
            successCount: successes.count
        )
    }
}

import Foundation

// MARK: - AgentLogEntry

/// All event types that can be written to a session's JSONL event log.
enum AgentLogEntry: Codable {
    case sessionStarted(gameId: String, timestamp: String)
    case llmCalled(iteration: Int, inputTokens: Int, outputTokens: Int)
    case toolInvoked(name: String, iteration: Int)
    case toolCompleted(name: String, summary: String, iteration: Int)
    case stepCompleted(iteration: Int, cost: Double)
    case envChanged(key: String, value: String)
    case gameLaunched(launchNumber: Int, exitCode: Int, elapsed: Double)
    case spinDetected(pattern: [String])
    case budgetWarning(percentage: Int)
    case sessionEnded(reason: String, iterations: Int, cost: Double)
}

// MARK: - AgentEventLog

/// Append-only JSONL event log for a single agent session.
///
/// Each line in the file is a JSON-encoded `AgentLogEntry`. The file is created
/// at `~/.cellar/logs/<gameId>-<timestamp>.jsonl` when the log is initialized.
final class AgentEventLog {
    private let fileURL: URL
    private let encoder: JSONEncoder

    init(gameId: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")

        try? FileManager.default.createDirectory(
            at: CellarPaths.logsDir,
            withIntermediateDirectories: true
        )

        fileURL = CellarPaths.logsDir.appendingPathComponent("\(gameId)-\(timestamp).jsonl")

        encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
    }

    /// Computed property exposing the log file URL (e.g. for display in the UI).
    var url: URL { fileURL }

    /// Encode and append a single log entry as a JSONL line.
    func append(_ entry: AgentLogEntry) {
        guard let data = try? encoder.encode(entry) else { return }
        var line = data
        line.append(0x0A) // newline

        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: fileURL, options: .atomic)
        }
    }

    /// Read and decode all log entries from the JSONL file.
    func readAll() -> [AgentLogEntry] {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return raw
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> AgentLogEntry? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(AgentLogEntry.self, from: data)
            }
    }

    /// Build a plain-text resume summary from the event log.
    ///
    /// Returns nil if the log has no events.
    func summarizeForResume() -> String? {
        let entries = readAll()
        guard !entries.isEmpty else { return nil }

        var toolNames: [String] = []
        var envChanges: [(key: String, value: String)] = []
        var launches: [(launchNumber: Int, exitCode: Int, elapsed: Double)] = []

        for entry in entries {
            switch entry {
            case .toolInvoked(let name, _):
                toolNames.append(name)
            case .envChanged(let key, let value):
                envChanges.append((key: key, value: value))
            case .gameLaunched(let n, let code, let elapsed):
                launches.append((launchNumber: n, exitCode: code, elapsed: elapsed))
            default:
                break
            }
        }

        var lines: [String] = ["--- PREVIOUS SESSION (event log) ---"]

        if !toolNames.isEmpty {
            lines.append("Tools called: \(toolNames.joined(separator: ", "))")
        }

        if !envChanges.isEmpty {
            let envDesc = envChanges.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            lines.append("Environment configured: \(envDesc)")
        }

        if !launches.isEmpty {
            let launchDesc = launches.map { "launch \($0.launchNumber) (exit \($0.exitCode), \(String(format: "%.1f", $0.elapsed))s)" }.joined(separator: ", ")
            lines.append("Launch results: \(launchDesc)")
        }

        lines.append("---")
        return lines.joined(separator: "\n")
    }
}

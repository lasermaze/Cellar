import Foundation

/// Captures mid-session observations (`update_wiki` calls) in memory and persists
/// each append to a draft file for crash recovery. Notes are flushed into the final
/// session log entry by AIService at session end.
final class SessionDraftBuffer {

    private let draftFile: URL
    private(set) var notes: [(timestamp: String, content: String)] = []

    init(shortId: String) {
        self.draftFile = CellarPaths.sessionDraftFile(for: shortId)
        // On init, if a draft file already exists for this shortId, load it.
        // (Resume scenario: same shortId reused across resumed session.)
        if let existing = SessionDraftBuffer.readDraft(at: self.draftFile) {
            self.notes = existing
        }
        try? FileManager.default.createDirectory(
            at: CellarPaths.sessionsDraftDir,
            withIntermediateDirectories: true
        )
    }

    func append(content: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        notes.append((timestamp: ts, content: content))
        persist()
    }

    /// Delete the on-disk draft. Call after the session log has been successfully posted.
    func clearDraft() {
        try? FileManager.default.removeItem(at: draftFile)
    }

    private func persist() {
        // Encode each note on its own line: ISO8601\t<escaped content>\n
        let escaped: [String] = notes.map { note in
            let safe = note.content.replacingOccurrences(of: "\n", with: "\\n")
            return "\(note.timestamp)\t\(safe)"
        }
        let body = escaped.joined(separator: "\n") + "\n"
        try? body.write(to: draftFile, atomically: true, encoding: .utf8)
    }

    private static func readDraft(at url: URL) -> [(String, String)]? {
        guard FileManager.default.fileExists(atPath: url.path),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var parsed: [(String, String)] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let ts = String(parts[0])
            let content = String(parts[1]).replacingOccurrences(of: "\\n", with: "\n")
            parsed.append((ts, content))
        }
        return parsed
    }

    /// Best-effort cleanup: remove draft files older than `maxAge` seconds.
    /// Call from app/launch entry points.
    static func purgeOldDrafts(maxAge: TimeInterval = 7 * 24 * 60 * 60) {
        let dir = CellarPaths.sessionsDraftDir
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for url in entries {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let mtime = attrs[.modificationDate] as? Date,
               mtime < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

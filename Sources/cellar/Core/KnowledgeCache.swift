import Foundation

// MARK: - KnowledgeCache

/// File-backed TTL cache for KnowledgeStore entries.
///
/// Cache layout: `cacheDir/{key/components}.bin` — keys containing `/` are preserved
/// as subdirectory paths, so `config/cossacks-european-wars` becomes
/// `cacheDir/config/cossacks-european-wars` with intermediate directories created automatically.
///
/// Stale files are never deleted — `readStale(key:)` serves them on network-failure paths,
/// matching the existing CollectiveMemoryService pattern.
struct KnowledgeCache: Sendable {

    // MARK: Properties

    let cacheDir: URL
    let ttl: TimeInterval

    static let defaultTTL: TimeInterval = 3600

    // MARK: Init

    init(cacheDir: URL, ttl: TimeInterval = KnowledgeCache.defaultTTL) {
        self.cacheDir = cacheDir
        self.ttl = ttl
    }

    // MARK: - Public API

    /// Returns the cached bytes for `key` if the file exists, regardless of freshness.
    /// Returns nil only when the file is missing.
    func readStale(key: String) -> Data? {
        let url = fileURL(for: key)
        return try? Data(contentsOf: url)
    }

    /// Returns the cached bytes for `key` if the file exists (freshness is the caller's concern).
    /// This is the same as `readStale` — callers should check `isFresh(key:)` separately.
    func read(key: String) -> Data? {
        readStale(key: key)
    }

    /// Writes `data` to the cache file for `key`, creating intermediate directories as needed.
    func write(key: String, data: Data) throws {
        let url = fileURL(for: key)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Returns true when the cached file exists and its modification date is within the TTL.
    func isFresh(key: String) -> Bool {
        let url = fileURL(for: key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(modDate) < ttl
    }

    // MARK: - File URL (exposed for tests)

    /// Returns the cache file URL for `key`.
    /// Keys containing `/` are treated as subdirectory paths under `cacheDir`.
    func fileURL(for key: String) -> URL {
        cacheDir.appendingPathComponent(key)
    }
}

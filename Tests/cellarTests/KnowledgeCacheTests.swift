import Testing
import Foundation
@testable import cellar

@Suite("KnowledgeCache — TTL, stale, and missing file behavior")
struct KnowledgeCacheTests {

    // MARK: Helpers

    private func makeTempCache(ttl: TimeInterval = 3600) -> (KnowledgeCache, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        // Don't create it yet — KnowledgeCache.write should create directories
        let cache = KnowledgeCache(cacheDir: dir, ttl: ttl)
        return (cache, dir)
    }

    // MARK: Test 6: read returns nil when file missing

    @Test("read(key:) returns nil when no file exists")
    func readMissingReturnsNil() {
        let (cache, _) = makeTempCache()
        #expect(cache.read(key: "nonexistent-key") == nil)
    }

    // MARK: Test 7: write then read returns same bytes

    @Test("write(key:data:) then read(key:) returns the same bytes")
    func writeReadRoundTrip() throws {
        let (cache, _) = makeTempCache()
        let original = Data("hello cache world".utf8)
        try cache.write(key: "test-key", data: original)
        let result = cache.read(key: "test-key")
        #expect(result == original, "read should return the same bytes that were written")
    }

    // MARK: Test 8: isFresh returns true within TTL

    @Test("isFresh(key:) returns true when file mtime is within TTL")
    func isFreshWithinTTL() throws {
        let (cache, _) = makeTempCache(ttl: 3600)
        let data = Data("fresh data".utf8)
        try cache.write(key: "fresh-key", data: data)
        // File was just written — should be fresh
        #expect(cache.isFresh(key: "fresh-key") == true, "Freshly written file should be within TTL")
    }

    // MARK: Test 9: isFresh returns false when file mtime is older than TTL

    @Test("isFresh(key:) returns false when file mtime is older than TTL")
    func isFreshExpiredTTL() throws {
        let (cache, _) = makeTempCache(ttl: 3600)
        let data = Data("stale data".utf8)
        try cache.write(key: "stale-key", data: data)

        // Backdate the file mtime by 7200 seconds (2 hours — older than 1 hour TTL)
        let fileURL = cache.fileURL(for: "stale-key")
        let backdatedDate = Date(timeIntervalSinceNow: -7200)
        try FileManager.default.setAttributes(
            [.modificationDate: backdatedDate],
            ofItemAtPath: fileURL.path
        )

        #expect(cache.isFresh(key: "stale-key") == false, "File with backdated mtime should not be fresh")
    }

    // MARK: Test 10: readStale returns data even when isFresh is false

    @Test("readStale(key:) returns data even when isFresh is false")
    func readStaleReturnsStaleData() throws {
        let (cache, _) = makeTempCache(ttl: 3600)
        let original = Data("stale but valuable".utf8)
        try cache.write(key: "stale-valuable", data: original)

        // Backdate mtime so isFresh returns false
        let fileURL = cache.fileURL(for: "stale-valuable")
        let backdatedDate = Date(timeIntervalSinceNow: -7200)
        try FileManager.default.setAttributes(
            [.modificationDate: backdatedDate],
            ofItemAtPath: fileURL.path
        )

        #expect(cache.isFresh(key: "stale-valuable") == false, "Precondition: file should be stale")
        let result = cache.readStale(key: "stale-valuable")
        #expect(result == original, "readStale should return data even for stale files")
    }
}

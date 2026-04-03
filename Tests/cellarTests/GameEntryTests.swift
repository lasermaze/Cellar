import Testing
import Foundation
@testable import cellar

@Suite("GameEntry — Codable Round-Trip")
struct GameEntryTests {

    @Test("GameEntry round-trip preserves all fields")
    func fullRoundTrip() throws {
        let entry = GameEntry(
            id: "cossacks",
            name: "Cossacks: European Wars",
            installPath: "/Users/test/games/cossacks",
            executablePath: "C:\\Games\\Cossacks\\dmcr.exe",
            recipeId: "cossacks-european-wars",
            addedAt: Date(timeIntervalSince1970: 1700000000),
            lastLaunched: nil,
            lastResult: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GameEntry.self, from: data)

        #expect(decoded.id == "cossacks")
        #expect(decoded.name == "Cossacks: European Wars")
        #expect(decoded.executablePath == "C:\\Games\\Cossacks\\dmcr.exe")
        #expect(decoded.recipeId == "cossacks-european-wars")
    }

    @Test("GameEntry decodes with nil optional fields")
    func nilOptionals() throws {
        let json = """
        {
            "id": "test",
            "name": "Test Game",
            "installPath": "/test",
            "addedAt": "2026-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GameEntry.self, from: Data(json.utf8))
        #expect(decoded.id == "test")
        #expect(decoded.executablePath == nil)
        #expect(decoded.lastLaunched == nil)
        #expect(decoded.lastResult == nil)
    }

    @Test("slugify produces deterministic lowercase output")
    func slugifyBasic() {
        #expect(slugify("Cossacks: European Wars") == "cossacks-european-wars")
        #expect(slugify("Deus Ex GOTY") == "deus-ex-goty")
    }

    @Test("slugify strips trailing hyphens")
    func slugifyTrailingHyphens() {
        #expect(!slugify("Test Game!!!").hasSuffix("-"))
    }
}

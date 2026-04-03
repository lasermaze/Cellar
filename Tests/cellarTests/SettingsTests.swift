import Testing
@testable import cellar

@Suite("Settings — API Key Masking")
struct SettingsTests {

    // MARK: - maskKey

    @Test("maskKey returns empty for empty key")
    func maskKeyEmpty() {
        #expect(SettingsController.maskKey("") == "")
    }

    @Test("maskKey returns dots for short key (under 8 chars)")
    func maskKeyShort() {
        #expect(SettingsController.maskKey("abc") == "••••")
        #expect(SettingsController.maskKey("12345678") == "••••")
    }

    @Test("maskKey shows first 4 and last 4 for long key")
    func maskKeyLong() {
        let masked = SettingsController.maskKey("sk-ant-api03-abcdefghijklmnop")
        #expect(masked.hasPrefix("sk-a"))
        #expect(masked.hasSuffix("mnop"))
        #expect(masked.contains("••••"))
    }

    @Test("maskKey preserves key length indicator")
    func maskKeyFormat() {
        let masked = SettingsController.maskKey("1234567890abcdef")
        // first 4 + "••••••••" + last 4 = 16 chars
        #expect(masked == "1234••••••••cdef")
    }
}

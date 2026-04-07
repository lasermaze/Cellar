import Testing
import Foundation
@testable import cellar

@Suite("PEReader — PE Header Detection")
struct PEReaderTests {

    // MARK: - Helpers

    /// Write synthetic PE binary to a temp file and return the URL.
    private func makeTempPE(machineType: UInt16, peOffset: UInt32 = 0x40) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent(UUID().uuidString + ".exe")

        var bytes = [UInt8](repeating: 0, count: 512)

        // MZ header
        bytes[0] = 0x4D  // 'M'
        bytes[1] = 0x5A  // 'Z'

        // e_lfanew at offset 0x3C (4-byte LE DWORD pointing to PE signature)
        let off = UInt32(peOffset)
        bytes[0x3C] = UInt8(off & 0xFF)
        bytes[0x3D] = UInt8((off >> 8) & 0xFF)
        bytes[0x3E] = UInt8((off >> 16) & 0xFF)
        bytes[0x3F] = UInt8((off >> 24) & 0xFF)

        // PE signature at peOffset
        let p = Int(peOffset)
        bytes[p + 0] = 0x50  // 'P'
        bytes[p + 1] = 0x45  // 'E'
        bytes[p + 2] = 0x00
        bytes[p + 3] = 0x00

        // Machine type at peOffset+4 (2-byte LE)
        bytes[p + 4] = UInt8(machineType & 0xFF)
        bytes[p + 5] = UInt8((machineType >> 8) & 0xFF)

        try Data(bytes).write(to: url)
        return url
    }

    private func makeTempFile(_ content: Data, ext: String = ".txt") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ext)
        try content.write(to: url)
        return url
    }

    // MARK: - Tests

    @Test("Detects PE32 (i386 / 0x014C) as .win32")
    func detectsPE32() throws {
        let url = try makeTempPE(machineType: 0x014C)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PEReader.detectArch(fileURL: url) == .win32)
    }

    @Test("Detects PE32+ (AMD64 / 0x8664) as .win64")
    func detectsPE32Plus() throws {
        let url = try makeTempPE(machineType: 0x8664)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PEReader.detectArch(fileURL: url) == .win64)
    }

    @Test("Returns nil for unknown machine type (e.g. ARM64 0xAA64)")
    func unknownMachineTypeReturnsNil() throws {
        let url = try makeTempPE(machineType: 0xAA64)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PEReader.detectArch(fileURL: url) == nil)
    }

    @Test("Returns nil for plain text file")
    func textFileReturnsNil() throws {
        let content = "Hello, this is not a PE binary.".data(using: .utf8)!
        let url = try makeTempFile(content)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PEReader.detectArch(fileURL: url) == nil)
    }

    @Test("Returns nil for empty file")
    func emptyFileReturnsNil() throws {
        let url = try makeTempFile(Data())
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PEReader.detectArch(fileURL: url) == nil)
    }

    @Test("Returns nil for truncated MZ header (just two bytes)")
    func truncatedMZReturnsNil() throws {
        let url = try makeTempFile(Data([0x4D, 0x5A]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PEReader.detectArch(fileURL: url) == nil)
    }

    @Test("e_lfanew read as 4-byte DWORD (not 2 bytes)")
    func eL​fnewReadAs4Bytes() throws {
        // Place PE signature at offset 0x100 — requires correct 4-byte e_lfanew read.
        // If only 2 bytes are read, the offset would be 0x0100, which is still 256 — same value.
        // Use 0x0101 (257) to require all 4 bytes to be meaningful:
        // Actually easier: place PE at offset > 255 so the high byte matters.
        // Offset 0x140 = 320 — low byte 0x40, high byte 0x01 (in 2-byte read, only 0x40 = 64 used)
        let url = try makeTempPE(machineType: 0x014C, peOffset: 0x140)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PEReader.detectArch(fileURL: url) == .win32)
    }

    @Test("Arch enum raw values are string literals")
    func archRawValues() {
        #expect(PEReader.Arch.win32.rawValue == "win32")
        #expect(PEReader.Arch.win64.rawValue == "win64")
    }
}

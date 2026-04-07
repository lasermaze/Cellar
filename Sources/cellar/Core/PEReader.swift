import Foundation

/// Reads Windows PE (Portable Executable) file headers to detect binary architecture.
///
/// Used at install time to determine whether a game installer is 32-bit or 64-bit,
/// enabling arch-aware bottle decisions.
struct PEReader {

    /// The detected CPU architecture of a PE binary.
    enum Arch: String {
        case win32  // PE32 — i386 (32-bit)
        case win64  // PE32+ — AMD64 (64-bit)
    }

    /// Detects the architecture of a PE binary at the given URL.
    ///
    /// - Returns: `.win32` for PE32 (i386/0x014C), `.win64` for PE32+ (AMD64/0x8664),
    ///   or `nil` for non-PE files, corrupted headers, unknown machine types, or read failures.
    static func detectArch(fileURL: URL) -> Arch? {
        // Read first 1024 bytes — safety margin for large DOS stubs
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        let header: Data
        do {
            header = handle.readData(ofLength: 1024)
            try? handle.close()
        }

        // Minimum: MZ magic (2 bytes) + 62 padding bytes + e_lfanew (4 bytes at 0x3C) = 64 bytes
        guard header.count >= 64 else { return nil }

        // Check MZ magic bytes: 'M' (0x4D) 'Z' (0x5A)
        guard header[0] == 0x4D, header[1] == 0x5A else { return nil }

        // Read e_lfanew: 4-byte LE DWORD at offset 0x3C
        // (Bug fix: DiagnosticTools.swift reads only 2 bytes — we read all 4)
        let peOffset = Int(header[0x3C])
                     | (Int(header[0x3D]) << 8)
                     | (Int(header[0x3E]) << 16)
                     | (Int(header[0x3F]) << 24)

        // Validate PE signature 'P','E','\0','\0' at peOffset
        guard peOffset + 6 <= header.count else { return nil }
        guard header[peOffset + 0] == 0x50,   // 'P'
              header[peOffset + 1] == 0x45,   // 'E'
              header[peOffset + 2] == 0x00,
              header[peOffset + 3] == 0x00
        else { return nil }

        // Machine type: 2-byte LE WORD at peOffset+4
        let machine = UInt16(header[peOffset + 4]) | (UInt16(header[peOffset + 5]) << 8)

        switch machine {
        case 0x014C: return .win32  // IMAGE_FILE_MACHINE_I386
        case 0x8664: return .win64  // IMAGE_FILE_MACHINE_AMD64
        default:     return nil     // Unknown / not i386 or AMD64 (fix: DiagnosticTools treated all non-0x8664 as 32-bit)
        }
    }
}

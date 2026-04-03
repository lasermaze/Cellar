import Testing
import Foundation
@testable import cellar

@Suite("DiscImageHandler — Volume Label Filtering and Error Descriptions")
struct DiscImageHandlerTests {

    // Use an instance since volumeLabel is an instance method
    private let handler = DiscImageHandler()

    @Test("volumeLabel returns nil for generic CDROM label")
    func volumeLabelCdrom() {
        let label = handler.volumeLabel(from: URL(fileURLWithPath: "/Volumes/CDROM"))
        #expect(label == nil)
    }

    @Test("volumeLabel returns nil for DISC label (case insensitive)")
    func volumeLabelDisc() {
        let label = handler.volumeLabel(from: URL(fileURLWithPath: "/Volumes/Disc"))
        #expect(label == nil)
    }

    @Test("volumeLabel returns nil for DVD label")
    func volumeLabelDvd() {
        let label = handler.volumeLabel(from: URL(fileURLWithPath: "/Volumes/DVD"))
        #expect(label == nil)
    }

    @Test("volumeLabel returns meaningful name for game disc")
    func volumeLabelGameDisc() {
        let label = handler.volumeLabel(from: URL(fileURLWithPath: "/Volumes/Cossacks"))
        #expect(label == "Cossacks")
    }

    @Test("volumeLabel returns non-nil for non-generic name like Untitled")
    func volumeLabelUntitled() {
        let label = handler.volumeLabel(from: URL(fileURLWithPath: "/Volumes/Untitled"))
        // "Untitled" is not in the generic labels list — it passes through
        #expect(label == "Untitled")
    }

    @Test("DiscImageError cases have non-empty descriptions")
    func errorDescriptions() {
        let errors: [DiscImageError] = [
            .hdiutilFailed("test"),
            .noInstallerFound,
            .plistParseFailed,
            .noVolumesMounted,
            .companionBinNotFound("test.cue"),
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}

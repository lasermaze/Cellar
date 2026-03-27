import Foundation

// MARK: - DependencyStatus

struct DependencyStatus {
    let homebrew: URL?
    let wine: URL?
    let winetricks: URL?   // AGENT-01
    let gptk: Bool

    var allRequired: Bool { homebrew != nil && wine != nil && winetricks != nil }
}

// MARK: - DependencyChecker

struct DependencyChecker {
    /// Set of paths that "exist" — injected for testability.
    /// When nil, uses FileManager for real filesystem checks.
    private let mockedPaths: Set<String>?

    /// Production initializer — uses the real filesystem.
    init() {
        self.mockedPaths = nil
    }

    /// Test initializer — uses a fixed set of paths instead of the filesystem.
    init(existingPaths: [String]) {
        self.mockedPaths = Set(existingPaths)
    }

    // MARK: - Private helpers

    private func fileExists(atPath path: String) -> Bool {
        if let mocked = mockedPaths {
            return mocked.contains(path)
        }
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Public API

    /// Detects Homebrew by checking known install paths.
    /// ARM (Apple Silicon) path is checked before Intel path.
    func detectHomebrew() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/brew",   // Apple Silicon
            "/usr/local/bin/brew",      // Intel
        ]
        return candidates
            .first { fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Detects Wine binary in the same Homebrew bin directory as `brew`.
    /// Checks `wine64` first, then falls back to `wine`.
    func detectWine(brewPrefix: URL) -> URL? {
        let binDir = brewPrefix.deletingLastPathComponent()
        let candidates = ["wine64", "wine"].map { binDir.appendingPathComponent($0) }
        return candidates.first { fileExists(atPath: $0.path) }
    }

    /// Detects winetricks binary in the same Homebrew bin directory as `brew`.
    func detectWinetricks(brewPrefix: URL) -> URL? {
        let binDir = brewPrefix.deletingLastPathComponent()
        let path = binDir.appendingPathComponent("winetricks")
        return fileExists(atPath: path.path) ? path : nil
    }

    /// Best-effort detection of Game Porting Toolkit at known install paths.
    func detectGPTK() -> Bool {
        let candidates = [
            "/usr/local/bin/gameportingtoolkit",
            "/opt/homebrew/bin/gameportingtoolkit",
        ]
        return candidates.contains { fileExists(atPath: $0) }
    }

    /// Runs all detections and returns a unified status.
    func checkAll() -> DependencyStatus {
        let homebrew = detectHomebrew()
        let wine = homebrew.flatMap { detectWine(brewPrefix: $0) }
        let winetricks = homebrew.flatMap { detectWinetricks(brewPrefix: $0) }
        let gptk = detectGPTK()
        return DependencyStatus(homebrew: homebrew, wine: wine, winetricks: winetricks, gptk: gptk)
    }
}

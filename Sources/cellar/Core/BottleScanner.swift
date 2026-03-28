import Foundation

struct BottleScanner {
    /// Recursively scan a bottle's drive_c/ directory for game executables.
    /// Skips Wine system directories and known non-game executables.
    /// Returns discovered .exe paths sorted by depth (shallowest first).
    static func scanForExecutables(bottlePath: URL) -> [URL] {
        let driveC = BottleScanner.resolvedURL(bottlePath.appendingPathComponent("drive_c"))

        // Directories to skip — Wine system dirs that contain non-game executables
        let skipDirs: Set<String> = ["windows", "programdata", "users"]

        // System subdirectories under Program Files to skip — these contain OS/runtime programs, not games
        let skipProgramDirs: Set<String> = [
            "windows media player", "windows nt", "internet explorer",
            "common files", "microsoft", "directx",
        ]

        // Known non-game executables to exclude (prefix-matched against lowercased filename without extension)
        let skipExePatterns: [String] = [
            "unins000", "unins001", "uninstall",
            "vcredist", "dxsetup", "dxwebsetup",
            "setup", "install",
            "crashreporter", "updater", "launcher",
            "wmplayer", "iexplore", "notepad", "regedit", "winhlp32",
        ]

        // Config/utility tool suffixes — these are helper tools, not the game itself
        let skipExeSuffixes: [String] = [
            "_config", "_configuration", "_settings", "_options",
            "_editor", "_tool", "_diag", "_benchmark",
        ]

        var results: [URL] = []

        guard let enumerator = FileManager.default.enumerator(
            at: driveC,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            // Skip system directories by checking the top-level dir name under drive_c
            let relativePath = fileURL.path.replacingOccurrences(of: driveC.path + "/", with: "")
            let topDir = relativePath.components(separatedBy: "/").first?.lowercased() ?? ""
            if skipDirs.contains(topDir) {
                enumerator.skipDescendants()
                continue
            }

            // Only consider .exe files
            guard fileURL.pathExtension.lowercased() == "exe" else { continue }

            // Skip system subdirectories under Program Files (e.g., Windows Media Player, Common Files)
            let pathComponents = relativePath.lowercased().components(separatedBy: "/")
            if pathComponents.contains(where: { skipProgramDirs.contains($0) }) {
                continue
            }

            // Skip known non-game executables
            let filename = fileURL.deletingPathExtension().lastPathComponent.lowercased()
            let isSkippedPrefix = skipExePatterns.contains { pattern in
                filename.hasPrefix(pattern) || filename == pattern
            }
            let isSkippedSuffix = skipExeSuffixes.contains { suffix in
                filename.hasSuffix(suffix)
            }
            if isSkippedPrefix || isSkippedSuffix { continue }

            results.append(fileURL)
        }

        // Sort by path depth (shallowest first) — game executables tend to be at the top level of install dir
        results.sort { url1, url2 in
            url1.pathComponents.count < url2.pathComponents.count
        }

        return results
    }

    /// Resolve a URL through the filesystem, handling macOS firmlinks (/var → /private/var).
    private static func resolvedURL(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url }
        let result = URL(fileURLWithPath: String(cString: resolved))
        free(resolved)
        return result
    }

    /// Match a recipe's expected executable name against scan results.
    /// Returns the full path if found, nil otherwise.
    static func findExecutable(named name: String, in scanResults: [URL]) -> URL? {
        let nameLower = name.lowercased()
        return scanResults.first { $0.lastPathComponent.lowercased() == nameLower }
    }
}

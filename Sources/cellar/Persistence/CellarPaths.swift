import Foundation

struct CellarPaths {
    static let base: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cellar")

    /// Abort if running as root — prevents creating root-owned files under ~/.cellar and ~/.cache
    static func refuseRoot() {
        if ProcessInfo.processInfo.userName == "root" || getuid() == 0 {
            print("Error: Do not run cellar with sudo. It creates root-owned files that break Wine and winetricks.")
            print("If you already did, run:  sudo chown -R $(whoami):staff ~/.cellar ~/.cache/winetricks .build 2>/dev/null")
            _Exit(1)
        }
    }

    /// Check key directories for root-owned files and warn with a fix command
    static func checkOwnership() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirsToCheck = [
            base.path,
            "\(home)/.cache/winetricks"
        ]
        let currentUser = ProcessInfo.processInfo.userName
        var badPaths: [String] = []

        for dir in dirsToCheck {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            var stat = stat()
            if lstat(dir, &stat) == 0 && stat.st_uid == 0 {
                badPaths.append(dir)
            }
        }

        guard !badPaths.isEmpty else { return }
        print("Warning: These directories are owned by root (likely from a previous sudo run):")
        for path in badPaths {
            print("  \(path)")
        }
        print("Fix with:  sudo chown -R \(currentUser):staff \(badPaths.joined(separator: " "))")
        print("")
    }

    static let gamesJSON: URL = base.appendingPathComponent("games.json")

    static let bottlesDir: URL = base.appendingPathComponent("bottles")

    static let logsDir: URL = base.appendingPathComponent("logs")

    static let userRecipesDir: URL = base.appendingPathComponent("recipes")

    static func userRecipeFile(for gameId: String) -> URL {
        userRecipesDir.appendingPathComponent("\(gameId).json")
    }

    static let configFile: URL = base.appendingPathComponent("config.json")

    static let aiTipSentinel: URL = base.appendingPathComponent(".ai-tip-shown")

    static let dllsDir: URL = base.appendingPathComponent("dlls")

    static func dllCacheDir(for dllName: String) -> URL {
        dllsDir.appendingPathComponent(dllName)
    }

    static func cachedDLLFile(dllName: String, fileName: String) -> URL {
        dllCacheDir(for: dllName).appendingPathComponent(fileName)
    }

    static func bottleDir(for gameId: String) -> URL {
        bottlesDir.appendingPathComponent(gameId)
    }

    static func logDir(for gameId: String) -> URL {
        logsDir.appendingPathComponent(gameId)
    }

    static func logFile(for gameId: String, timestamp: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestampString = formatter.string(from: timestamp)
        return logDir(for: gameId).appendingPathComponent("\(timestampString).log")
    }

    // Success database directory: ~/.cellar/successdb/
    static let successdbDir: URL = base.appendingPathComponent("successdb")

    static func successdbFile(for gameId: String) -> URL {
        successdbDir.appendingPathComponent("\(gameId).json")
    }

    // Research cache directory: ~/.cellar/research/
    static let researchCacheDir: URL = base.appendingPathComponent("research")

    static func researchCacheFile(for gameId: String) -> URL {
        researchCacheDir.appendingPathComponent("\(gameId).json")
    }

    static func repairReportFile(for gameId: String, timestamp: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return logDir(for: gameId).appendingPathComponent("repair-report-\(formatter.string(from: timestamp)).txt")
    }

    /// Default collective memory repository identifier (owner/repo).
    static let defaultMemoryRepo = "cellar-community/memory"
}

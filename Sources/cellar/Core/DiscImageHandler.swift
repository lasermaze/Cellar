import Foundation

// MARK: - DiscImageError

enum DiscImageError: LocalizedError {
    case hdiutilFailed(String)
    case plistParseFailed
    case noVolumesMounted
    case noInstallerFound
    case companionBinNotFound(String)

    var errorDescription: String? {
        switch self {
        case .hdiutilFailed(let stderr):
            return """
            Failed to mount disc image: \(stderr)
            Try this: Verify the file is not corrupted. You can test with: hdiutil verify <path>
            """
        case .plistParseFailed:
            return """
            Failed to parse hdiutil output.
            Try this: Run `hdiutil attach -readonly -nobrowse <path>` manually to check for errors.
            """
        case .noVolumesMounted:
            return """
            The disc image was attached but no mountable filesystem was found.
            Try this: Convert the image first with: hdiutil convert <path> -format UDTO -o converted
            """
        case .noInstallerFound:
            return """
            No installer executable found on the mounted disc.
            Try this: Mount the disc manually with Finder and locate the installer, then run: cellar add /Volumes/<disc>/setup.exe
            """
        case .companionBinNotFound(let cueFile):
            return """
            Could not find the .bin file referenced by the .cue file: \(cueFile)
            Try this: Ensure the .bin file is in the same directory as the .cue file with matching filename.
            """
        }
    }
}

// MARK: - MountResult

struct MountResult {
    let mountPoint: URL
    let devEntry: String
    /// Non-nil when a .bin file was converted to a temporary ISO for mounting.
    let tempConvertedISO: URL?
}

// MARK: - DiscImageHandler

struct DiscImageHandler {

    // MARK: - Public API

    /// Mounts a disc image (.iso, .bin, or .cue) via hdiutil.
    ///
    /// - For .cue: locates the companion .bin and mounts that instead.
    /// - For .bin: attempts CRawDiskImage mount first; falls back to hdiutil convert.
    /// - For .iso/.img: mounts directly with hdiutil attach.
    ///
    /// - Returns: A MountResult with the mount point URL, dev entry, and optional temp ISO URL.
    /// - Throws: DiscImageError on mount failure.
    func mount(imageURL: URL) throws -> MountResult {
        let ext = imageURL.pathExtension.lowercased()

        switch ext {
        case "cue":
            let binURL = try resolveBinFromCue(cueURL: imageURL)
            return try mountBin(binURL: binURL)

        case "bin":
            return try mountBin(binURL: imageURL)

        case "iso", "img":
            return try mountISO(imageURL: imageURL)

        default:
            // Attempt as ISO-like image (renamed or unknown extension)
            return try mountISO(imageURL: imageURL)
        }
    }

    /// Discovers an installer executable on a mounted disc volume.
    ///
    /// Priority:
    /// 1. Parse autorun.inf for `open=` directive
    /// 2. Check common installer names (setup.exe, install.exe)
    /// 3. List all .exe files and prompt user to choose
    ///
    /// - Parameter mountPoint: The URL of the mounted volume root.
    /// - Returns: URL of the installer executable.
    /// - Throws: DiscImageError.noInstallerFound if no .exe exists on disc.
    func discoverInstaller(at mountPoint: URL) throws -> URL {
        // 1. Parse autorun.inf
        if let autorunURL = findAutorunInf(at: mountPoint) {
            if let installerURL = parseAutorunInf(at: autorunURL, mountPoint: mountPoint) {
                return installerURL
            }
        }

        // 2. Common installer names
        let commonNames = ["setup.exe", "install.exe", "Setup.exe", "Install.exe"]
        for name in commonNames {
            let candidate = mountPoint.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // 3. All .exe fallback
        let allExes = listExeFiles(at: mountPoint)
        switch allExes.count {
        case 0:
            throw DiscImageError.noInstallerFound
        case 1:
            return allExes[0]
        default:
            print("Multiple installers found on disc:")
            for (index, exeURL) in allExes.enumerated() {
                print("  \(index + 1). \(exeURL.lastPathComponent)")
            }
            print("Choose installer [1-\(allExes.count)]: ", terminator: "")
            fflush(stdout)
            if let line = readLine()?.trimmingCharacters(in: .whitespaces),
               let choice = Int(line),
               choice >= 1 && choice <= allExes.count {
                return allExes[choice - 1]
            }
            // Default to first if invalid input
            return allExes[0]
        }
    }

    /// Detaches the mounted disc volume and cleans up any temporary files.
    ///
    /// Never throws — all errors are silently suppressed. Retries with -force on failure.
    func detach(mountResult: MountResult) {
        // Attempt normal detach
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountResult.devEntry]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        // Retry with -force if first attempt failed
        if process.terminationStatus != 0 {
            let forceProcess = Process()
            forceProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            forceProcess.arguments = ["detach", "-force", mountResult.devEntry]
            forceProcess.standardOutput = FileHandle.nullDevice
            forceProcess.standardError = FileHandle.nullDevice
            try? forceProcess.run()
            forceProcess.waitUntilExit()
        }

        // Clean up temp converted ISO if present
        if let tempURL = mountResult.tempConvertedISO {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    /// Extracts a meaningful volume label from the mount point path.
    ///
    /// Returns nil for generic volume names like CDROM, DISC, DVD, etc.
    func volumeLabel(from mountPoint: URL) -> String? {
        let label = mountPoint.lastPathComponent
        let genericLabels: Set<String> = [
            "CDROM", "CD_ROM", "DISC", "DISC1", "DISC_1", "DVD", "VOLUME"
        ]
        if label.isEmpty || genericLabels.contains(label.uppercased()) {
            return nil
        }
        return label
    }

    // MARK: - Private Mount Helpers

    /// Mounts an ISO/IMG file using hdiutil attach.
    private func mountISO(imageURL: URL) throws -> MountResult {
        let plistData = try runHdiutil([
            "attach",
            "-readonly",
            "-nobrowse",
            "-plist",
            imageURL.path
        ])
        return try parseMountInfo(from: plistData, tempConvertedISO: nil)
    }

    /// Mounts a BIN file: tries CRawDiskImage first, falls back to hdiutil convert.
    private func mountBin(binURL: URL) throws -> MountResult {
        // Attempt 1: CRawDiskImage direct mount
        if let plistData = try? runHdiutil([
            "attach",
            "-readonly",
            "-nobrowse",
            "-plist",
            "-imagekey", "diskimage-class=CRawDiskImage",
            binURL.path
        ]) {
            if let result = try? parseMountInfo(from: plistData, tempConvertedISO: nil) {
                return result
            }
        }

        // Attempt 2: Convert .bin to CDR, then mount
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-disc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let convertedBase = tempDir.appendingPathComponent("converted").path

        print("Converting disc image to ISO format...")
        _ = try runHdiutil([
            "convert",
            binURL.path,
            "-format", "UDTO",
            "-o", convertedBase
        ])

        // hdiutil convert outputs .cdr extension
        let cdrURL = tempDir.appendingPathComponent("converted.cdr")
        guard FileManager.default.fileExists(atPath: cdrURL.path) else {
            try? FileManager.default.removeItem(at: tempDir)
            throw DiscImageError.hdiutilFailed("Converted CDR file not found at \(cdrURL.path)")
        }

        let plistData = try runHdiutil([
            "attach",
            "-readonly",
            "-nobrowse",
            "-plist",
            cdrURL.path
        ])

        return try parseMountInfo(from: plistData, tempConvertedISO: tempDir)
    }

    /// Parses a CUE file to locate the companion .bin file.
    ///
    /// Reads `FILE "filename" ...` directives and performs case-insensitive search.
    private func resolveBinFromCue(cueURL: URL) throws -> URL {
        let cueDir = cueURL.deletingLastPathComponent()
        let cueContent: String
        do {
            cueContent = try String(contentsOf: cueURL, encoding: .isoLatin1)
        } catch {
            throw DiscImageError.companionBinNotFound(cueURL.lastPathComponent)
        }

        // Parse FILE directive: FILE "filename.bin" ...
        var binFilename: String? = nil
        for line in cueContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let uppercased = trimmed.uppercased()
            if uppercased.hasPrefix("FILE ") {
                // Extract filename between quotes
                if let firstQuote = trimmed.firstIndex(of: "\""),
                   let lastQuote = trimmed.lastIndex(of: "\""),
                   firstQuote < lastQuote {
                    let start = trimmed.index(after: firstQuote)
                    binFilename = String(trimmed[start..<lastQuote])
                    break
                }
            }
        }

        guard let filename = binFilename else {
            throw DiscImageError.companionBinNotFound(cueURL.lastPathComponent)
        }

        // Case-insensitive search in the same directory
        let filenameLower = filename.lowercased()
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: cueDir.path)) ?? []
        for entry in contents {
            if entry.lowercased() == filenameLower {
                return cueDir.appendingPathComponent(entry)
            }
        }

        throw DiscImageError.companionBinNotFound(filename)
    }

    // MARK: - Private hdiutil Helpers

    /// Runs /usr/bin/hdiutil with given arguments, capturing stdout.
    ///
    /// - Returns: stdout Data on success.
    /// - Throws: DiscImageError.hdiutilFailed if exit code is non-zero.
    @discardableResult
    private func runHdiutil(_ args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw DiscImageError.hdiutilFailed("Failed to launch hdiutil: \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let stderrString = String(data: stderrData, encoding: .utf8) ?? "(no stderr)"
            throw DiscImageError.hdiutilFailed(stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return stdoutData
    }

    /// Parses hdiutil plist output to extract mount point and dev entry.
    ///
    /// Walks `system-entities` array for first entity containing both `mount-point` and `dev-entry`.
    /// If only `dev-entry` found (no filesystem), throws `.noVolumesMounted`.
    private func parseMountInfo(from plistData: Data, tempConvertedISO: URL?) throws -> MountResult {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            )
        } catch {
            throw DiscImageError.plistParseFailed
        }

        guard let dict = plist as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]] else {
            throw DiscImageError.plistParseFailed
        }

        if entities.isEmpty {
            throw DiscImageError.plistParseFailed
        }

        // Find first entity with both mount-point and dev-entry
        for entity in entities {
            if let mountPointStr = entity["mount-point"] as? String,
               let devEntry = entity["dev-entry"] as? String {
                let mountPoint = URL(fileURLWithPath: mountPointStr)
                return MountResult(
                    mountPoint: mountPoint,
                    devEntry: devEntry,
                    tempConvertedISO: tempConvertedISO
                )
            }
        }

        // No mount-point found — check if at least a dev-entry exists (block device, no filesystem)
        let hasDevEntry = entities.contains { $0["dev-entry"] != nil }
        if hasDevEntry {
            // Detach the orphaned device before throwing
            if let devEntry = entities.first?["dev-entry"] as? String {
                let cleanup = Process()
                cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                cleanup.arguments = ["detach", "-force", devEntry]
                cleanup.standardOutput = FileHandle.nullDevice
                cleanup.standardError = FileHandle.nullDevice
                try? cleanup.run()
                cleanup.waitUntilExit()
            }
            if let tempURL = tempConvertedISO {
                try? FileManager.default.removeItem(at: tempURL)
            }
            throw DiscImageError.noVolumesMounted
        }

        throw DiscImageError.plistParseFailed
    }

    // MARK: - Private Installer Discovery Helpers

    /// Locates autorun.inf at the mount point root with case-insensitive name matching.
    private func findAutorunInf(at mountPoint: URL) -> URL? {
        let candidates = ["AUTORUN.INF", "autorun.inf", "Autorun.inf"]
        for name in candidates {
            let url = mountPoint.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Fallback: case-insensitive scan of root directory
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mountPoint.path) else {
            return nil
        }
        for entry in contents {
            if entry.lowercased() == "autorun.inf" {
                return mountPoint.appendingPathComponent(entry)
            }
        }
        return nil
    }

    /// Parses autorun.inf for the `open=` directive and returns the installer URL if it exists.
    private func parseAutorunInf(at autorunURL: URL, mountPoint: URL) -> URL? {
        guard let content = try? String(contentsOf: autorunURL, encoding: .isoLatin1) else {
            return nil
        }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("open=") else { continue }

            // Extract value after "open="
            let valueStart = trimmed.index(trimmed.startIndex, offsetBy: 5)
            var value = String(trimmed[valueStart...])
                .trimmingCharacters(in: .whitespaces)

            // Strip surrounding quotes if present
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }

            // Normalize backslashes to forward slashes
            value = value.replacingOccurrences(of: "\\", with: "/")

            // Construct and verify the URL
            let installerURL = mountPoint.appendingPathComponent(value)
            if FileManager.default.fileExists(atPath: installerURL.path) {
                return installerURL
            }

            // Case-insensitive fallback for path components
            if let resolved = resolvePathCaseInsensitive(value, from: mountPoint) {
                return resolved
            }
        }

        return nil
    }

    /// Resolves a relative path from a base URL using case-insensitive component matching.
    private func resolvePathCaseInsensitive(_ relativePath: String, from base: URL) -> URL? {
        let components = relativePath.components(separatedBy: "/").filter { !$0.isEmpty }
        var current = base

        for component in components {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: current.path) else {
                return nil
            }
            let lower = component.lowercased()
            guard let match = entries.first(where: { $0.lowercased() == lower }) else {
                return nil
            }
            current = current.appendingPathComponent(match)
        }

        return FileManager.default.fileExists(atPath: current.path) ? current : nil
    }

    /// Lists all .exe files at the mount point root (non-recursive).
    private func listExeFiles(at mountPoint: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter { $0.pathExtension.lowercased() == "exe" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

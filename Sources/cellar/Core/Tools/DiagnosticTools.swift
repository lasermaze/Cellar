import Foundation

// MARK: - Diagnostic Tools Extension

extension AgentTools {

    // MARK: 1. inspect_game

    func inspectGame(input: JSONValue) -> String {
        print("[inspect_game] START for \(gameId)")
        let gameDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()

        // Detect PE type by reading the exe header bytes directly (no external process)
        print("[inspect_game] detecting PE type...")
        var exeType = "unknown"
        if let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: executablePath)) {
            let header = handle.readData(ofLength: 512)
            try? handle.close()
            // Check for MZ header + PE signature
            if header.count >= 2 && header[0] == 0x4D && header[1] == 0x5A {  // "MZ"
                // PE offset is at bytes 60-63 (little-endian)
                if header.count >= 64 {
                    let peOffset = Int(header[60]) | (Int(header[61]) << 8)
                    if peOffset + 6 <= header.count,
                       header[peOffset] == 0x50, header[peOffset+1] == 0x45 {  // "PE\0\0"
                        let machine = UInt16(header[peOffset+4]) | (UInt16(header[peOffset+5]) << 8)
                        if machine == 0x8664 {
                            exeType = "PE32+ (64-bit)"
                        } else {
                            exeType = "PE32 (32-bit)"
                        }
                    }
                }
            }
        }
        print("[inspect_game] PE type: \(exeType)")

        // List files in game directory (top-level only)
        print("[inspect_game] listing game files...")
        var gameFiles: [String] = []
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: gameDir,
            includingPropertiesForKeys: nil
        ) {
            gameFiles = contents.map { $0.lastPathComponent }.sorted()
        }

        // Subdirectory name scanning (one level deep, directory names only)
        var allGameFiles = gameFiles
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: gameDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for item in contents {
                if let values = try? item.resourceValues(forKeys: [.isDirectoryKey]),
                   values.isDirectory == true {
                    allGameFiles.append(item.lastPathComponent + "/")
                }
            }
        }

        // Check bottle existence
        let bottleExists = FileManager.default.fileExists(atPath: bottleURL.path)

        // List DLLs in system32
        print("[inspect_game] listing system32 DLLs...")
        var system32DLLs: [String] = []
        let system32Dir = bottleURL
            .appendingPathComponent("drive_c")
            .appendingPathComponent("windows")
            .appendingPathComponent("system32")
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: system32Dir,
            includingPropertiesForKeys: nil
        ) {
            system32DLLs = contents
                .filter { $0.pathExtension.lowercased() == "dll" }
                .map { $0.lastPathComponent }
                .sorted()
        }

        // Load bundled recipe info
        var recipeInfo: [String: Any] = [:]
        if let recipe = try? RecipeEngine.findBundledRecipe(for: gameId) {
            recipeInfo = [
                "name": recipe.name,
                "environment": recipe.environment,
                "registry_count": recipe.registry.count
            ]
        }

        print("[inspect_game] scanning PE imports...")
        // PE imports: scan first 64KB of exe for DLL name strings (PE headers live here)
        var peImports: [String] = []
        if let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: executablePath)) {
            let headerData = handle.readData(ofLength: 65536)
            try? handle.close()
            // Convert to ASCII, replacing non-printable bytes with spaces
            let bytes = headerData.map { ($0 >= 0x20 && $0 < 0x7F) ? $0 : UInt8(0x20) }
            let headerString = String(bytes: bytes, encoding: .ascii) ?? ""
            if !headerString.isEmpty {
                let pattern = try? NSRegularExpression(pattern: #"(\w+\.dll)"#, options: .caseInsensitive)
                let matches = pattern?.matches(in: headerString, range: NSRange(headerString.startIndex..., in: headerString)) ?? []
                var seen = Set<String>()
                let knownPrefixes = ["kernel32", "user32", "gdi32", "advapi32", "shell32", "ole32", "oleaut32",
                                   "msvcrt", "ntdll", "ws2_32", "winmm", "ddraw", "d3d", "dsound", "dinput",
                                   "opengl32", "version", "comctl32", "comdlg32", "imm32", "setupapi",
                                   "winspool", "msvcp", "vcruntime", "ucrtbase", "xinput", "wsock32"]
                for match in matches {
                    if let range = Range(match.range(at: 1), in: headerString) {
                        let dll = String(headerString[range]).lowercased()
                        if knownPrefixes.contains(where: { dll.hasPrefix($0) }) && seen.insert(dll).inserted {
                            peImports.append(dll)
                        }
                    }
                }
            }
        }
        print("[inspect_game] found \(peImports.count) PE imports")

        // Extract strings from binary (find printable sequences >= 10 chars)
        print("[inspect_game] extracting strings...")
        let binaryStrings = extractStrings(from: executablePath)
        print("[inspect_game] found \(binaryStrings.count) strings")

        print("[inspect_game] DONE")
        return jsonResult([
            "game_id": gameId,
            "executable_path": executablePath,
            "exe_type": exeType,
            "game_files": allGameFiles,
            "bottle_exists": bottleExists,
            "bottle_path": bottleURL.path,
            "system32_dlls": system32DLLs,
            "recipe": recipeInfo,
            "pe_imports": peImports,
            "binary_strings": binaryStrings
        ])
    }

    /// Extract printable ASCII strings (>= 10 chars) from a binary file.
    private func extractStrings(from path: String) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return []
        }
        let data = handle.readDataToEndOfFile()
        try? handle.close()

        var results: [String] = []
        var current: [UInt8] = []

        for byte in data {
            if byte >= 0x20 && byte < 0x7F {
                current.append(byte)
            } else {
                if current.count >= 10 {
                    if let s = String(bytes: current, encoding: .ascii) {
                        results.append(s)
                        if results.count >= 2000 { break }
                    }
                }
                current.removeAll()
            }
        }
        // Flush last run
        if current.count >= 10 && results.count < 2000 {
            if let s = String(bytes: current, encoding: .ascii) {
                results.append(s)
            }
        }
        return results
    }

    // MARK: 2. read_log

    func readLog(input: JSONValue) -> String {
        // Resolve log file: use lastLogFile or scan for most recent
        var logFileURL: URL? = lastLogFile

        if logFileURL == nil {
            let logDir = CellarPaths.logDir(for: gameId)
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: logDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) {
                logFileURL = contents
                    .filter { $0.pathExtension == "log" }
                    .sorted { a, b in
                        let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                        let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                        return aDate > bDate
                    }
                    .first
            }
        }

        guard let url = logFileURL else {
            return jsonResult(["error": "No log file found for game '\(gameId)'. Run launch_game first.", "log_content": ""])
        }

        // Read file, return last 8000 chars
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return jsonResult(["error": "Could not read log file: \(error.localizedDescription)", "log_file": url.path])
        }

        let diagnostics = WineErrorParser.parse(content)
        let filtered = WineErrorParser.filteredLog(content, diagnostics: diagnostics)
        return jsonResult([
            "diagnostics": diagnostics.asDictionary(),
            "filtered_log": String(filtered.suffix(8000)),
            "log_file": url.path
        ])
    }

    // MARK: 3. read_registry

    func readRegistry(input: JSONValue) -> String {
        guard let keyPath = input["key_path"]?.asString, !keyPath.isEmpty else {
            return jsonResult(["error": "key_path is required"])
        }
        let valueName = input["value_name"]?.asString

        // Determine which .reg file to read based on hive prefix
        let regFileURL: URL
        let upperKeyPath = keyPath.uppercased()
        if upperKeyPath.hasPrefix("HKCU") || upperKeyPath.hasPrefix("HKEY_CURRENT_USER") {
            regFileURL = bottleURL.appendingPathComponent("user.reg")
        } else if upperKeyPath.hasPrefix("HKLM") || upperKeyPath.hasPrefix("HKEY_LOCAL_MACHINE") {
            regFileURL = bottleURL.appendingPathComponent("system.reg")
        } else {
            return jsonResult(["error": "Unsupported hive in key_path '\(keyPath)'. Use HKCU or HKLM prefix."])
        }

        // Read reg file — try UTF-8 first, fall back to Windows-1252
        let regContent: String
        do {
            if let content = try? String(contentsOf: regFileURL, encoding: .utf8) {
                regContent = content
            } else {
                regContent = try String(contentsOf: regFileURL, encoding: .windowsCP1252)
            }
        } catch {
            return jsonResult(["error": "Could not read registry file: \(error.localizedDescription)"])
        }

        // Convert Windows key path separators: backslash -> forward slash for .reg search
        // Wine .reg files use backslash in section headers: [HKEY_CURRENT_USER\Software\Wine\DllOverrides]
        // We need to search for the exact Windows format with backslashes
        let lines = regContent.components(separatedBy: "\n")

        // Normalize the search key: expand abbreviations to full form
        let normalizedSearchKey = normalizeRegistryKey(keyPath)

        // Find the section header matching the key path
        var inSection = false
        var values: [String: String] = [:]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for section header: [HKEY_CURRENT_USER\Software\...]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let sectionKey = String(trimmed.dropFirst().dropLast())
                inSection = (sectionKey.uppercased() == normalizedSearchKey.uppercased())
                if inSection && valueName != nil {
                    // Keep scanning for the specific value
                }
                continue
            }

            guard inSection else { continue }

            // Empty line ends section
            if trimmed.isEmpty {
                if valueName == nil {
                    break // collected all values
                }
                continue
            }

            // Parse value line: "valueName"=data or @=data (default value)
            if trimmed.hasPrefix("\"") || trimmed.hasPrefix("@") {
                if let eqRange = trimmed.range(of: "=") {
                    let nameRaw = String(trimmed[trimmed.startIndex..<eqRange.lowerBound])
                    let data = String(trimmed[eqRange.upperBound...])

                    // Strip surrounding quotes from name
                    let parsedName: String
                    if nameRaw == "@" {
                        parsedName = "(Default)"
                    } else {
                        parsedName = nameRaw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    }

                    if let targetName = valueName {
                        if parsedName.lowercased() == targetName.lowercased() {
                            return jsonResult(["values": [parsedName: data], "key_path": keyPath])
                        }
                    } else {
                        values[parsedName] = data
                    }
                }
            }
        }

        if let targetName = valueName {
            return jsonResult(["error": "Value '\(targetName)' not found in '\(keyPath)'", "key_path": keyPath])
        }

        if values.isEmpty && !inSection {
            return jsonResult(["error": "Key path '\(keyPath)' not found in registry", "key_path": keyPath])
        }

        return jsonResult(["values": values, "key_path": keyPath])
    }

    /// Expand HKCU/HKLM abbreviations to full form for .reg file matching.
    private func normalizeRegistryKey(_ keyPath: String) -> String {
        var normalized = keyPath
        if normalized.uppercased().hasPrefix("HKCU\\") {
            normalized = "HKEY_CURRENT_USER\\" + normalized.dropFirst(5)
        } else if normalized.uppercased().hasPrefix("HKLM\\") {
            normalized = "HKEY_LOCAL_MACHINE\\" + normalized.dropFirst(5)
        } else if normalized.uppercased() == "HKCU" {
            normalized = "HKEY_CURRENT_USER"
        } else if normalized.uppercased() == "HKLM" {
            normalized = "HKEY_LOCAL_MACHINE"
        }
        return normalized
    }

    // MARK: - Msgbox Dialog Parsing

    /// Parse Wine trace:msgbox lines from stderr to extract dialog message text.
    /// Returns array of dicts with "message" and "source" keys.
    /// Wine only traces the message body (not caption or button type).
    static func parseMsgboxDialogs(from stderrLines: [String]) -> [[String: String]] {
        var dialogs: [[String: String]] = []
        for line in stderrLines {
            guard line.contains("trace:msgbox:MSGBOX_OnInit") else { continue }
            // Extract text between L" and the final "
            if let lQuoteRange = line.range(of: #"L""#),
               let lastQuote = line.lastIndex(of: "\""),
               lastQuote > lQuoteRange.upperBound {
                var rawText = String(line[lQuoteRange.upperBound..<lastQuote])
                // Unescape Wine debugstr_w sequences (order matters: backslash last)
                rawText = rawText.replacingOccurrences(of: "\\n", with: "\n")
                rawText = rawText.replacingOccurrences(of: "\\t", with: "\t")
                rawText = rawText.replacingOccurrences(of: "\\\\", with: "\\")
                dialogs.append([
                    "message": rawText,
                    "source": "trace:msgbox"
                ])
            }
        }
        return dialogs
    }

    // MARK: - Diagnostic Trace Tools

    /// Thread-safe stderr capture for trace_launch.
    final class TraceStderrCapture: @unchecked Sendable {
        private var buffer = ""
        private let lock = NSLock()
        func append(_ str: String) { lock.lock(); buffer += str; lock.unlock() }
        var value: String { lock.lock(); defer { lock.unlock() }; return buffer }
    }

    // MARK: 12. trace_launch

    /// Run a short diagnostic Wine launch with debug channels, kill after timeout.
    /// Returns structured DLL load analysis. Does NOT count toward launch limit.
    func traceLaunch(input: JSONValue) -> String {
        // Extract parameters with defaults
        let debugChannels: [String]
        if let channels = input["debug_channels"]?.asArray {
            debugChannels = channels.compactMap { $0.asString }
        } else {
            debugChannels = ["+loaddll", "+msgbox"]
        }
        let timeoutSeconds: Int
        if let ts = input["timeout_seconds"]?.asNumber {
            timeoutSeconds = Int(ts)
        } else {
            timeoutSeconds = 5
        }

        // Build environment: copy accumulated, merge WINEDEBUG channels
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = wineProcess.winePrefix.path
        for (key, value) in accumulatedEnv {
            env[key] = value
        }
        let existingDebug = env["WINEDEBUG"] ?? ""
        let channelsStr = debugChannels.joined(separator: ",")
        env["WINEDEBUG"] = existingDebug.isEmpty ? channelsStr : "\(existingDebug),\(channelsStr)"

        // Create process
        let process = Process()
        process.executableURL = wineProcess.wineBinary
        process.arguments = [executablePath]
        process.environment = env

        // Set CWD to binary's parent directory (matches WineProcess CWD fix)
        let binaryURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = binaryURL.deletingLastPathComponent()

        // Capture stderr
        let stderrPipe = Pipe()
        process.standardOutput = Pipe() // discard stdout
        process.standardError = stderrPipe

        let stderrCapture = TraceStderrCapture()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                stderrCapture.append(str)
            }
        }

        // Start process
        do {
            try process.run()
        } catch {
            return jsonResult(["error": "Failed to start trace launch: \(error.localizedDescription)"])
        }

        // Kill timer: terminate process + kill wineserver after timeout
        let killWork = DispatchWorkItem { [weak self] in
            process.terminate()
            try? self?.wineProcess.killWineserver()
            // Force SIGKILL after 2 more seconds if process is still alive
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Double(timeoutSeconds), execute: killWork)

        // Wait for exit with a hard timeout — don't hang if Wine children keep the process alive
        let waitDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            waitDone.signal()
        }
        let maxWait = Double(timeoutSeconds) + 5.0
        if waitDone.wait(timeout: .now() + maxWait) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            try? wineProcess.killWineserver()
        }
        killWork.cancel()

        // Kill wineserver to release all Wine children holding pipe descriptors
        try? wineProcess.killWineserver()

        // Close pipes immediately — readabilityHandler already captured data in real-time.
        // Do NOT call readDataToEndOfFile — Wine child processes hold pipe descriptors
        // open indefinitely, causing hangs.
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stderrPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForWriting.close()

        let stderr = stderrCapture.value

        // Parse +loaddll lines: trace:loaddll:...Loaded L"path" at addr: native|builtin
        let lines = stderr.components(separatedBy: "\n")
        var dllEntries: [String: [String: String]] = [:] // keyed by DLL name, last occurrence wins

        for line in lines {
            // Match lines containing loaddll trace output
            guard line.contains("trace:loaddll") || line.contains("Loaded") else { continue }

            // Regex: Loaded L"<path>".*: native|builtin
            if let match = line.range(of: #"Loaded L"([^"]+)".*\b(native|builtin)\b"#, options: .regularExpression) {
                let matchStr = String(line[match])
                // Extract path between L" and "
                if let pathStart = matchStr.range(of: #"L""#),
                   let pathEnd = matchStr[pathStart.upperBound...].range(of: "\"") {
                    let fullPath = String(matchStr[pathStart.upperBound..<pathEnd.lowerBound])
                    let dllName = URL(fileURLWithPath: fullPath.replacingOccurrences(of: "\\", with: "/")).lastPathComponent.lowercased()
                    let loadType = matchStr.hasSuffix("native") ? "native" : "builtin"
                    // Deduplicate by DLL name (keep last occurrence)
                    dllEntries[dllName] = [
                        "name": dllName,
                        "path": fullPath,
                        "type": loadType
                    ]
                }
            }
        }

        let loadedDLLs = dllEntries.values.sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }

        // Parse +msgbox lines for dialog detection
        let parsedDialogs = AgentTools.parseMsgboxDialogs(from: lines)

        // Parse structured diagnostics from stderr
        let diagnostics = WineErrorParser.parse(stderr)

        // Swap pending actions for diff tracking
        lastAppliedActions = pendingActions
        pendingActions = []

        let changesDiff = computeChangesDiff(current: diagnostics, previousDiagnostics: previousDiagnostics, lastActions: lastAppliedActions)
        previousDiagnostics = diagnostics

        // Persist to disk for cross-session tracking
        let record = DiagnosticRecord.from(diagnostics: diagnostics, gameId: gameId, lastActions: lastAppliedActions)
        DiagnosticRecord.write(record)

        return jsonResult([
            "loaded_dlls": loadedDLLs,
            "dialogs": parsedDialogs,
            "diagnostics": diagnostics.asDictionary(),
            "changes_since_last": changesDiff,
            "timeout_applied": true,
            "raw_line_count": lines.count
        ])
    }

    // MARK: 13. check_file_access

    func checkFileAccess(input: JSONValue) -> String {
        guard let paths = input["paths"]?.asArray?.compactMap({ $0.asString }), !paths.isEmpty else {
            return jsonResult(["error": "paths array is required and must not be empty"])
        }

        let gameDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        let fm = FileManager.default

        var results: [[String: Any]] = []
        for relativePath in paths {
            let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
            let fullURL = gameDir.appendingPathComponent(normalizedPath)
            let exists = fm.fileExists(atPath: fullURL.path)
            results.append([
                "path": relativePath,
                "exists_from_game_dir": exists,
                "absolute_path": fullURL.path
            ])
        }

        return jsonResult(["results": results, "game_dir": gameDir.path])
    }

    // MARK: 14. verify_dll_override

    func verifyDllOverride(input: JSONValue) -> String {
        guard let dllName = input["dll_name"]?.asString, !dllName.isEmpty else {
            return jsonResult(["error": "dll_name is required"])
        }

        let dllFileName = dllName.hasSuffix(".dll") ? dllName : "\(dllName).dll"
        let baseName = dllName.replacingOccurrences(of: ".dll", with: "").lowercased()

        // 1. Check configured override in accumulatedEnv
        let configuredOverride: String?
        if let overrides = accumulatedEnv["WINEDLLOVERRIDES"] {
            // Parse override string like "ddraw=n,b;dsound=b"
            let pairs = overrides.components(separatedBy: ";")
            configuredOverride = pairs.first(where: { $0.lowercased().hasPrefix(baseName + "=") })
        } else {
            configuredOverride = nil
        }

        // 2. Check where native DLL files exist
        let gameDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        let system32Dir = bottleURL
            .appendingPathComponent("drive_c/windows/system32")
        let syswow64Dir = bottleURL
            .appendingPathComponent("drive_c/windows/syswow64")

        let fm = FileManager.default
        var nativeDllLocations: [String] = []
        if fm.fileExists(atPath: gameDir.appendingPathComponent(dllFileName).path) {
            nativeDllLocations.append("game_dir")
        }
        if fm.fileExists(atPath: system32Dir.appendingPathComponent(dllFileName).path) {
            nativeDllLocations.append("system32")
        }
        if fm.fileExists(atPath: syswow64Dir.appendingPathComponent(dllFileName).path) {
            nativeDllLocations.append("syswow64")
        }

        // 3. Run a short trace launch to see what Wine actually loaded (skip if no executable found)
        let traceResultStr: String
        if fm.fileExists(atPath: executablePath) {
            let traceInput = JSONValue.object([
                "debug_channels": .array([.string("+loaddll")]),
                "timeout_seconds": .number(8)
            ])
            traceResultStr = traceLaunch(input: traceInput)
        } else {
            traceResultStr = jsonResult(["error": "no executable to trace"])
        }

        // Parse trace result to find the DLL
        var actualLoadPath: String? = nil
        var actualLoadType: String? = nil
        if let traceData = traceResultStr.data(using: .utf8),
           let traceJSON = try? JSONSerialization.jsonObject(with: traceData) as? [String: Any],
           let loadedDLLs = traceJSON["loaded_dlls"] as? [[String: String]] {
            for dll in loadedDLLs {
                if let name = dll["name"], name.lowercased() == dllFileName.lowercased() {
                    actualLoadPath = dll["path"]
                    actualLoadType = dll["type"]
                    break
                }
            }
        }

        // 4. Build explanation
        let explanation: String
        let working: Bool

        if let override = configuredOverride {
            if let loadType = actualLoadType {
                let wantsNative = override.contains("n,b") || override.contains("=n")
                if wantsNative && loadType == "native" {
                    explanation = "Override working correctly: configured \(override), loaded native from \(actualLoadPath ?? "unknown")"
                    working = true
                } else if wantsNative && loadType == "builtin" {
                    if nativeDllLocations.isEmpty {
                        explanation = "Override set to \(override) but Wine loaded builtin — no native DLL file found in game_dir, system32, or syswow64"
                    } else {
                        explanation = "Override set to \(override) but Wine loaded builtin from \(actualLoadPath ?? "unknown") — native DLL found in \(nativeDllLocations.joined(separator: ", ")) but Wine did not use it. For system DLLs in wow64 bottles, place in syswow64."
                    }
                    working = false
                } else {
                    explanation = "Override \(override) active, loaded \(loadType) from \(actualLoadPath ?? "unknown")"
                    working = true
                }
            } else {
                explanation = "Override \(override) is configured but DLL '\(dllFileName)' was not observed in trace output — game may not load this DLL at startup"
                working = false
            }
        } else {
            if let loadType = actualLoadType {
                explanation = "No override configured. Wine loaded \(loadType) \(dllFileName) from \(actualLoadPath ?? "unknown")"
                working = loadType == "builtin" // builtin is expected default
            } else {
                explanation = "No override configured and DLL '\(dllFileName)' was not observed in trace output"
                working = true // nothing to verify
            }
        }

        return jsonResult([
            "dll_name": baseName,
            "configured_override": configuredOverride ?? "none",
            "native_dll_locations": nativeDllLocations,
            "actual_load": [
                "path": actualLoadPath ?? "not_found",
                "type": actualLoadType ?? "not_loaded"
            ],
            "explanation": explanation,
            "working": working
        ])
    }
}

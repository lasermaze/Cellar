import Foundation
import CoreGraphics

// MARK: - Launch Tools Extension

extension AgentTools {

    // MARK: 4. ask_user

    func askUser(input: JSONValue) -> String {
        guard let question = input["question"]?.asString, !question.isEmpty else {
            return jsonResult(["error": "question is required"])
        }

        let options = input["options"]?.asArray?.compactMap { $0.asString }
        let answer = askUserHandler(question, options)
        return jsonResult(["answer": answer])
    }

    // MARK: 9. launch_game

    func launchGame(input: JSONValue) -> String {
        let isDiagnostic = input["diagnostic"]?.asBool ?? false

        // Enforce max launch limit (diagnostic launches are free)
        if !isDiagnostic {
            if launchCount >= maxLaunches {
                return jsonResult([
                    "error": "Maximum launches (\(maxLaunches)) reached for this session. Save a recipe if you found a working configuration.",
                    "launch_number": launchCount
                ])
            }
            launchCount += 1
        }
        let thisLaunchNumber = launchCount

        // Pre-flight checks
        var preflightWarnings: [String] = []
        let fm = FileManager.default

        // a. Verify executable exists
        if !fm.fileExists(atPath: config.executablePath) {
            preflightWarnings.append("Executable not found at: \(config.executablePath)")
        }

        // b. Check DLL override files exist where expected
        if let overrides = accumulatedEnv["WINEDLLOVERRIDES"], !overrides.isEmpty {
            let gameDir = URL(fileURLWithPath: config.executablePath).deletingLastPathComponent()
            let system32Dir = config.bottleURL.appendingPathComponent("drive_c/windows/system32")
            let syswow64Dir = config.bottleURL.appendingPathComponent("drive_c/windows/syswow64")
            let pairs = overrides.components(separatedBy: ";")
            for pair in pairs {
                let parts = pair.components(separatedBy: "=")
                guard let dllBase = parts.first?.trimmingCharacters(in: .whitespaces), !dllBase.isEmpty else { continue }
                let mode = parts.count > 1 ? parts[1] : ""
                // Only check native overrides (n or n,b)
                if mode.contains("n") {
                    let dllFile = dllBase.hasSuffix(".dll") ? dllBase : "\(dllBase).dll"
                    let inGameDir = fm.fileExists(atPath: gameDir.appendingPathComponent(dllFile).path)
                    let inSystem32 = fm.fileExists(atPath: system32Dir.appendingPathComponent(dllFile).path)
                    let inSyswow64 = fm.fileExists(atPath: syswow64Dir.appendingPathComponent(dllFile).path)
                    if !inGameDir && !inSystem32 && !inSyswow64 {
                        preflightWarnings.append("DLL override '\(dllBase)=\(mode)' set but \(dllFile) not found in game_dir, system32, or syswow64")
                    }
                }
            }
        }

        // Build environment: start with accumulated env
        var env = accumulatedEnv

        // Merge extra_winedebug if provided
        if let extraDebug = input["extra_winedebug"]?.asString, !extraDebug.isEmpty {
            let current = env["WINEDEBUG"] ?? ""
            env["WINEDEBUG"] = current.isEmpty ? extraDebug : "\(current),\(extraDebug)"
        }

        // Create log file
        let logFile = CellarPaths.logFile(for: config.gameId, timestamp: Date())

        // Ensure log directory exists
        let logDir = logFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let launchLabel = isDiagnostic ? "diagnostic" : "\(thisLaunchNumber)/\(maxLaunches)"
        print("\n[Agent launch \(launchLabel)] Starting game...")

        // Run game via wineProcess
        let result: WineResult
        do {
            result = try config.wineProcess.run(
                binary: config.executablePath,
                arguments: [],
                environment: env,
                logFile: logFile
            )
        } catch {
            return jsonResult([
                "error": "Failed to launch game: \(error.localizedDescription)",
                "launch_number": thisLaunchNumber,
                "diagnostic": isDiagnostic
            ])
        }

        // Store last log file for read_log
        lastLogFile = logFile

        // Parse structured diagnostics from stderr
        let diagnostics = WineErrorParser.parse(result.stderr)

        // Swap pending actions for diff tracking
        lastAppliedActions = pendingActions
        pendingActions = []

        // Compute changes since last launch
        let changesDiff = computeChangesDiff(current: diagnostics, previousDiagnostics: previousDiagnostics, lastActions: lastAppliedActions)

        // Store current diagnostics for next comparison
        previousDiagnostics = diagnostics

        // Persist to disk for cross-session tracking
        let record = DiagnosticRecord.from(diagnostics: diagnostics, gameId: config.gameId, lastActions: lastAppliedActions)
        DiagnosticRecord.write(record)

        // Parse +loaddll lines from stderr for DLL load analysis
        let stderrLines = result.stderr.components(separatedBy: "\n")
        var loadedDLLEntries: [String: [String: String]] = [:]
        for line in stderrLines {
            guard line.contains("loaddll") || line.contains("Loaded") else { continue }
            if let match = line.range(of: #"Loaded L"([^"]+)".*\b(native|builtin)\b"#, options: .regularExpression) {
                let matchStr = String(line[match])
                if let pathStart = matchStr.range(of: #"L""#),
                   let pathEnd = matchStr[pathStart.upperBound...].range(of: "\"") {
                    let fullPath = String(matchStr[pathStart.upperBound..<pathEnd.lowerBound])
                    let dllName = URL(fileURLWithPath: fullPath.replacingOccurrences(of: "\\", with: "/")).lastPathComponent.lowercased()
                    let loadType = matchStr.hasSuffix("native") ? "native" : "builtin"
                    loadedDLLEntries[dllName] = ["name": dllName, "path": fullPath, "type": loadType]
                }
            }
        }
        let loadedDLLs = loadedDLLEntries.values.sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }

        // Parse +msgbox lines from stderr for dialog detection
        let parsedDialogs = AgentTools.parseMsgboxDialogs(from: stderrLines)

        let stderrTail = String(result.stderr.suffix(4000))

        // Determine if game ran long enough that the user interacted with it
        let likelyRanSuccessfully = result.elapsed > 3.0

        var resultDict: [String: Any] = [
            "exit_code": Int(result.exitCode),
            "elapsed_seconds": result.elapsed,
            "timed_out": result.timedOut,
            "stderr_tail": stderrTail,
            "diagnostics": diagnostics.asDictionary(),
            "changes_since_last": changesDiff,
            "loaded_dlls": loadedDLLs,
            "dialogs": parsedDialogs,
            "log_file": logFile.path,
            "launch_number": thisLaunchNumber,
            "diagnostic": isDiagnostic
        ]
        if !preflightWarnings.isEmpty {
            resultDict["preflight_warnings"] = preflightWarnings
        }
        if likelyRanSuccessfully {
            // Auto-prompt user directly — don't leave this to the agent
            let feedback = askUserHandler(
                "Game ran for \(Int(result.elapsed)) seconds. Did the game work? (yes / no / describe any issues)",
                nil
            )
            resultDict["user_feedback"] = feedback
            resultDict["user_was_asked"] = true
            resultDict["IMPORTANT"] = "The user was already asked about the game and responded: '\(feedback)'. Use their feedback to decide next steps. Do NOT call ask_user to re-ask the same question."
        } else if !isDiagnostic && !result.timedOut && result.elapsed < 10.0 {
            // Fast crash — task is definitely not complete
            resultDict["IMPORTANT"] = "Game crashed in \(String(format: "%.1f", result.elapsed))s. This is NOT a success. Diagnose the crash using read_log and diagnostics, then fix and relaunch."
        }

        return jsonResult(resultDict)
    }

    // MARK: 19. list_windows

    /// Query macOS window list for Wine processes using CoreGraphics.
    func listWindows(input: JSONValue) -> String {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return jsonResult(["error": "Failed to query window list", "windows": [] as [Any], "count": 0])
        }

        let wineNames: Set<String> = ["wine", "wine64", "wineserver",
            "wine-preloader", "wine64-preloader", "start.exe"]

        let myPID = ProcessInfo.processInfo.processIdentifier
        var wineWindows: [[String: Any]] = []
        var hasScreenRecordingPermission = false

        // Check all windows for Screen Recording permission indicator
        for window in windowList {
            if let pid = window[kCGWindowOwnerPID as String] as? Int32,
               pid != myPID,
               window[kCGWindowName as String] as? String != nil {
                hasScreenRecordingPermission = true
                break
            }
        }

        // Filter to Wine processes
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String else { continue }

            let isWine = wineNames.contains(ownerName.lowercased()) ||
                         ownerName.lowercased().contains("wine")
            guard isWine else { continue }

            var entry: [String: Any] = ["owner": ownerName]

            // Bounds are always available (no permission needed)
            if let bounds = window[kCGWindowBounds as String] as? [String: Any] {
                let w = (bounds["Width"] as? CGFloat) ?? (bounds["Width"] as? Double).map { CGFloat($0) } ?? 0
                let h = (bounds["Height"] as? CGFloat) ?? (bounds["Height"] as? Double).map { CGFloat($0) } ?? 0
                entry["width"] = Int(w)
                entry["height"] = Int(h)
                entry["likely_dialog"] = (w < 640 && h < 480)
            }

            // Window name requires Screen Recording permission
            if let name = window[kCGWindowName as String] as? String {
                entry["title"] = name
            }

            wineWindows.append(entry)
        }

        var result: [String: Any] = [
            "windows": wineWindows,
            "screen_recording_permission": hasScreenRecordingPermission,
            "count": wineWindows.count
        ]

        if wineWindows.isEmpty && !hasScreenRecordingPermission {
            result["note"] = "No Wine windows found. If a Wine game is running, Screen Recording permission may be needed for full window detection. Grant permission to Terminal/your app in System Settings > Privacy & Security > Screen Recording."
        }

        return jsonResult(result)
    }

    // MARK: - Launch Helpers

    /// Describe a WineFix as a human-readable string for the agent.
    func describeFix(_ fix: WineFix) -> String {
        switch fix {
        case .installWinetricks(let verb): return "install_winetricks(\(verb))"
        case .setEnvVar(let key, let value): return "set_environment(\(key)=\(value))"
        case .setDLLOverride(let dll, let mode): return "set_environment(WINEDLLOVERRIDES=\(dll)=\(mode))"
        case .placeDLL(let name, let target): return "place_dll(\(name), \(target))"
        case .setRegistry(let key, let name, let data): return "set_registry(\(key), \(name)=\(data))"
        case .compound(let fixes): return fixes.map { describeFix($0) }.joined(separator: " + ")
        }
    }

    /// Compute a diff between current and previous diagnostics for changes_since_last.
    func computeChangesDiff(
        current: WineDiagnostics,
        previousDiagnostics: WineDiagnostics?,
        lastActions: [String]
    ) -> [String: Any] {
        guard let previous = previousDiagnostics else {
            return ["note": "First launch — no previous data for comparison"]
        }

        // Use (category, detail) as identity for comparison
        let currentErrors = Set(current.allErrors().map { "\($0.category):\($0.detail)" })
        let previousErrors = Set(previous.allErrors().map { "\($0.category):\($0.detail)" })
        let currentSuccesses = Set(current.allSuccesses().map { "\($0.subsystem):\($0.detail)" })
        let previousSuccesses = Set(previous.allSuccesses().map { "\($0.subsystem):\($0.detail)" })

        return [
            "last_actions": lastActions,
            "new_errors": Array(currentErrors.subtracting(previousErrors)).sorted(),
            "resolved_errors": Array(previousErrors.subtracting(currentErrors)).sorted(),
            "persistent_errors": Array(currentErrors.intersection(previousErrors)).sorted(),
            "new_successes": Array(currentSuccesses.subtracting(previousSuccesses)).sorted()
        ]
    }
}

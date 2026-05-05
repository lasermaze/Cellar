import Foundation

// MARK: - Config Tools Extension

extension AgentTools {

    // MARK: Allowlisted Wine environment variable keys

    /// The set of environment variable keys the agent is permitted to set.
    /// Shared between the write path (setEnvironment) and the read path (CollectiveMemoryService.sanitizeEntry).
    static var allowedEnvKeys: Set<String> { PolicyResources.shared.envAllowlist }

    // MARK: 5. set_environment

    func setEnvironment(input: JSONValue) -> String {
        guard let key = input["key"]?.asString, !key.isEmpty else {
            return jsonResult(["error": "key is required"])
        }
        guard let value = input["value"]?.asString else {
            return jsonResult(["error": "value is required"])
        }

        guard AgentTools.allowedEnvKeys.contains(key) else {
            let allowed = AgentTools.allowedEnvKeys.sorted().joined(separator: ", ")
            return jsonResult(["error": "Environment key '\(key)' not allowed. Allowed keys: \(allowed)"])
        }

        session.accumulatedEnv[key] = value

        return jsonResult([
            "status": "ok",
            "key": key,
            "value": value,
            "current_env": session.accumulatedEnv
        ])
    }

    // MARK: 6. set_registry

    /// Allowed HKEY prefix paths for registry edits.
    private static var allowedRegistryPrefixes: [String] { PolicyResources.shared.registryAllowlist }

    func setRegistry(input: JSONValue) -> String {
        guard let keyPath = input["key_path"]?.asString, !keyPath.isEmpty else {
            return jsonResult(["error": "key_path is required"])
        }
        guard let valueName = input["value_name"]?.asString, !valueName.isEmpty else {
            return jsonResult(["error": "value_name is required"])
        }
        guard let data = input["data"]?.asString else {
            return jsonResult(["error": "data is required"])
        }

        // Normalize forward slashes to backslashes for consistency
        let normalizedKeyPath = keyPath.replacingOccurrences(of: "/", with: "\\")

        // Validate registry key prefix
        let isAllowed = AgentTools.allowedRegistryPrefixes.contains(where: { normalizedKeyPath.hasPrefix($0) })
        guard isAllowed else {
            let allowed = AgentTools.allowedRegistryPrefixes.joined(separator: ", ")
            return jsonResult(["error": "Registry key '\(keyPath)' must start with an allowed prefix: \(allowed)"])
        }

        // Build .reg file content
        var regContent = "Windows Registry Editor Version 5.00\n\n"
        regContent += "[\(normalizedKeyPath)]\n"
        regContent += "\"\(valueName)\"=\(data)\n"

        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".reg")
        do {
            try regContent.write(to: tempFile, atomically: true, encoding: .utf8)
            try config.wineProcess.applyRegistryFile(at: tempFile)
            try? FileManager.default.removeItem(at: tempFile)
            return jsonResult([
                "status": "ok",
                "key_path": normalizedKeyPath,
                "value_name": valueName,
                "data": data
            ])
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
            return jsonResult(["error": "Registry edit failed: \(error.localizedDescription)"])
        }
    }

    // MARK: 7. install_winetricks

    func installWinetricks(input: JSONValue) -> String {
        guard let verb = input["verb"]?.asString, !verb.isEmpty else {
            return jsonResult(["error": "verb is required"])
        }

        // Validate against allowlist
        guard AIService.agentValidWinetricksVerbs.contains(verb) else {
            let allowed = AIService.agentValidWinetricksVerbs.sorted().joined(separator: ", ")
            return jsonResult(["error": "Verb '\(verb)' not in allowed list.", "allowed_verbs": allowed])
        }

        // Skip if already installed
        if session.installedDeps.contains(verb) {
            return jsonResult(["status": "ok", "verb": verb, "note": "Already installed in this session"])
        }

        // Find winetricks binary
        guard let winetricksURL = DependencyChecker().checkAll().winetricks else {
            return jsonResult(["error": "winetricks not found. Run 'cellar status' to check dependencies."])
        }

        let runner = WinetricksRunner(
            winetricksURL: winetricksURL,
            wineBinary: config.wineURL,
            bottlePath: config.bottleURL.path
        )

        do {
            let result = try runner.install(verb: verb)
            if result.success {
                session.installedDeps.insert(verb)
                return jsonResult([
                    "status": "ok",
                    "verb": verb,
                    "exit_code": Int(result.exitCode),
                    "elapsed_seconds": result.elapsed,
                    "timed_out": result.timedOut
                ])
            } else if result.timedOut {
                return jsonResult(["error": "winetricks '\(verb)' timed out (>5 min stale output)", "verb": verb])
            } else {
                return jsonResult([
                    "error": "winetricks '\(verb)' failed with exit code \(result.exitCode)",
                    "verb": verb,
                    "exit_code": Int(result.exitCode)
                ])
            }
        } catch {
            return jsonResult(["error": "winetricks error: \(error.localizedDescription)", "verb": verb])
        }
    }

    // MARK: 8. place_dll

    func placeDLL(input: JSONValue) async -> String {
        guard let dllName = input["dll_name"]?.asString, !dllName.isEmpty else {
            return jsonResult(["error": "dll_name is required"])
        }

        guard let knownDLL = KnownDLLRegistry.find(name: dllName) else {
            let available = KnownDLLRegistry.registry.map { $0.name }.joined(separator: ", ")
            return jsonResult([
                "error": "DLL '\(dllName)' is not in the known DLL registry. The user should place it manually. Available DLLs: \(available)"
            ])
        }

        // Determine placement target: explicit param or auto-detect
        let detectedTarget: DLLPlacementTarget
        if let targetStr = input["target"]?.asString {
            switch targetStr {
            case "syswow64": detectedTarget = .syswow64
            case "system32": detectedTarget = .system32
            default: detectedTarget = .gameDir
            }
        } else {
            // Auto-detect using KnownDLL metadata and bottle layout
            detectedTarget = knownDLL.isSystemDLL
                ? DLLPlacementTarget.autoDetect(bottleURL: config.bottleURL, dllBitness: 32, isSystemDLL: true)
                : .gameDir
        }

        // Map target enum to actual directory URL
        let targetDir: URL
        let targetName: String
        switch detectedTarget {
        case .gameDir:
            targetDir = URL(fileURLWithPath: config.executablePath).deletingLastPathComponent()
            targetName = "game_dir"
        case .system32:
            targetDir = config.bottleURL.appendingPathComponent("drive_c/windows/system32")
            targetName = "system32"
        case .syswow64:
            targetDir = config.bottleURL.appendingPathComponent("drive_c/windows/syswow64")
            targetName = "syswow64"
        }

        do {
            print("Downloading \(knownDLL.name) from GitHub...")
            let cachedDLL = try await DLLDownloader.downloadAndCache(knownDLL)
            let placedDLL = try DLLDownloader.place(cachedDLL: cachedDLL, into: targetDir)
            print("Placed \(placedDLL.lastPathComponent) in \(targetDir.path)")

            // Write companion files to the same directory as the DLL
            var companionPaths: [String] = []
            for companion in knownDLL.companionFiles {
                let companionURL = targetDir.appendingPathComponent(companion.filename)
                try companion.content.write(to: companionURL, atomically: true, encoding: .utf8)
                companionPaths.append(companionURL.path)
                print("Wrote companion file: \(companion.filename)")
            }

            // Apply required DLL overrides by accumulating into env
            var appliedOverrides: [String: String] = [:]
            for (dll, mode) in knownDLL.requiredOverrides {
                let override = "\(dll)=\(mode)"
                let key = "WINEDLLOVERRIDES"
                let current = session.accumulatedEnv[key] ?? ""
                session.accumulatedEnv[key] = current.isEmpty ? override : "\(current);\(override)"
                appliedOverrides[dll] = mode
            }

            return jsonResult([
                "status": "ok",
                "dll_name": knownDLL.name,
                "dll_file": knownDLL.dllFileName,
                "placed_at": placedDLL.path,
                "target": targetName,
                "companion_files": companionPaths,
                "applied_overrides": appliedOverrides
            ])
        } catch {
            return jsonResult(["error": "Failed to download/place \(dllName): \(error.localizedDescription)"])
        }
    }

    // MARK: 11. write_game_file

    func writeGameFile(input: JSONValue) -> String {
        guard let relativePath = input["relative_path"]?.asString, !relativePath.isEmpty else {
            return jsonResult(["error": "relative_path is required"])
        }
        guard let content = input["content"]?.asString else {
            return jsonResult(["error": "content is required"])
        }

        let gameDir = URL(fileURLWithPath: config.executablePath).deletingLastPathComponent()

        // Normalize: replace backslashes with forward slashes
        let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")

        // Build target URL and resolve to canonical path
        let targetURL = gameDir.appendingPathComponent(normalizedPath).standardized

        // Security check: resolved path must be under gameDir
        let gameDirPath = gameDir.standardized.path
        guard targetURL.path.hasPrefix(gameDirPath) else {
            return jsonResult(["error": "Path traversal denied: resolved path is outside the game directory"])
        }

        // Create intermediate directories
        let parentDir = targetURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            return jsonResult(["error": "Failed to create directories: \(error.localizedDescription)"])
        }

        // Back up existing file before overwriting
        let fm = FileManager.default
        var backedUp = false
        var backupPath = ""
        if fm.fileExists(atPath: targetURL.path) {
            let backupURL = targetURL.appendingPathExtension("cellar-backup")
            try? fm.removeItem(at: backupURL)  // Remove stale backup
            do {
                try fm.copyItem(at: targetURL, to: backupURL)
                backedUp = true
                backupPath = backupURL.path
            } catch {
                // Non-fatal — warn but continue
                print("[write_game_file] Warning: could not back up \(targetURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Write file atomically
        do {
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
            var result: [String: Any] = [
                "status": "ok",
                "written_to": targetURL.path
            ]
            if backedUp {
                result["backup"] = backupPath
                result["note"] = "Original file backed up to \(targetURL.lastPathComponent).cellar-backup. If the game breaks, the backup can be restored."
            }
            return jsonResult(result)
        } catch {
            return jsonResult(["error": "Failed to write file: \(error.localizedDescription)"])
        }
    }

    // MARK: 11b. read_game_file

    func readGameFile(input: JSONValue) -> String {
        guard let relativePath = input["relative_path"]?.asString, !relativePath.isEmpty else {
            return jsonResult(["error": "relative_path is required"])
        }

        let gameDir = URL(fileURLWithPath: config.executablePath).deletingLastPathComponent()
        let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
        let targetURL = gameDir.appendingPathComponent(normalizedPath).standardized

        // Security check
        let gameDirPath = gameDir.standardized.path
        guard targetURL.path.hasPrefix(gameDirPath) else {
            return jsonResult(["error": "Path traversal denied: resolved path is outside the game directory"])
        }

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return jsonResult(["error": "File not found: \(relativePath)"])
        }

        do {
            let content = try String(contentsOf: targetURL, encoding: .utf8)
            let truncated = content.count > 16000
            let output = truncated ? String(content.prefix(16000)) : content
            var result: [String: Any] = [
                "status": "ok",
                "path": relativePath,
                "content": output
            ]
            if truncated {
                result["truncated"] = true
                result["total_length"] = content.count
            }
            return jsonResult(result)
        } catch {
            return jsonResult(["error": "Failed to read file: \(error.localizedDescription)"])
        }
    }
}

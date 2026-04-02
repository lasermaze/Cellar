import Foundation

struct WineActionExecutor {
    let wineProcess: WineProcess
    let wineURL: URL
    let bottleURL: URL
    let gameDir: URL   // game executable's parent directory inside bottle

    /// Execute a single WineFix action. Returns true if action succeeded.
    /// Failures: prints warning and returns false (repair loop continues).
    /// The envConfigs tuple includes actions field from LaunchCommand.
    func execute(
        _ fix: WineFix,
        envConfigs: inout [(description: String, environment: [String: String], actions: [WineFix])],
        configIndex: Int,
        installedDeps: inout Set<String>
    ) async -> Bool {
        switch fix {
        case .installWinetricks(let verb):
            guard !installedDeps.contains(verb) else { return true }
            guard let winetricksURL = DependencyChecker().checkAll().winetricks else {
                print("Warning: winetricks not found, skipping verb '\(verb)'")
                return false
            }
            let runner = WinetricksRunner(
                winetricksURL: winetricksURL,
                wineBinary: wineURL,
                bottlePath: bottleURL.path
            )
            do {
                let result = try runner.install(verb: verb)
                installedDeps.insert(verb)
                if result.success {
                    print("Installed winetricks verb '\(verb)'")
                    return true
                } else {
                    print("Warning: winetricks verb '\(verb)' failed")
                    return false
                }
            } catch {
                print("Warning: winetricks error for '\(verb)': \(error.localizedDescription)")
                return false
            }

        case .setEnvVar(let key, let value):
            envConfigs[configIndex].environment[key] = value
            print("Set \(key)=\(value)")
            return true

        case .setDLLOverride(let dll, let mode):
            let override = "\(dll)=\(mode)"
            let key = "WINEDLLOVERRIDES"
            let current = envConfigs[configIndex].environment[key] ?? ""
            let newValue = current.isEmpty ? override : "\(current);\(override)"
            envConfigs[configIndex].environment[key] = newValue
            print("DLL override: \(override)")
            return true

        case .placeDLL(let dllName, let target):
            guard let knownDLL = KnownDLLRegistry.find(name: dllName) else {
                print("Warning: '\(dllName)' is not in the known DLL registry. Skipping auto-download.")
                print("  If you have this DLL, place it manually in: \(gameDir.path)")
                return false
            }

            do {
                print("Downloading \(knownDLL.name) from GitHub...")
                let cachedDLL = try await DLLDownloader.downloadAndCache(knownDLL)

                let targetDir: URL
                switch target {
                case .gameDir:
                    targetDir = gameDir
                case .system32:
                    targetDir = bottleURL
                        .appendingPathComponent("drive_c")
                        .appendingPathComponent("windows")
                        .appendingPathComponent("system32")
                case .syswow64:
                    targetDir = bottleURL
                        .appendingPathComponent("drive_c")
                        .appendingPathComponent("windows")
                        .appendingPathComponent("syswow64")
                }
                let placed = try DLLDownloader.place(cachedDLL: cachedDLL, into: targetDir)
                print("Placed \(placed.lastPathComponent) in \(targetDir.path)")

                // Apply required DLL overrides (e.g. ddraw=n,b for cnc-ddraw)
                for (dll, mode) in knownDLL.requiredOverrides {
                    _ = await execute(.setDLLOverride(dll, mode), envConfigs: &envConfigs, configIndex: configIndex, installedDeps: &installedDeps)
                }

                return true
            } catch {
                // Download failures skip and continue (per decisions)
                print("Warning: Failed to download/place \(dllName): \(error.localizedDescription)")
                return false
            }

        case .setRegistry(let keyPath, let valueName, let data):
            // Format as .reg file content, write to temp file, apply via wine regedit
            var regContent = "Windows Registry Editor Version 5.00\n\n"
            regContent += "[\(keyPath)]\n"
            regContent += "\"\(valueName)\"=\(data)\n"

            let tempFile = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".reg")
            do {
                try regContent.write(to: tempFile, atomically: true, encoding: .utf8)
                try wineProcess.applyRegistryFile(at: tempFile)
                try? FileManager.default.removeItem(at: tempFile)
                print("Registry: \(keyPath) \(valueName)=\(data)")
                return true
            } catch {
                try? FileManager.default.removeItem(at: tempFile)
                print("Warning: Registry edit failed: \(error.localizedDescription)")
                return false
            }

        case .compound(let fixes):
            var allSucceeded = true
            for subFix in fixes {
                if await !execute(subFix, envConfigs: &envConfigs, configIndex: configIndex, installedDeps: &installedDeps) {
                    allSucceeded = false
                    // Continue executing remaining sub-actions even if one fails
                }
            }
            return allSucceeded
        }
    }
}

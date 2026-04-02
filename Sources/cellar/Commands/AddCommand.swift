import ArgumentParser
import Foundation

struct AddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a game by running its installer inside a Wine bottle"
    )

    @Argument(help: "Path to the game installer (e.g. setup.exe)")
    var installerPath: String

    @Flag(help: "Pre-install recipe dependencies before running installer (old behavior)")
    var forceProactiveDeps: Bool = false

    mutating func run() async throws {
        let installerURL = URL(fileURLWithPath: installerPath)

        // 1. Verify installer exists
        guard FileManager.default.fileExists(atPath: installerURL.path) else {
            print("Error: Installer not found at \(installerPath)")
            print("Try this: Check the path exists with: ls \(installerPath)")
            throw ExitCode.failure
        }

        // 2. Check dependencies — offer inline install if missing
        var status = DependencyChecker().checkAll()
        if !status.allRequired {
            print("Missing dependencies detected. Setting up now...\n")
            let installer = GuidedInstaller()
            if status.homebrew == nil {
                installer.installHomebrew()
                status = DependencyChecker().checkAll()
            }
            if status.homebrew != nil && status.wine == nil {
                installer.installWine()
                status = DependencyChecker().checkAll()
            }
            guard status.allRequired else {
                print("Error: Dependencies could not be installed automatically.")
                print("Try this: Run `cellar` for step-by-step setup guidance.")
                throw ExitCode.failure
            }
            print("\nDependencies installed successfully. Continuing with game installation...\n")
        }
        guard let wineURL = status.wine else {
            print("Error: Wine is not installed.")
            print("Try this: Run `cellar` for step-by-step setup guidance.")
            throw ExitCode.failure
        }

        // 3. Derive game name and ID from installer filename (strip extension)
        let installerName = installerURL.deletingPathExtension().lastPathComponent
        let gameName = installerName.replacingOccurrences(of: "_", with: " ")
        let gameId = slugify(installerName)

        // 4. Check if game already exists
        if let _ = try? CellarStore.findGame(id: gameId) {
            print("Game already added. Use `cellar launch \(gameId)` to play.")
            throw ExitCode.success
        }

        print("Adding game: \(gameName)")

        // 5. Create bottle
        let bottleManager = BottleManager(wineBinary: wineURL)
        _ = try bottleManager.createBottle(gameId: gameId)

        // 6. Load recipe
        let recipe = try RecipeEngine.findBundledRecipe(for: gameId)

        // 7. Proactive mode (--force-proactive-deps): install recipe deps upfront
        if forceProactiveDeps, let deps = recipe?.setupDeps, !deps.isEmpty {
            guard let winetricksURL = status.winetricks else {
                print("Error: winetricks is required for --force-proactive-deps but was not found.")
                print("Try this: Run `brew install winetricks` to install winetricks.")
                throw ExitCode.failure
            }
            let runner = WinetricksRunner(winetricksURL: winetricksURL, wineBinary: wineURL, bottlePath: CellarPaths.bottleDir(for: gameId).path)
            for dep in deps {
                print("Pre-installing dependency: \(dep)...")
                let result = try runner.install(verb: dep)
                if result.timedOut {
                    print("Warning: winetricks \(dep) timed out (stale output). Skipping.")
                } else if !result.success {
                    print("Warning: winetricks \(dep) failed (exit \(result.exitCode)). Continuing.")
                } else {
                    print("Installed \(dep) successfully.")
                }
            }
        }

        // 8. Run installer (first attempt)
        let wineProcess = WineProcess(wineBinary: wineURL, winePrefix: CellarPaths.bottleDir(for: gameId))
        print("Running installer inside Wine bottle...")
        let installerResult = try wineProcess.run(
            binary: installerURL.path,
            arguments: ["/VERYSILENT", "/SP-", "/SUPPRESSMSGBOXES"],
            environment: [:]
        )

        // 9. Reactive dep install: if installer failed, diagnose and retry
        if installerResult.exitCode != 0 && !forceProactiveDeps {
            let errors = WineErrorParser.parseLegacy(installerResult.stderr)
            var installed = false

            // Try diagnosed fix first
            for error in errors {
                if case .installWinetricks(let verb) = error.suggestedFix {
                    guard let winetricksURL = status.winetricks else {
                        print("Error: winetricks needed to install \(verb) but not found.")
                        print("Try this: Run `brew install winetricks` to install winetricks.")
                        throw ExitCode.failure
                    }
                    print("Installer failed — diagnosed: \(error.detail)")
                    print("Installing \(verb) via winetricks...")
                    let runner = WinetricksRunner(winetricksURL: winetricksURL, wineBinary: wineURL, bottlePath: CellarPaths.bottleDir(for: gameId).path)
                    let wtResult = try runner.install(verb: verb)
                    if wtResult.success {
                        installed = true
                        print("Installed \(verb). Retrying installer...")
                        let retryResult = try wineProcess.run(
                            binary: installerURL.path,
                            arguments: ["/VERYSILENT", "/SP-", "/SUPPRESSMSGBOXES"],
                            environment: [:]
                        )
                        if retryResult.exitCode == 0 {
                            print("Installer succeeded on retry.")
                        }
                    } else if wtResult.timedOut {
                        print("Warning: \(verb) install timed out.")
                    }
                    break  // Only try first diagnosed fix
                }
            }

            // Fallback: if no diagnosis but recipe has setup_deps, offer them
            if !installed, let deps = recipe?.setupDeps, !deps.isEmpty {
                print("Installer failed with no specific diagnosis.")
                print("Recipe suggests these dependencies: \(deps.joined(separator: ", "))")
                print("Install them now? [y/n] ", terminator: "")
                fflush(stdout)
                let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
                if answer == "y" {
                    guard let winetricksURL = status.winetricks else {
                        print("Error: winetricks not found.")
                        print("Try this: Run `brew install winetricks` to install winetricks.")
                        throw ExitCode.failure
                    }
                    let runner = WinetricksRunner(winetricksURL: winetricksURL, wineBinary: wineURL, bottlePath: CellarPaths.bottleDir(for: gameId).path)
                    for dep in deps {
                        print("Installing \(dep)...")
                        let wtResult = try runner.install(verb: dep)
                        if wtResult.timedOut {
                            print("Warning: \(dep) timed out. Skipping remaining deps.")
                            break
                        } else if !wtResult.success {
                            print("Warning: \(dep) failed (exit \(wtResult.exitCode)).")
                        }
                    }
                    print("Retrying installer...")
                    _ = try wineProcess.run(
                        binary: installerURL.path,
                        arguments: ["/VERYSILENT", "/SP-", "/SUPPRESSMSGBOXES"],
                        environment: [:]
                    )
                }
            }
        }

        // 10. Post-install scan and validation (AGENT-04, AGENT-05, AGENT-06)
        let bottleURL = CellarPaths.bottleDir(for: gameId)
        let discovered = BottleScanner.scanForExecutables(bottlePath: bottleURL)

        // Validate expected install directory (AGENT-05)
        if let installDir = recipe?.installDir {
            let expectedDir = bottleURL
                .appendingPathComponent("drive_c")
                .appendingPathComponent(installDir)
                .resolvingSymlinksInPath()
            if !FileManager.default.fileExists(atPath: expectedDir.path) {
                print("Warning: Expected install directory not found: \(installDir)")
                print("The installer may have used a different path. Checking for executables...")
            }
        }

        if discovered.isEmpty {
            print("Warning: No game executables found in the bottle.")
            print("The installation may have failed. Check Wine output above for errors.")
            print("You can try running `cellar add \(installerPath)` again.")
        } else {
            print("Found \(discovered.count) executable(s):")
            for exe in discovered.prefix(5) {
                let resolvedDriveC: String = {
                    guard let r = realpath(bottleURL.appendingPathComponent("drive_c").path, nil) else {
                        return bottleURL.appendingPathComponent("drive_c").path + "/"
                    }
                    let s = String(cString: r) + "/"
                    free(r)
                    return s
                }()
                let relativePath = exe.path.replacingOccurrences(of: resolvedDriveC, with: "")
                print("  \(relativePath)")
            }
        }

        // Discover executable path (AGENT-06)
        var executablePath: String? = nil
        if let recipe = recipe {
            if let found = BottleScanner.findExecutable(named: recipe.executable, in: discovered) {
                executablePath = found.path
                print("Game executable: \(recipe.executable) -> \(found.path)")
            } else if !discovered.isEmpty {
                print("Warning: Expected executable '\(recipe.executable)' not found.")
                print("Using first discovered executable: \(discovered[0].lastPathComponent)")
                executablePath = discovered[0].path
            }
        } else if !discovered.isEmpty {
            executablePath = discovered[0].path
        }

        // 11. AI Recipe Generation: if no bundled recipe, try AI
        var activeRecipe: Recipe? = recipe
        if recipe == nil {
            // Build file context for AI: exe + dll + config files, capped at 50
            var fileContext: [URL] = discovered  // already have exe list from scan
            // Add DLLs and config files from game install directory only
            let driveCURL = bottleURL.appendingPathComponent("drive_c")
            // Collect file URLs synchronously to avoid async context restriction on NSEnumerator
            fileContext += collectInstalledFiles(in: driveCURL, limit: 50)

            switch await AIService.generateRecipe(gameName: gameName, gameId: gameId, installedFiles: fileContext) {
            case .success(let aiRecipe):
                print("\nAI generated recipe for \(gameName):")
                // Display with same transparency as bundled recipes
                if !aiRecipe.environment.isEmpty {
                    for (key, value) in aiRecipe.environment.sorted(by: { $0.key < $1.key }) {
                        print("  Environment: \(key)=\(value)")
                    }
                }
                if !aiRecipe.registry.isEmpty {
                    for entry in aiRecipe.registry {
                        print("  Registry: \(entry.description)")
                    }
                }
                if let deps = aiRecipe.setupDeps, !deps.isEmpty {
                    print("  Dependencies: \(deps.joined(separator: ", "))")
                }
                // Save for reuse on next launch
                try RecipeEngine.saveUserRecipe(aiRecipe)
                activeRecipe = aiRecipe
                // Update executablePath from AI recipe if we don't have one yet
                if executablePath == nil, !aiRecipe.executable.isEmpty {
                    if let found = BottleScanner.findExecutable(named: aiRecipe.executable, in: discovered) {
                        executablePath = found.path
                        print("Game executable (from AI recipe): \(aiRecipe.executable) -> \(found.path)")
                    }
                }
            case .unavailable:
                AIService.showAITipIfNeeded()
                print("No recipe available for \(gameName). Continue with defaults? [y/n] ", terminator: "")
                fflush(stdout)
                let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
                if answer != "y" {
                    print("Aborted. You can try again with an API key configured.")
                    throw ExitCode.failure
                }
            case .failed(let msg):
                print("AI recipe generation failed: \(msg)")
                print("No recipe available for \(gameName). Continue with defaults? [y/n] ", terminator: "")
                fflush(stdout)
                let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
                if answer != "y" {
                    print("Aborted.")
                    throw ExitCode.failure
                }
            }
        }

        // 12. Save game entry with discovered executable path
        let entry = GameEntry(
            id: gameId,
            name: gameName,
            installPath: "",
            executablePath: executablePath,
            recipeId: activeRecipe?.id ?? gameId,
            addedAt: Date()
        )
        try CellarStore.addGame(entry)

        print("Game added successfully. Run `cellar launch \(gameId)` to play.")
    }

    // MARK: - Helpers

    /// Collect installed file URLs from drive_c synchronously (avoids NSEnumerator async restriction).
    private func collectInstalledFiles(in driveCURL: URL, limit: Int) -> [URL] {
        var result: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: driveCURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return result }
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            let relativePath = fileURL.path.replacingOccurrences(of: driveCURL.path, with: "")
            if relativePath.hasPrefix("/windows/") { continue }
            if ["dll", "ini", "cfg"].contains(ext) {
                result.append(fileURL)
            }
            if result.count >= limit { break }
        }
        return result
    }

    /// Convert a directory name to a slug: lowercase, spaces to hyphens, strip non-alphanumeric except hyphens.
    private func slugify(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .components(separatedBy: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

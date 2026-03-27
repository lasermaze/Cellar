import ArgumentParser
import Foundation

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a game by running its installer inside a Wine bottle"
    )

    @Argument(help: "Path to the game installer (e.g. setup.exe)")
    var installerPath: String

    mutating func run() throws {
        let installerURL = URL(fileURLWithPath: installerPath)

        // 1. Verify installer exists
        guard FileManager.default.fileExists(atPath: installerURL.path) else {
            print("Error: Installer not found at \(installerPath)")
            throw ExitCode.failure
        }

        // 2. Check dependencies
        let status = DependencyChecker().checkAll()
        guard status.allRequired, let wineURL = status.wine else {
            print("Error: Wine is not installed.")
            print("Run `cellar` first to install dependencies.")
            throw ExitCode.failure
        }

        // 3. Derive game name and ID from installer filename (strip extension)
        let installerName = installerURL.deletingPathExtension().lastPathComponent
        let gameName = installerName.replacingOccurrences(of: "_", with: " ")
        let gameId = slugify(installerName)

        // 4. Check if game already exists
        if let existing = try? CellarStore.findGame(id: gameId), existing != nil {
            print("Game already added. Use `cellar launch \(gameId)` to play.")
            throw ExitCode.success
        }

        print("Adding game: \(gameName)")

        // 5. Create bottle
        let bottleManager = BottleManager(wineBinary: wineURL)
        _ = try bottleManager.createBottle(gameId: gameId)

        // 6. Load recipe and install winetricks setup_deps (AGENT-02)
        let recipe = try RecipeEngine.findBundledRecipe(for: gameId)
        if let deps = recipe?.setupDeps, !deps.isEmpty {
            guard let winetricksURL = status.winetricks else {
                print("Error: winetricks is required to install dependencies but was not found.")
                print("Run `cellar` first to install dependencies.")
                throw ExitCode.failure
            }
            let bottlePath = CellarPaths.bottleDir(for: gameId).path
            for dep in deps {
                print("Installing dependency: \(dep) (this may take several minutes)...")
                let wtProcess = Process()
                wtProcess.executableURL = winetricksURL
                wtProcess.arguments = [dep]
                var env = ProcessInfo.processInfo.environment
                env["WINEPREFIX"] = bottlePath
                wtProcess.environment = env

                // Stream winetricks output in real-time
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                wtProcess.standardOutput = stdoutPipe
                wtProcess.standardError = stderrPipe

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    FileHandle.standardOutput.write(data)
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    FileHandle.standardError.write(data)
                }

                try wtProcess.run()
                wtProcess.waitUntilExit()

                // Drain remaining data
                let r1 = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if !r1.isEmpty { FileHandle.standardOutput.write(r1) }
                let r2 = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !r2.isEmpty { FileHandle.standardError.write(r2) }

                if wtProcess.terminationStatus != 0 {
                    print("Warning: winetricks \(dep) exited with status \(wtProcess.terminationStatus)")
                } else {
                    print("Installed \(dep) successfully.")
                }
            }
        }

        // 7. Run GOG installer inside the bottle
        let wineProcess = WineProcess(
            wineBinary: wineURL,
            winePrefix: CellarPaths.bottleDir(for: gameId)
        )
        print("Running installer inside Wine bottle...")
        try wineProcess.run(
            binary: installerURL.path,
            arguments: ["/VERYSILENT", "/SP-", "/SUPPRESSMSGBOXES"],
            environment: [:]
        )

        // 8. Post-install scan and validation (AGENT-04, AGENT-05, AGENT-06)
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

        // 9. Save game entry with discovered executable path
        let entry = GameEntry(
            id: gameId,
            name: gameName,
            installPath: "",
            executablePath: executablePath,
            recipeId: gameId,
            addedAt: Date()
        )
        try CellarStore.addGame(entry)

        print("Game added successfully. Run `cellar launch \(gameId)` to play.")
    }

    // MARK: - Helpers

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

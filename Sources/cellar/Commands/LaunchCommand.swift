import ArgumentParser
import Foundation

struct LaunchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch an installed game via Wine"
    )

    @Argument(help: "Game name or ID to launch")
    var game: String

    mutating func run() throws {
        // 1. Check dependencies
        let status = DependencyChecker().checkAll()
        guard status.allRequired, let wineURL = status.wine else {
            print("Error: Wine is not installed.")
            print("Run `cellar` first to install dependencies.")
            throw ExitCode.failure
        }

        // 2. Find game
        guard var entry = try CellarStore.findGame(id: game) else {
            print("Game not found. Run `cellar add /path/to/installer` first.")
            throw ExitCode.failure
        }

        // 3. Check bottle exists
        let bottleManager = BottleManager(wineBinary: wineURL)
        guard bottleManager.bottleExists(gameId: game) else {
            print("Error: Bottle for '\(game)' not found. Run `cellar add /path/to/installer` again.")
            throw ExitCode.failure
        }

        let bottleURL = CellarPaths.bottleDir(for: game)
        let wineProcess = WineProcess(wineBinary: wineURL, winePrefix: bottleURL)

        // 4. Load recipe
        let recipe = try RecipeEngine.findBundledRecipe(for: game)
        if recipe == nil {
            print("Warning: No recipe found for \(game). Launching with default Wine settings.")
        }

        // 5. Apply recipe (if found)
        var recipeEnv: [String: String] = [:]
        if let recipe = recipe {
            recipeEnv = try RecipeEngine().apply(recipe: recipe, wineProcess: wineProcess)
        }

        // 6. Determine executable path using GameEntry.executablePath (AGENT-06 consumer)
        let executablePath: String
        if let stored = entry.executablePath {
            // Use the path discovered during `cellar add`
            executablePath = stored
        } else if let recipe = recipe {
            // Fallback: construct from recipe + assumed GOG path (legacy entries without executablePath)
            let gogDir = bottleURL.path + "/drive_c/GOG Games/Cossacks - European Wars"
            executablePath = gogDir + "/" + recipe.executable
        } else {
            print("Error: No executable path stored and no recipe available.")
            print("Re-add the game with `cellar add /path/to/installer`.")
            throw ExitCode.failure
        }

        // 7. Compute gameDir for WineActionExecutor
        let gameDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()

        // 8. Create WineActionExecutor for applying all fix types uniformly
        let executor = WineActionExecutor(
            wineProcess: wineProcess,
            wineURL: wineURL,
            bottleURL: bottleURL,
            gameDir: gameDir
        )

        // 9. Build the list of env configurations to try (base + retry variants with parsed actions)
        var envConfigs: [(description: String, environment: [String: String], actions: [WineFix])] = []
        envConfigs.append((description: "Base recipe configuration", environment: recipeEnv, actions: []))
        if let variants = recipe?.retryVariants {
            for variant in variants {
                // Parse recipe-level actions through AIService.parseWineFix(from:)
                let parsedActions: [WineFix] = (variant.actions ?? []).compactMap { actionDict in
                    AIService.parseWineFix(from: actionDict)
                }
                envConfigs.append((description: variant.description, environment: variant.environment, actions: parsedActions))
            }
        }

        // 10. Self-healing retry loop with graduated escalation (AGENT-09, AGENT-10, AGENT-11)
        var lastResult: WineResult? = nil
        var lastErrors: [WineError] = []
        var attemptCount = 0
        var allAttempts: [(description: String, environment: [String: String], errors: [WineError])] = []
        var appliedActions: [(description: String, actions: [String])] = []  // for repair report

        var installedDeps: Set<String> = []  // Track installed deps to avoid re-installing
        let maxTotalAttempts = 10  // Cap total attempts across dep installs + variant cycling (raised for AI budget)
        var totalAttempts = 0

        var configIndex = 0
        var currentEscalationLevel = 1   // tracks which AI escalation level to call next (1, 2, 3)
        let originalEnvConfigsCount = envConfigs.count
        var winningConfigIndex = 0  // track which config succeeded

        while (configIndex < envConfigs.count || currentEscalationLevel <= 3) && totalAttempts < maxTotalAttempts {
            // AI variant injection — when bundled variants exhausted, escalate and ask AI for more
            if configIndex >= envConfigs.count && currentEscalationLevel <= 3 {
                let level = currentEscalationLevel
                currentEscalationLevel += 1

                let escalationMessages = [
                    1: "Trying environment variable adjustments...",
                    2: "Escalating to DLL overrides and winetricks...",
                    3: "Escalating to DLL replacements and registry edits..."
                ]
                print("\n\(escalationMessages[level] ?? "Trying next escalation level...")")

                let history: [(description: String, envDiff: [String: String], errorSummary: String)] = allAttempts.map { attempt in
                    let errorSummary = attempt.errors.map { $0.detail }.joined(separator: "; ")
                    let capped = String(errorSummary.prefix(500))
                    return (description: attempt.description, envDiff: attempt.environment, errorSummary: capped)
                }

                switch AIService.generateVariants(
                    gameId: game,
                    gameName: entry.name,
                    currentEnvironment: recipeEnv,
                    attemptHistory: history,
                    escalationLevel: level
                ) {
                case .success(let aiResult):
                    print("AI analysis: \(aiResult.reasoning)")
                    print("Generating \(aiResult.variants.count) alternative configuration(s)...\n")
                    for variant in aiResult.variants {
                        envConfigs.append((description: variant.description, environment: variant.environment, actions: variant.actions))
                    }
                case .unavailable:
                    break  // Silent — no API key is not an error
                case .failed(let msg):
                    print("AI variant generation failed: \(msg)")
                }

                // If no variants were added at this level, try next level immediately
                if configIndex >= envConfigs.count {
                    continue
                }
            }

            // Guard: if all escalation levels exhausted and no variants left, stop
            if configIndex >= envConfigs.count {
                break
            }

            totalAttempts += 1
            attemptCount = totalAttempts
            let config = envConfigs[configIndex]

            if totalAttempts > 1 {
                print("\nAttempt \(totalAttempts): \(config.description)...")
            }

            // Apply variant-level actions (DLL placements, registry edits, etc.) before launch
            if !config.actions.isEmpty {
                var actionDescriptions: [String] = []
                for action in config.actions {
                    let success = executor.execute(action, envConfigs: &envConfigs, configIndex: configIndex, installedDeps: &installedDeps)
                    if success {
                        actionDescriptions.append("\(action)")
                    }
                }
                if !actionDescriptions.isEmpty {
                    appliedActions.append((description: config.description, actions: actionDescriptions))
                }
            }

            // Prepare log file for this attempt
            let launchTimestamp = Date()
            let logFileURL = CellarPaths.logFile(for: game, timestamp: launchTimestamp)
            try FileManager.default.createDirectory(
                at: CellarPaths.logDir(for: game),
                withIntermediateDirectories: true
            )
            print("Log: \(logFileURL.path)")

            // Set up SIGINT handler — Ctrl+C kills Wine but still shows validation prompt
            // WineProcess.run() is synchronous; we use wineserver -k for Wine-aware termination
            signal(SIGINT, SIG_IGN)
            let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            sigintSource.setEventHandler {
                try? wineProcess.killWineserver()
            }
            sigintSource.resume()

            if totalAttempts == 1 {
                print("Launching \(game)...")
            }

            let result = try wineProcess.run(
                binary: executablePath,
                arguments: recipe?.launchArgs ?? [],
                environment: config.environment,
                logFile: logFileURL
            )

            sigintSource.cancel()
            signal(SIGINT, SIG_DFL)

            lastResult = result

            // Hung launch — treat as failed attempt, advance to next variant
            if result.timedOut {
                let errors = WineErrorParser.parse(result.stderr)
                lastErrors = errors
                allAttempts.append((description: config.description, environment: config.environment, errors: errors))
                print("Launch timed out (no output for 5 minutes). Moving to next variant...")
                configIndex += 1
                if totalAttempts >= maxTotalAttempts { break }
                continue
            }

            // Check if launch ran long enough to possibly be a real session
            if result.exitCode == 0 || result.elapsed > 2.0 {
                // Ask the user — did it actually work?
                let validation = ValidationPrompt.run(
                    gameId: game,
                    elapsed: result.elapsed,
                    wineProcess: wineProcess
                )
                if validation?.reachedMenu == true {
                    winningConfigIndex = configIndex
                    break
                }
                // User said no — treat as failed attempt, continue retry loop
                var errors = WineErrorParser.parse(result.stderr)
                // Include user's observation as an error context for AI
                if let observation = validation?.userObservation {
                    errors.append(WineError(category: .unknown, detail: "User reported: \(observation)", suggestedFix: nil))
                }
                lastErrors = errors
                allAttempts.append((description: config.description, environment: config.environment, errors: errors))
                configIndex += 1
                if totalAttempts >= maxTotalAttempts { break }
                continue
            }

            // Quick exit — parse errors
            let errors = WineErrorParser.parse(result.stderr)
            lastErrors = errors
            allAttempts.append((description: config.description, environment: config.environment, errors: errors))

            // Apply any error-diagnosed fix via WineActionExecutor BEFORE advancing variant
            var depInstalled = false
            if let suggestedFix = errors.first?.suggestedFix {
                print("Diagnosed: \(errors.first!.detail)")
                let success = executor.execute(suggestedFix, envConfigs: &envConfigs, configIndex: configIndex, installedDeps: &installedDeps)
                if success { depInstalled = true }
            }

            if !depInstalled {
                // AI diagnosis: try when WineErrorParser has no actionable fix
                let hasActionableFix = errors.contains { $0.suggestedFix != nil }
                if !hasActionableFix {
                    let truncatedStderr = String(result.stderr.suffix(8000))
                    switch AIService.diagnose(stderr: truncatedStderr, gameId: game) {
                    case .success(let diagnosis):
                        print("\nAI diagnosis: \(diagnosis.explanation)")
                        if let fix = diagnosis.suggestedFix {
                            print("AI suggests: \(fix)")
                            let success = executor.execute(fix, envConfigs: &envConfigs, configIndex: configIndex, installedDeps: &installedDeps)
                            if success { depInstalled = true }
                        }
                    case .unavailable:
                        break  // Silent -- no API key is not an error during launch
                    case .failed(let msg):
                        print("AI diagnosis unavailable: \(msg)")
                    }
                }

                if !depInstalled {
                    // No fix applied — advance to next variant
                    if errors.isEmpty {
                        print("Wine exited in \(String(format: "%.1f", result.elapsed))s with no diagnosed errors.")
                    } else if errors.first?.suggestedFix == nil {
                        print("Diagnosed: \(errors.first!.detail)")
                    }
                    configIndex += 1
                }
            }

            if totalAttempts >= maxTotalAttempts {
                break
            }
        }

        // 9. Post-loop: handle exhausted retries or normal exit

        guard let finalResult = lastResult else {
            print("Error: No launch result available.")
            throw ExitCode.failure
        }

        // Exhausted retries and still failed (AGENT-11)
        if (finalResult.elapsed < 2.0 || finalResult.timedOut) && finalResult.exitCode != 0 && totalAttempts >= maxTotalAttempts {
            print("\n--- Launch Failed ---")
            print("Exhausted \(totalAttempts) attempt(s). Summary:")
            for (i, attempt) in allAttempts.enumerated() {
                print("  Attempt \(i + 1): \(attempt.description)")
                if attempt.errors.isEmpty {
                    print("    No specific errors diagnosed")
                } else {
                    for error in attempt.errors {
                        print("    - \(error.detail)")
                    }
                }
            }
            if let bestDiagnosis = lastErrors.first {
                print("\nBest diagnosis: \(bestDiagnosis.detail)")
                if let fix = bestDiagnosis.suggestedFix {
                    switch fix {
                    case .installWinetricks(let verb):
                        print("Suggested fix: Install '\(verb)' via winetricks")
                    case .setEnvVar(let key, let value):
                        print("Suggested fix: Set \(key)=\(value)")
                    case .setDLLOverride(let dll, let mode):
                        print("Suggested fix: Set DLL override \(dll)=\(mode)")
                    case .placeDLL(let name, _):
                        print("Suggested fix: Place DLL '\(name)' in game directory")
                    case .setRegistry(let key, let name, let data):
                        print("Suggested fix: Set registry \(key) \(name)=\(data)")
                    case .compound(let fixes):
                        print("Suggested fix: Compound fix (\(fixes.count) actions)")
                    }
                }
            }

            // Write repair report
            let reportTimestamp = Date()
            let reportURL = CellarPaths.repairReportFile(for: game, timestamp: reportTimestamp)
            var reportLines: [String] = []
            reportLines.append("Cellar Repair Report")
            reportLines.append("Game: \(game)")
            reportLines.append("Date: \(reportTimestamp)")
            reportLines.append("Total attempts: \(totalAttempts)")
            reportLines.append("")
            reportLines.append("--- Attempt History ---")
            for (i, attempt) in allAttempts.enumerated() {
                reportLines.append("")
                reportLines.append("Attempt \(i + 1): \(attempt.description)")
                reportLines.append("Environment:")
                for (key, value) in attempt.environment.sorted(by: { $0.key < $1.key }) {
                    reportLines.append("  \(key)=\(value)")
                }
                if attempt.errors.isEmpty {
                    reportLines.append("Errors: None diagnosed")
                } else {
                    reportLines.append("Errors:")
                    for error in attempt.errors {
                        reportLines.append("  - \(error.detail)")
                    }
                }
            }
            reportLines.append("")
            reportLines.append("--- Best Diagnosis ---")
            if let bestDiagnosis = lastErrors.first {
                reportLines.append(bestDiagnosis.detail)
                if let fix = bestDiagnosis.suggestedFix {
                    switch fix {
                    case .installWinetricks(let verb):
                        reportLines.append("Suggested: Install '\(verb)' via winetricks")
                    case .setEnvVar(let key, let value):
                        reportLines.append("Suggested: Set \(key)=\(value)")
                    case .setDLLOverride(let dll, let mode):
                        reportLines.append("Suggested: DLL override \(dll)=\(mode)")
                    case .placeDLL(let name, _):
                        reportLines.append("Suggested: Place DLL '\(name)' in game directory")
                    case .setRegistry(let key, let name, let data):
                        reportLines.append("Suggested: Set registry \(key) \(name)=\(data)")
                    case .compound(let fixes):
                        reportLines.append("Suggested: Compound fix (\(fixes.count) actions)")
                    }
                }
            } else {
                reportLines.append("No specific errors diagnosed.")
            }
            // Applied actions section
            if !appliedActions.isEmpty {
                reportLines.append("")
                reportLines.append("--- Applied Actions ---")
                for actionEntry in appliedActions {
                    reportLines.append("Variant: \(actionEntry.description)")
                    for action in actionEntry.actions {
                        reportLines.append("  \(action)")
                    }
                }
            }
            reportLines.append("")
            reportLines.append("--- Logs ---")
            reportLines.append("Log directory: \(CellarPaths.logDir(for: game).path)")
            let reportContent = reportLines.joined(separator: "\n")
            try? reportContent.write(to: reportURL, atomically: true, encoding: .utf8)
            print("Repair report saved: \(reportURL.path)")

            print("\nCheck the latest log for details: \(CellarPaths.logDir(for: game).path)")

            // Record the failed result
            entry.lastLaunched = Date()
            entry.lastResult = LaunchResult(
                timestamp: Date(),
                reachedMenu: false,
                attemptCount: attemptCount,
                diagnosis: lastErrors.first?.detail
            )
            try CellarStore.updateGame(entry)
            return
        }

        // Normal post-exit: user already confirmed via in-loop validation prompt
        let reachedMenu = true

        // Save winning AI variant as user recipe if it came from AI stage
        if winningConfigIndex >= originalEnvConfigsCount,
           let baseRecipe = recipe {
            let winningConfig = envConfigs[winningConfigIndex]
            let winningEnv = winningConfig.environment
            let winningActions = winningConfig.actions
            // Show winning config diff
            let diffKeys = winningEnv.filter { baseRecipe.environment[$0.key] != $0.value }
            if !diffKeys.isEmpty {
                print("\nSaving winning configuration:")
                for (key, value) in diffKeys.sorted(by: { $0.key < $1.key }) {
                    print("  \(key)=\(value)")
                }
            }
            // Build updated recipe with AI variant environment merged over base
            var mergedEnv = baseRecipe.environment
            for (key, value) in winningEnv {
                mergedEnv[key] = value
            }
            // Include actions as a new retry variant if present
            var updatedVariants = baseRecipe.retryVariants ?? []
            if !winningActions.isEmpty {
                let actionDicts: [[String: String]] = winningActions.compactMap { fix -> [String: String]? in
                    switch fix {
                    case .placeDLL(let name, let target):
                        return ["type": "place_dll", "dll": name, "target": target == .system32 ? "system32" : "game_dir"]
                    case .setRegistry(let key, let valueName, let data):
                        return ["type": "set_registry", "key": key, "value_name": valueName, "data": data]
                    case .setDLLOverride(let dll, let mode):
                        return ["type": "set_dll_override", "dll": dll, "mode": mode]
                    case .installWinetricks(let verb):
                        return ["type": "install_winetricks", "verb": verb]
                    case .setEnvVar(let k, let v):
                        return ["type": "set_env", "key": k, "value": v]
                    case .compound:
                        return nil  // compound not serialized directly
                    }
                }
                let winningVariant = RetryVariant(
                    description: winningConfig.description,
                    environment: diffKeys,
                    actions: actionDicts.isEmpty ? nil : actionDicts
                )
                updatedVariants.append(winningVariant)
            }
            let updatedRecipe = Recipe(
                id: baseRecipe.id, name: baseRecipe.name, version: baseRecipe.version,
                source: baseRecipe.source, executable: baseRecipe.executable,
                wineTested: baseRecipe.wineTested, environment: mergedEnv,
                registry: baseRecipe.registry, launchArgs: baseRecipe.launchArgs,
                notes: baseRecipe.notes, setupDeps: baseRecipe.setupDeps,
                installDir: baseRecipe.installDir, retryVariants: updatedVariants.isEmpty ? nil : updatedVariants
            )
            try RecipeEngine.saveUserRecipe(updatedRecipe)
        } else if winningConfigIndex >= originalEnvConfigsCount,
                  recipe == nil {
            // No base recipe — build minimal recipe from winning env
            let winningEnv = envConfigs[winningConfigIndex].environment
            print("\nSaving winning configuration:")
            for (key, value) in winningEnv.sorted(by: { $0.key < $1.key }) {
                print("  \(key)=\(value)")
            }
            let minimalRecipe = Recipe(
                id: game, name: game, version: "1.0.0", source: "ai-generated",
                executable: executablePath, wineTested: nil, environment: winningEnv,
                registry: [], launchArgs: [], notes: "Auto-generated from successful AI variant",
                setupDeps: nil, installDir: nil, retryVariants: nil
            )
            try RecipeEngine.saveUserRecipe(minimalRecipe)
        }

        entry.lastLaunched = Date()
        entry.lastResult = LaunchResult(
            timestamp: Date(),
            reachedMenu: reachedMenu,
            attemptCount: attemptCount,
            diagnosis: lastErrors.isEmpty ? nil : lastErrors.first?.detail
        )
        try CellarStore.updateGame(entry)
        print("Launch result recorded.")
    }
}

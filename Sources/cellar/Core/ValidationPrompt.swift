import Foundation

struct ValidationResult {
    let reachedMenu: Bool
    let userObservation: String?  // What the user saw when game didn't work
}

struct ValidationPrompt {
    /// Run the post-launch validation prompt: wineserver shutdown + "did game reach menu?" question.
    ///
    /// Returns ValidationResult with reachedMenu and optional user observation,
    /// or nil if the game exited too quickly (crash detection).
    static func run(gameId: String, elapsed: TimeInterval, wineProcess: WineProcess) -> ValidationResult? {
        // 1. Quick-exit detection: < 2 seconds means likely a crash
        if elapsed < 2.0 {
            let elapsedStr = String(format: "%.1f", elapsed)
            print("Wine exited in \(elapsedStr)s -- likely a crash.")
            print("Check logs: ~/.cellar/logs/\(gameId)/")
            return nil
        }

        // 2. Wineserver shutdown prompt
        print("Shut down Wine services? [y/n] ", terminator: "")
        fflush(stdout)
        let shutdownResponse = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if shutdownResponse == "y" {
            try? wineProcess.killWineserver()
        }

        // 3. Validation prompt
        print("Did the game reach the menu? [y/n] ", terminator: "")
        fflush(stdout)
        let validationResponse = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if validationResponse == "y" {
            return ValidationResult(reachedMenu: true, userObservation: nil)
        }

        // 4. Ask what the user saw — feeds into AI variant generation
        print("What did you see? (e.g., black screen, error dialog, crash): ", terminator: "")
        fflush(stdout)
        let observation = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return ValidationResult(
            reachedMenu: false,
            userObservation: observation.isEmpty ? nil : observation
        )
    }
}

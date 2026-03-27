import Foundation

struct ValidationPrompt {
    /// Run the full post-launch flow: quick-exit check, wineserver shutdown prompt, validation prompt.
    ///
    /// Returns the LaunchResult to be saved, or nil if the game exited too quickly (crash detection).
    static func run(gameId: String, elapsed: TimeInterval, wineProcess: WineProcess) -> LaunchResult? {
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
        return LaunchResult(timestamp: Date(), reachedMenu: validationResponse == "y")
    }
}

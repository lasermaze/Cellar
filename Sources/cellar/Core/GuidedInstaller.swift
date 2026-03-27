import Foundation

// MARK: - GuidedInstaller

struct GuidedInstaller {

    // MARK: - Public API

    /// Installs Homebrew using the official install script with real-time streaming output.
    /// On failure, offers retry and prints manual fallback instructions.
    func installHomebrew() {
        print("Installing Homebrew...")

        let status = runStreamingProcess(
            executablePath: "/bin/bash",
            arguments: [
                "-c",
                #"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"#,
            ]
        )

        if status != 0 {
            print("\nHomebrew installation failed (exit code \(status)).")
            print("Retry? [y/n] ", terminator: "")
            fflush(stdout)
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
            if answer == "y" {
                installHomebrew()
                return
            } else {
                print("\nTo install Homebrew manually, run:")
                print(#"  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#)
                return
            }
        }

        print("Homebrew installed successfully.")
    }

    /// Taps the Gcenx Wine repository and installs wine-crossover.
    /// After install, removes quarantine flag if Gatekeeper blocks Wine.
    /// On failure, offers retry and prints manual fallback instructions.
    func installWine() {
        guard let brewURL = DependencyChecker().detectHomebrew() else {
            print("Cannot install Wine: Homebrew is not installed. Install Homebrew first.")
            return
        }
        let brewPath = brewURL.path

        // Step 1: tap gcenx/wine
        print("Adding Gcenx Wine tap...")
        let tapStatus = runStreamingProcess(
            executablePath: brewPath,
            arguments: ["tap", "gcenx/wine"]
        )
        if tapStatus != 0 {
            print("\n`brew tap gcenx/wine` failed (exit code \(tapStatus)).")
            print("Retry? [y/n] ", terminator: "")
            fflush(stdout)
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
            if answer == "y" {
                installWine()
                return
            } else {
                print("\nTo add the tap manually, run:")
                print("  brew tap gcenx/wine")
                return
            }
        }

        // Step 2: install wine-crossover (plain brew install — xattr fallback handles Gatekeeper)
        print("Installing Wine (this may take a few minutes)...")
        let installStatus = runStreamingProcess(
            executablePath: brewPath,
            arguments: ["install", "gcenx/wine/wine-crossover"]
        )
        if installStatus != 0 {
            print("\n`brew install gcenx/wine/wine-crossover` failed (exit code \(installStatus)).")
            print("Retry? [y/n] ", terminator: "")
            fflush(stdout)
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
            if answer == "y" {
                installWine()
                return
            } else {
                print("\nTo install Wine manually, run:")
                print("  brew tap gcenx/wine")
                print("  brew install gcenx/wine/wine-crossover")
                return
            }
        }

        // Step 3: check if Wine binary is accessible; if Gatekeeper blocked it, remove quarantine
        let checker = DependencyChecker()
        let wineCheck = checker.checkAll()
        if wineCheck.wine == nil {
            print("Wine installed but may be blocked by Gatekeeper. Removing quarantine flag...")
            if let homebrewURL = checker.detectHomebrew() {
                // Homebrew prefix is two levels up from the brew binary (bin/brew -> prefix/)
                let brewPrefix = homebrewURL.deletingLastPathComponent().deletingLastPathComponent()
                let caskroomPath = brewPrefix.appendingPathComponent("Caskroom/wine-crossover").path
                runStreamingProcess(
                    executablePath: "/usr/bin/xattr",
                    arguments: ["-rd", "com.apple.quarantine", caskroomPath]
                )
            }
        }

        print("Wine installed successfully.")
    }

    /// Installs winetricks via Homebrew.
    /// On failure, offers retry and prints manual fallback instructions.
    func installWinetricks() {
        guard let brewURL = DependencyChecker().detectHomebrew() else {
            print("Cannot install winetricks: Homebrew is not installed.")
            return
        }
        print("Installing winetricks...")
        let status = runStreamingProcess(
            executablePath: brewURL.path,
            arguments: ["install", "winetricks"]
        )
        if status != 0 {
            print("\n`brew install winetricks` failed (exit code \(status)).")
            print("Retry? [y/n] ", terminator: "")
            fflush(stdout)
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
            if answer == "y" {
                installWinetricks()
                return
            } else {
                print("\nTo install winetricks manually, run:")
                print("  brew install winetricks")
                return
            }
        }
        print("winetricks installed successfully.")
    }

    // MARK: - Private helpers

    /// Runs a process with real-time stdout and stderr streaming.
    /// Drains remaining pipe data after process exit (readabilityHandler EOF workaround).
    /// Returns the process termination status.
    @discardableResult
    private func runStreamingProcess(executablePath: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Stream stdout in real-time
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardOutput.write(data)
        }

        // Stream stderr in real-time
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardError.write(data)
        }

        do {
            try process.run()
        } catch {
            print("Failed to launch \(executablePath): \(error)")
            return 1
        }

        process.waitUntilExit()

        // Drain remaining data (readabilityHandler EOF bug workaround — swift-corelibs-foundation #3275)
        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStdout.isEmpty {
            FileHandle.standardOutput.write(remainingStdout)
        }

        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStderr.isEmpty {
            FileHandle.standardError.write(remainingStderr)
        }

        // Disable handlers after drain to prevent further callbacks
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        return process.terminationStatus
    }
}

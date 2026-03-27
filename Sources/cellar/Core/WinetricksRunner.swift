import Foundation

/// Structured result from a winetricks verb installation.
struct WinetricksResult {
    let verb: String
    let success: Bool
    let timedOut: Bool
    let exitCode: Int32
    let elapsed: TimeInterval
}

/// Reusable service for running winetricks verbs with stale-output timeout protection.
struct WinetricksRunner {
    let winetricksURL: URL
    let wineBinary: URL
    let bottlePath: String  // WINEPREFIX path

    /// Thread-safe timestamp tracker for stale-output detection.
    /// Reuses the NSLock + @unchecked Sendable pattern from WineProcess.StderrCapture.
    private final class OutputMonitor: @unchecked Sendable {
        private var _lastOutputTime = Date()
        private let lock = NSLock()

        func touch() {
            lock.lock()
            _lastOutputTime = Date()
            lock.unlock()
        }

        var lastOutputTime: Date {
            lock.lock()
            defer { lock.unlock() }
            return _lastOutputTime
        }
    }

    /// Install a winetricks verb inside the bottle, with stale-output timeout protection.
    ///
    /// The 5-minute stale-output timeout kills the process (and wineserver) if no output
    /// has been produced for that duration — covering the case where winetricks hangs
    /// silently waiting for user interaction that will never come.
    ///
    /// - Parameter verb: The winetricks verb to install (e.g. "vcrun2019", "d3dx9")
    /// - Returns: A WinetricksResult describing outcome, exit code, and whether a timeout occurred.
    @discardableResult
    func install(verb: String) throws -> WinetricksResult {
        let process = Process()
        process.executableURL = winetricksURL
        // -q = unattended mode (no dialogs) per design decision
        process.arguments = ["-q", verb]

        // Inherit current environment and set WINEPREFIX
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottlePath
        env["WINEBINARY"] = wineBinary.path
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let outputMonitor = OutputMonitor()
        let startTime = Date()

        // Real-time stdout streaming + stale-output monitoring
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardOutput.write(data)
            outputMonitor.touch()
        }

        // Real-time stderr streaming + stale-output monitoring
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardError.write(data)
            outputMonitor.touch()
        }

        try process.run()

        // Stale-output detection loop — poll every 2 seconds instead of waitUntilExit()
        let staleTimeout: TimeInterval = 300  // 5 minutes
        var didTimeout = false
        while process.isRunning {
            Thread.sleep(forTimeInterval: 2.0)
            let timeSinceOutput = Date().timeIntervalSince(outputMonitor.lastOutputTime)
            if timeSinceOutput > staleTimeout {
                print("\nwinetricks '\(verb)' has produced no output for \(Int(staleTimeout / 60)) minutes — killing stalled process.")
                process.terminate()
                // Kill wineserver to clean up any Wine child processes
                let wineProcess = WineProcess(wineBinary: wineBinary, winePrefix: URL(fileURLWithPath: bottlePath))
                try? wineProcess.killWineserver()
                // Brief wait for cleanup
                Thread.sleep(forTimeInterval: 1.0)
                didTimeout = true
                break
            }
        }

        // Post-exit drain — flush any remaining buffered output
        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStdout.isEmpty {
            FileHandle.standardOutput.write(remainingStdout)
        }
        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStderr.isEmpty {
            FileHandle.standardError.write(remainingStderr)
        }

        // Prevent spurious callbacks after process exit (matches GuidedInstaller pattern)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let elapsed = Date().timeIntervalSince(startTime)

        return WinetricksResult(
            verb: verb,
            success: !didTimeout && process.terminationStatus == 0,
            timedOut: didTimeout,
            exitCode: process.terminationStatus,
            elapsed: elapsed
        )
    }
}

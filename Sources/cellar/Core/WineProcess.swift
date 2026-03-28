import Foundation

struct WineProcess {
    let wineBinary: URL
    let winePrefix: URL

    /// Thread-safe output monitor for stale-output hang detection.
    private final class OutputMonitor: @unchecked Sendable {
        private var _lastOutputTime = Date()
        private let lock = NSLock()
        func touch() { lock.lock(); _lastOutputTime = Date(); lock.unlock() }
        var lastOutputTime: Date { lock.lock(); defer { lock.unlock() }; return _lastOutputTime }
    }

    /// Thread-safe stderr capture buffer for Swift 6 Sendable compliance.
    private final class StderrCapture: @unchecked Sendable {
        private var buffer = ""
        private let lock = NSLock()
        func append(_ str: String) { lock.lock(); buffer += str; lock.unlock() }
        var value: String { lock.lock(); defer { lock.unlock() }; return buffer }
    }

    /// Run a Wine command with WINEPREFIX set, streaming output to terminal and optionally to a log file.
    /// Returns a WineResult with exit code, captured stderr, elapsed time, and log path.
    @discardableResult
    func run(
        binary: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        logFile: URL? = nil
    ) throws -> WineResult {
        let process = Process()
        process.executableURL = wineBinary

        // Pass binary name and args as an array — NEVER shell string (avoids Windows path escaping issues)
        process.arguments = [binary] + arguments

        // Set CWD to the game binary's parent directory — fixes games that use relative paths
        // (e.g., Missions/Missions.txt, mode.dat)
        let binaryURL = URL(fileURLWithPath: binary)
        process.currentDirectoryURL = binaryURL.deletingLastPathComponent()

        // Build environment: start with current process env, set WINEPREFIX, merge additional env
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefix.path
        // Capture message box text in stderr so error dialogs are visible to the retry loop
        let existingDebug = environment["WINEDEBUG"] ?? env["WINEDEBUG"] ?? ""
        env["WINEDEBUG"] = existingDebug.isEmpty ? "+msgbox" : "\(existingDebug),+msgbox"
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        // Set up stdout and stderr pipes
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Open log file handle if requested — captured as a let constant for Swift 6 Sendable
        let logHandle: FileHandle?
        if let logFile = logFile {
            // Ensure directory exists
            let logDir = logFile.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            // Create the file if it doesn't exist
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
            logHandle = FileHandle(forWritingAtPath: logFile.path)
        } else {
            logHandle = nil
        }

        // Stderr capture buffer (thread-safe)
        let stderrCapture = StderrCapture()
        let outputMonitor = OutputMonitor()
        let startTime = Date()

        // Real-time stdout streaming to terminal + log
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputMonitor.touch()
            FileHandle.standardOutput.write(data)
            logHandle?.write(data)
        }

        // Real-time stderr streaming to terminal + log + capture buffer
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputMonitor.touch()
            FileHandle.standardError.write(data)
            logHandle?.write(data)
            if let str = String(data: data, encoding: .utf8) {
                stderrCapture.append(str)
            }
        }

        try process.run()

        let staleTimeout: TimeInterval = 300  // 5 minutes — per CONTEXT.md decision
        var didTimeout = false
        while process.isRunning {
            Thread.sleep(forTimeInterval: 2.0)
            if Date().timeIntervalSince(outputMonitor.lastOutputTime) > staleTimeout {
                print("\nGame launch has produced no output for \(Int(staleTimeout / 60)) minutes — assuming hung.")
                process.terminate()
                try? killWineserver()
                Thread.sleep(forTimeInterval: 1.0)
                didTimeout = true
                break
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Prevent spurious callbacks after process exit (matches GuidedInstaller pattern)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Close pipe write ends to unblock readDataToEndOfFile — Wine child processes
        // (winedevice, services.exe) inherit these descriptors and keep them open indefinitely,
        // causing readDataToEndOfFile to block forever even after the game exits.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        // Drain remaining data after exit (Pitfall 4: readabilityHandler EOF bug)
        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStdout.isEmpty {
            FileHandle.standardOutput.write(remainingStdout)
            logHandle?.write(remainingStdout)
        }
        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingStderr.isEmpty {
            FileHandle.standardError.write(remainingStderr)
            logHandle?.write(remainingStderr)
            if let str = String(data: remainingStderr, encoding: .utf8) {
                stderrCapture.append(str)
            }
        }

        // Close log file handle
        logHandle?.closeFile()

        return WineResult(
            exitCode: process.terminationStatus,
            stderr: stderrCapture.value,
            elapsed: elapsed,
            logPath: logFile,
            timedOut: didTimeout
        )
    }

    /// Run wineboot with --init to initialize a new prefix.
    func initPrefix() throws {
        // Resolve wineboot binary in same directory as wine
        let winebootBinary = wineBinary.deletingLastPathComponent()
            .appendingPathComponent("wineboot")

        let process = Process()
        process.executableURL = winebootBinary
        process.arguments = ["--init"]

        // Build environment with WINEPREFIX and Gecko/Mono suppression (Pitfall 5)
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefix.path
        env["WINEDLLOVERRIDES"] = "mscoree,mshtml="
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

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

        print("Initializing Wine bottle (first-time setup, may take ~30 seconds)...")

        try process.run()
        process.waitUntilExit()

        // Drain remaining data after exit
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
    }

    /// Run wine regedit with a .reg file.
    func applyRegistryFile(at path: URL) throws {
        try run(binary: "regedit", arguments: [path.path])
    }

    /// Kill wineserver for this prefix.
    func killWineserver() throws {
        let wineserverBinary = wineBinary.deletingLastPathComponent()
            .appendingPathComponent("wineserver")

        let process = Process()
        process.executableURL = wineserverBinary
        process.arguments = ["-k"]

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefix.path
        process.environment = env

        try process.run()
        process.waitUntilExit()
    }
}

import Foundation

/// Structured result returned by WineProcess.run().
/// Captures exit code, stderr (for error parsing), elapsed time, and log path.
struct WineResult {
    let exitCode: Int32
    let stderr: String       // captured stderr for error parsing
    let elapsed: TimeInterval
    let logPath: URL?
}

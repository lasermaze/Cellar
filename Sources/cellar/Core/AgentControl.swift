import Foundation
import os

// MARK: - AgentControl

/// Thread-safe control channel between web UI and agent loop.
///
/// Web routes call `abort()` / `confirm()`. Agent loop reads `shouldAbort` / `userForceConfirmed`.
/// Uses `OSAllocatedUnfairLock` for proper Sendable conformance without `@unchecked`.
final class AgentControl: Sendable {
    private let _lock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var shouldAbort = false
        var userForceConfirmed = false
    }

    var shouldAbort: Bool {
        _lock.withLock { $0.shouldAbort }
    }

    var userForceConfirmed: Bool {
        _lock.withLock { $0.userForceConfirmed }
    }

    func abort() {
        _lock.withLock { $0.shouldAbort = true }
    }

    func confirm() {
        _lock.withLock { $0.userForceConfirmed = true }
    }
}

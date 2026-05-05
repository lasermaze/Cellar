import Foundation

/// Mutable per-session runtime state for the agent loop.
/// Extracted from AgentTools to isolate accumulated state from injected
/// infrastructure (config, control, askUserHandler) and dispatch coordinator logic.
///
/// final class (not actor, not struct) because SessionDraftBuffer is a reference
/// type (final class) and lazy var requires reference semantics.
final class AgentSession {
    /// Wine environment variables accumulated across set_environment calls.
    var accumulatedEnv: [String: String] = [:]

    var launchCount: Int = 0
    let maxLaunches: Int = 8

    var installedDeps: Set<String> = []
    var lastLogFile: URL? = nil

    /// Actions taken since the last launch_game call.
    var pendingActions: [String] = []

    /// Actions that were pending at the time of the last launch_game call.
    var lastAppliedActions: [String] = []

    /// WineDiagnostics from the most recent launch, for inter-launch diff.
    var previousDiagnostics: WineDiagnostics? = nil

    /// Set by save_failure tool when agent reports a substantive failure.
    var hasSubstantiveFailure: Bool = false

    /// Per-session UUID prefix used for the draft file path.
    let sessionShortId: String = String(UUID().uuidString.prefix(8)).lowercased()

    /// Mid-session wiki draft. Lazy so filesystem access is deferred until first use.
    lazy var draftBuffer: SessionDraftBuffer = SessionDraftBuffer(shortId: sessionShortId)
}

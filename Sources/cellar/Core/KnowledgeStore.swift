import Foundation

// MARK: - KnowledgeStore Protocol

/// Unified interface for reading and writing structured knowledge entries.
/// Implementations: KnowledgeStoreLocal (Plan 03), KnowledgeStoreRemote (Plan 03).
protocol KnowledgeStore: Sendable {
    /// Fetch formatted context for the agent prompt for a given game + environment.
    /// Returns nil when no relevant context is available.
    func fetchContext(for gameName: String, environment: EnvironmentFingerprint) async -> String?

    /// Write a knowledge entry to the store.
    func write(_ entry: KnowledgeEntry) async

    /// List entries matching the given filter. Returns metadata only (no payloads).
    func list(filter: KnowledgeListFilter) async -> [KnowledgeEntryMeta]
}

// MARK: - KnowledgeStoreContainer

/// Holds the active KnowledgeStore implementation. Replaced once at app startup by Plan 04
/// when AIService wires KnowledgeStoreRemote (or KnowledgeStoreLocal for offline mode).
///
/// Using an enum container rather than a static var on the protocol because protocols cannot
/// have stored static properties. `nonisolated(unsafe)` is acceptable here because the value
/// is written exactly once at startup (single-writer-at-startup pattern, same as PolicyResources).
enum KnowledgeStoreContainer {
    nonisolated(unsafe) static var shared: any KnowledgeStore = NoOpKnowledgeStore()
}

// MARK: - NoOpKnowledgeStore

/// Default no-op implementation used before Plan 04 wires the real adapter at app startup.
/// Kept private to this file — callers must go through KnowledgeStoreContainer.shared.
private struct NoOpKnowledgeStore: KnowledgeStore {
    func fetchContext(for gameName: String, environment: EnvironmentFingerprint) async -> String? {
        nil
    }

    func write(_ entry: KnowledgeEntry) async {
        // no-op: Plan 03 ships real adapters
    }

    func list(filter: KnowledgeListFilter) async -> [KnowledgeEntryMeta] {
        []
    }
}

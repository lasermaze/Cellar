import Foundation

// MARK: - ConfigEntry

/// Thin alias so downstream code can write `ConfigEntry` without importing the full schema name.
typealias ConfigEntry = CollectiveMemoryEntry

// MARK: - GamePageEntry

/// An agent-authored or auto-scraped game wiki page.
struct GamePageEntry: Codable, Sendable {
    /// Filesystem slug, e.g. `half-life` — used as the path component in the wiki repo.
    let slug: String
    /// The upstream-scraped AUTO-fence content block.
    let autoContent: String
    /// Optional commit message for the wiki write. Omitted from stored JSON if nil.
    let commitMessage: String?
}

// MARK: - SessionLogEntry

/// A session journal entry written after each agent loop (success or failure).
/// `path` mirrors WikiService.postSessionLog filename convention:
/// `sessions/YYYY-MM-DD-game-slug-shortId.md`
struct SessionLogEntry: Codable, Sendable {
    /// Relative path within the wiki repo, e.g. `sessions/2026-05-03-game-slug-abc123.md`
    let path: String
    /// Full Markdown body of the session log.
    let body: String
    /// Optional commit message for the wiki write. Omitted from stored JSON if nil.
    let commitMessage: String?
}

// MARK: - KnowledgeEntry

/// Discriminated union representing the three kinds of knowledge entries stored in the
/// KnowledgeStore. JSON wire shape: `{"kind": "<case>", "entry": <payload>}`.
///
/// Design notes:
/// - Custom Codable uses a `kind`+`entry` wrapper so the wire format is explicit and
///   extensible. Unknown `kind` values throw a clear `DecodingError` (no silent default).
/// - `typealias ConfigEntry = CollectiveMemoryEntry` avoids duplicating the schema.
enum KnowledgeEntry: Sendable {

    /// An existing CollectiveMemoryEntry describing a working Wine configuration.
    case config(ConfigEntry)

    /// A scraped or agent-authored wiki page for a specific game.
    case gamePage(GamePageEntry)

    /// A post-session journal entry (success or failure narrative).
    case sessionLog(SessionLogEntry)

    // MARK: - Kind discriminant

    enum Kind: String, Codable, Sendable, CaseIterable {
        case config
        case gamePage
        case sessionLog
    }

    // MARK: - Computed properties

    /// The discriminant kind of this entry.
    var kind: Kind {
        switch self {
        case .config: return .config
        case .gamePage: return .gamePage
        case .sessionLog: return .sessionLog
        }
    }

    /// A slug that identifies the game or session this entry belongs to.
    /// - `.config`     → `gameId` from the CollectiveMemoryEntry
    /// - `.gamePage`   → `slug` field directly
    /// - `.sessionLog` → filename stem derived from `path` (strips directory prefix and `.md`)
    var slug: String {
        switch self {
        case .config(let entry):
            return entry.gameId
        case .gamePage(let entry):
            return entry.slug
        case .sessionLog(let entry):
            // Derive from e.g. "sessions/2026-05-03-game-slug-abc123.md" -> "2026-05-03-game-slug-abc123"
            let filename = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
            return filename
        }
    }
}

// MARK: - KnowledgeEntry Codable

extension KnowledgeEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case entry
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        switch self {
        case .config(let entry):
            try container.encode(entry, forKey: .entry)
        case .gamePage(let entry):
            try container.encode(entry, forKey: .entry)
        case .sessionLog(let entry):
            try container.encode(entry, forKey: .entry)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kindRaw = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: kindRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown KnowledgeEntry kind: '\(kindRaw)'"
            )
        }
        switch kind {
        case .config:
            let entry = try container.decode(ConfigEntry.self, forKey: .entry)
            self = .config(entry)
        case .gamePage:
            let entry = try container.decode(GamePageEntry.self, forKey: .entry)
            self = .gamePage(entry)
        case .sessionLog:
            let entry = try container.decode(SessionLogEntry.self, forKey: .entry)
            self = .sessionLog(entry)
        }
    }
}

// MARK: - KnowledgeWriteRequest

/// Outer envelope sent to the Worker `/api/knowledge/write` endpoint.
/// The JSON shape mirrors the KnowledgeEntry encoding: `{"kind": "...", "entry": {...}}`.
struct KnowledgeWriteRequest: Encodable {
    let entry: KnowledgeEntry

    func encode(to encoder: Encoder) throws {
        // Delegate entirely to KnowledgeEntry — it already produces {kind, entry}
        try entry.encode(to: encoder)
    }
}

// MARK: - KnowledgeListFilter

/// Filter parameters for `KnowledgeStore.list(filter:)`.
struct KnowledgeListFilter: Sendable {
    var kind: KnowledgeEntry.Kind?
    var slug: String?
    var maxResults: Int = 20
}

// MARK: - KnowledgeEntryMeta

/// Lightweight metadata returned by `KnowledgeStore.list(filter:)` without loading full payloads.
struct KnowledgeEntryMeta: Sendable {
    let kind: KnowledgeEntry.Kind
    let slug: String
    let path: String
    let lastModified: Date?
}

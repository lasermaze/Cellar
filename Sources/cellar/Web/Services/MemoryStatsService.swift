import Foundation
@preconcurrency import Vapor

// MARK: - View Models (Content-conforming for Leaf rendering)

struct MemoryStats: Content {
    let gameCount: Int
    let totalConfirmations: Int
    let recentContributions: [RecentContribution]
    let isAvailable: Bool  // false when auth missing or network fails
}

struct RecentContribution: Content {
    let gameName: String
    let gameSlug: String
    let lastConfirmed: String
    let confirmations: Int
}

struct GameDetail: Content {
    let gameName: String
    let gameSlug: String
    let entries: [MemoryEntryViewData]
}

/// Flat view model — Leaf cannot render computed properties or deeply nested optionals.
struct MemoryEntryViewData: Content {
    let arch: String
    let wineVersion: String
    let macosVersion: String
    let wineFlavor: String
    let confirmations: Int
    let lastConfirmed: String
    let engine: String       // "" if nil
    let graphicsApi: String  // "" if nil
    let reasoning: String
}

// MARK: - Internal helpers

private struct GitHubDirectoryEntry: Codable {
    let name: String
    let type: String
}

// MARK: - MemoryStatsService

/// Stateless service that fetches aggregate and per-game collective memory stats
/// from the GitHub Contents API.
///
/// All errors are swallowed — functions never throw, returning empty/nil on any failure.
///
/// Note: fetchStats() is not optimized for large repos — it fetches each game file
/// sequentially. This is acceptable for community repos with tens of games.
struct MemoryStatsService {

    // MARK: - Public API

    /// Fetch aggregate memory stats (game count, total confirmations, recent contributions).
    /// Returns a MemoryStats with isAvailable: false when auth is missing or network fails.
    static func fetchStats() -> MemoryStats {
        let emptyUnavailable = MemoryStats(
            gameCount: 0,
            totalConfirmations: 0,
            recentContributions: [],
            isAvailable: false
        )

        // Step 1: Auth check
        let authResult = GitHubAuthService.shared.getToken()
        guard case .token(let token) = authResult else {
            return emptyUnavailable
        }

        // Step 2: Fetch directory listing
        let repoBase = "https://api.github.com/repos/\(GitHubAuthService.shared.memoryRepo)/contents/entries"
        guard let url = URL(string: repoBase) else {
            return emptyUnavailable
        }

        var listRequest = URLRequest(url: url)
        listRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        listRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        listRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        listRequest.timeoutInterval = 5

        guard let (listData, listStatus) = performFetch(request: listRequest) else {
            return emptyUnavailable
        }

        // 404 = entries/ dir empty or doesn't exist — repo is reachable but has no entries
        if listStatus == 404 {
            return MemoryStats(
                gameCount: 0,
                totalConfirmations: 0,
                recentContributions: [],
                isAvailable: true
            )
        }

        guard listStatus == 200 else {
            return emptyUnavailable
        }

        // Step 3: Decode directory listing
        let dirEntries: [GitHubDirectoryEntry]
        do {
            dirEntries = try JSONDecoder().decode([GitHubDirectoryEntry].self, from: listData)
        } catch {
            return emptyUnavailable
        }

        let gameFiles = dirEntries.filter { $0.type == "file" && $0.name.hasSuffix(".json") }

        var totalConfirmations = 0
        var allContributions: [(slug: String, gameName: String, lastConfirmed: String, confirmations: Int)] = []

        // Step 4: Fetch each game file and aggregate stats
        for fileEntry in gameFiles {
            let slug = String(fileEntry.name.dropLast(5)) // drop ".json"
            let fileURLString = "https://api.github.com/repos/\(GitHubAuthService.shared.memoryRepo)/contents/entries/\(fileEntry.name)"
            guard let fileURL = URL(string: fileURLString) else { continue }

            var fileRequest = URLRequest(url: fileURL)
            fileRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            fileRequest.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
            fileRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            fileRequest.timeoutInterval = 5

            guard let (fileData, fileStatus) = performFetch(request: fileRequest),
                  fileStatus == 200 else { continue }

            guard let entries = try? JSONDecoder().decode([CollectiveMemoryEntry].self, from: fileData),
                  !entries.isEmpty else { continue }

            for entry in entries {
                totalConfirmations += entry.confirmations
                allContributions.append((
                    slug: slug,
                    gameName: entry.gameName,
                    lastConfirmed: entry.lastConfirmed,
                    confirmations: entry.confirmations
                ))
            }
        }

        // Step 5: Sort contributions by lastConfirmed descending (ISO 8601 lexicographic sort)
        let sorted = allContributions.sorted { $0.lastConfirmed > $1.lastConfirmed }
        let recent = sorted.prefix(10).map {
            RecentContribution(
                gameName: $0.gameName,
                gameSlug: $0.slug,
                lastConfirmed: $0.lastConfirmed,
                confirmations: $0.confirmations
            )
        }

        return MemoryStats(
            gameCount: gameFiles.count,
            totalConfirmations: totalConfirmations,
            recentContributions: Array(recent),
            isAvailable: true
        )
    }

    /// Fetch per-game memory entries for the given slug.
    /// Returns nil when auth is missing, the game is not found, or any network/parse error occurs.
    static func fetchGameDetail(slug: String) -> GameDetail? {
        // Step 1: Auth check
        let authResult = GitHubAuthService.shared.getToken()
        guard case .token(let token) = authResult else {
            return nil
        }

        // Step 2: Fetch raw game file
        let urlString = "https://api.github.com/repos/\(GitHubAuthService.shared.memoryRepo)/contents/entries/\(slug).json"
        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 5

        guard let (data, statusCode) = performFetch(request: request),
              statusCode == 200 else {
            return nil
        }

        // Step 3: Decode entries
        guard let entries = try? JSONDecoder().decode([CollectiveMemoryEntry].self, from: data),
              !entries.isEmpty else {
            return nil
        }

        // Step 4: Map to flat view models
        let gameName = entries[0].gameName
        let viewData = entries.map { entry in
            MemoryEntryViewData(
                arch: entry.environment.arch,
                wineVersion: entry.environment.wineVersion,
                macosVersion: entry.environment.macosVersion,
                wineFlavor: entry.environment.wineFlavor,
                confirmations: entry.confirmations,
                lastConfirmed: entry.lastConfirmed,
                engine: entry.engine ?? "",
                graphicsApi: entry.graphicsApi ?? "",
                reasoning: entry.reasoning
            )
        }

        return GameDetail(
            gameName: gameName,
            gameSlug: slug,
            entries: viewData
        )
    }

    // MARK: - Private Helpers

    /// Perform a synchronous HTTP fetch using DispatchSemaphore.
    /// Returns (data, statusCode) on any HTTP response, nil on network error.
    private static func performFetch(request: URLRequest) -> (data: Data, statusCode: Int)? {
        final class ResultBox: @unchecked Sendable {
            var value: (Data, Int)?
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if error == nil,
               let data = data,
               let httpResponse = response as? HTTPURLResponse {
                box.value = (data, httpResponse.statusCode)
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return box.value
    }
}

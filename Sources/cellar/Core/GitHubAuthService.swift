import Foundation
import Security

/// GitHub App authentication service.
///
/// Generates RS256 JWTs using Security.framework, exchanges them for 1-hour installation
/// tokens via the GitHub REST API, caches tokens with automatic TTL-based refresh at
/// 55 minutes (5-minute buffer before the 1-hour GitHub expiry), loads credentials via
/// priority cascade (env var > ~/.cellar/.env > bundled resource), and degrades gracefully
/// when credentials are missing or misconfigured.
///
/// Usage:
///   let result = GitHubAuthService.shared.getToken()
///   switch result {
///   case .token(let t):       // use t as Authorization: Bearer header
///   case .unavailable(let r): // log r, skip GitHub API calls
///   }
final class GitHubAuthService: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = GitHubAuthService()

    // MARK: - Cached Token State

    private var cachedToken: String?
    private var tokenExpiry: Date?
    private let lock = NSLock()

    // MARK: - Public API

    /// Return a valid installation access token, refreshing if within 5 minutes of expiry.
    /// Always returns gracefully — never throws or crashes.
    func getToken() async -> GitHubAuthResult {
        // Check cache synchronously first (NSLock provides thread safety for @unchecked Sendable)
        if let cached = cachedTokenIfValid() {
            return .token(cached)
        }

        // Cache miss: fetch a fresh token asynchronously
        do {
            let (token, expiry) = try await refreshToken()
            cacheToken(token, expiry: expiry)
            return .token(token)
        } catch GitHubAuthError.credentialsNotConfigured {
            return .unavailable(reason: "GitHub App credentials not configured — set GITHUB_APP_ID, GITHUB_INSTALLATION_ID, and GITHUB_APP_KEY_PATH in ~/.cellar/.env or environment")
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    /// Synchronous cache check (NSLock-protected). Returns cached token or nil.
    private func cachedTokenIfValid() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let token = cachedToken,
              let expiry = tokenExpiry,
              expiry > Date().addingTimeInterval(5 * 60) else {
            return nil
        }
        return token
    }

    /// Synchronous cache write (NSLock-protected).
    private func cacheToken(_ token: String, expiry: Date) {
        lock.lock()
        defer { lock.unlock() }
        cachedToken = token
        tokenExpiry = expiry
    }

    /// Reset cached token — useful for testing and future token invalidation scenarios.
    func resetCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedToken = nil
        tokenExpiry = nil
    }

    // MARK: - Collective Memory Repo

    /// The owner/repo identifier for collective memory API calls.
    var memoryRepo: String {
        loadEnvironmentVariables()["CELLAR_MEMORY_REPO"] ?? CellarPaths.defaultMemoryRepo
    }

    // MARK: - Private: Token Refresh

    private func refreshToken() async throws -> (token: String, expiresAt: Date) {
        let credentials = try loadCredentials()
        let jwt = try makeJWT(appID: credentials.appID, pemString: credentials.pemString)
        return try await fetchInstallationToken(jwt: jwt, installationID: credentials.installationID)
    }

    // MARK: - Private: JWT Generation

    private func makeJWT(appID: String, pemString: String) throws -> String {
        // Step 1: Strip PEM headers and decode DER bytes
        var stripped = pemString
        // PKCS#1 headers (GitHub App keys)
        stripped = stripped.replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
        stripped = stripped.replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
        // PKCS#8 headers (defensive)
        stripped = stripped.replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
        stripped = stripped.replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
        // Remove all whitespace characters
        stripped = stripped.replacingOccurrences(of: "\r", with: "")
        stripped = stripped.replacingOccurrences(of: "\n", with: "")
        stripped = stripped.replacingOccurrences(of: " ", with: "")

        guard let derData = Data(base64Encoded: stripped) else {
            throw GitHubAuthError.invalidPEM
        }

        // Step 2: Create SecKey from DER data
        let keyAttributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        var cfError: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(
            derData as CFData,
            keyAttributes as CFDictionary,
            &cfError
        ) else {
            let detail = cfError?.takeRetainedValue().localizedDescription ?? "unknown error"
            throw GitHubAuthError.keyCreationFailed(detail)
        }

        // Step 3: Build JWT header and payload
        let now = Int(Date().timeIntervalSince1970)

        // Header: {"alg":"RS256","typ":"JWT"}
        let headerDict: [String: String] = ["alg": "RS256", "typ": "JWT"]
        let headerData = try JSONSerialization.data(withJSONObject: headerDict, options: [.sortedKeys])
        let header = base64url(headerData)

        // Payload: {"iss": appID, "iat": now-60, "exp": now+510}
        // Use [String: Any] with JSONSerialization because iat/exp are Int, iss is String
        let payloadDict: [String: Any] = [
            "iss": appID,
            "iat": now - 60,    // 60-second clock skew buffer (GitHub recommended)
            "exp": now + 510    // 8.5 minutes — under GitHub's 10-minute maximum
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict, options: [])
        let payload = base64url(payloadData)

        // Step 4: Sign header.payload with RS256
        let message = "\(header).\(payload)"
        guard let messageData = message.data(using: .utf8) else {
            throw GitHubAuthError.encodingFailed
        }

        guard let signatureData = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            messageData as CFData,
            &cfError
        ) else {
            let detail = cfError?.takeRetainedValue().localizedDescription ?? "unknown error"
            fputs("[GitHubAuthService] Failed to sign JWT: \(detail)\n", stderr)
            throw GitHubAuthError.signFailed(detail)
        }

        // Step 5: Assemble final JWT
        return "\(header).\(payload).\(base64url(signatureData as Data))"
    }

    // MARK: - Private: base64url Encoding

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Private: Installation Token Exchange

    private func fetchInstallationToken(
        jwt: String,
        installationID: String
    ) async throws -> (token: String, expiresAt: Date) {
        let urlString = "https://api.github.com/app/installations/\(installationID)/access_tokens"
        guard let url = URL(string: urlString) else {
            throw GitHubAuthError.httpError(statusCode: 0, body: "Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data = try await performHTTPRequest(request: request)

        let decoder = JSONDecoder()
        let tokenResponse: InstallationTokenResponse
        do {
            tokenResponse = try decoder.decode(InstallationTokenResponse.self, from: data)
        } catch {
            fputs("[GitHubAuthService] Failed to decode installation token response\n", stderr)
            throw error
        }

        let dateFormatter = ISO8601DateFormatter()
        guard let expiryDate = dateFormatter.date(from: tokenResponse.expiresAt) else {
            throw GitHubAuthError.invalidExpiryDate
        }

        return (tokenResponse.token, expiryDate)
    }

    /// Async HTTP request using URLSession.data(for:).
    private func performHTTPRequest(request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAuthError.httpError(statusCode: 0, body: "No HTTP response received")
        }
        if http.statusCode >= 400 {
            fputs("[GitHubAuthService] HTTP \(http.statusCode) from GitHub API\n", stderr)
            let body = String(data: data, encoding: .utf8) ?? "<unreadable>"
            throw GitHubAuthError.httpError(statusCode: http.statusCode, body: body)
        }
        return data
    }

    // MARK: - Private: Credential Loading

    private func loadCredentials() throws -> GitHubCredentials {
        let env = loadEnvironmentVariables()

        // Resolve PEM string via priority cascade
        let pemString = try resolvePEM(env: env)

        // Resolve App ID and Installation ID
        // Priority: env var > bundled github-app.json
        var appID = env["GITHUB_APP_ID"] ?? ""
        var installationID = env["GITHUB_INSTALLATION_ID"] ?? ""

        // Fall back to bundled github-app.json if env vars are not set
        if appID.isEmpty || installationID.isEmpty {
            if let config = loadBundledConfig() {
                if appID.isEmpty { appID = config.appID }
                if installationID.isEmpty { installationID = config.installationID }
            }
        }

        guard !appID.isEmpty, !installationID.isEmpty else {
            throw GitHubAuthError.credentialsNotConfigured
        }

        return GitHubCredentials(appID: appID, installationID: installationID, pemString: pemString)
    }

    /// Resolve the PEM private key using the priority cascade:
    /// 1. GITHUB_APP_KEY_PATH env var → read file at that path
    /// 2. Bundle.main resource (release build)
    /// 3. CWD-relative Sources/cellar/Resources/github-app.pem (swift run / development)
    private func resolvePEM(env: [String: String]) throws -> String {
        // Strategy 1: Explicit path via env var
        if let keyPath = env["GITHUB_APP_KEY_PATH"], !keyPath.isEmpty {
            let url = URL(fileURLWithPath: keyPath)
            if let contents = try? String(contentsOf: url, encoding: .utf8), !contents.isEmpty {
                return contents
            }
        }

        // Strategy 2: Bundle.main (release build with bundled resources)
        if let bundledURL = Bundle.main.url(forResource: "github-app", withExtension: "pem") {
            if let contents = try? String(contentsOf: bundledURL, encoding: .utf8), !contents.isEmpty {
                return contents
            }
        }

        // Strategy 3: CWD-relative path (swift run / development)
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/cellar/Resources/github-app.pem")
        if let contents = try? String(contentsOf: cwdURL, encoding: .utf8), !contents.isEmpty {
            return contents
        }

        throw GitHubAuthError.credentialsNotConfigured
    }

    /// Load bundled github-app.json configuration using multi-strategy resource loading.
    private func loadBundledConfig() -> GitHubAppConfig? {
        // Strategy 1: Bundle.main (release build)
        if let bundledURL = Bundle.main.url(forResource: "github-app", withExtension: "json") {
            if let data = try? Data(contentsOf: bundledURL),
               let config = try? JSONDecoder().decode(GitHubAppConfig.self, from: data) {
                return config
            }
        }

        // Strategy 2: CWD-relative path (swift run / development)
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/cellar/Resources/github-app.json")
        if let data = try? Data(contentsOf: cwdURL),
           let config = try? JSONDecoder().decode(GitHubAppConfig.self, from: data) {
            return config
        }

        return nil
    }

    // MARK: - Private: Environment Loading

    /// Load environment variables: process env vars take precedence, then ~/.cellar/.env file.
    /// Mirrors AIService.loadEnvironment — copied here to keep GitHubAuthService self-contained.
    private func loadEnvironmentVariables() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let envFile = CellarPaths.base.appendingPathComponent(".env")
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else {
            return env
        }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            // Process env takes precedence — only set if not already present
            if env[key] == nil {
                env[key] = value
            }
        }
        return env
    }
}

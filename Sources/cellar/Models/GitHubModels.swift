import Foundation

// MARK: - GitHub App Config

/// Codable struct matching `github-app.json` structure.
/// Loaded from the bundled resource file at startup.
struct GitHubAppConfig: Codable {
    /// The GitHub App ID (numeric) or Client ID (string) — stored as String for flexibility.
    let appID: String
    /// The installation ID for the target account/organization.
    let installationID: String

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case installationID = "installation_id"
    }
}

// MARK: - GitHub Credentials

/// Resolved credentials held in memory after loading from config + PEM file.
/// Not Codable — never serialized, only used at runtime.
struct GitHubCredentials {
    let appID: String
    let installationID: String
    let pemString: String
}

// MARK: - Installation Token Response

/// Codable struct for the GitHub API installation access token response.
struct InstallationTokenResponse: Codable {
    let token: String
    /// ISO 8601 expiry date string from the GitHub API.
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

// MARK: - GitHub Auth Result

/// Result of a GitHub App authentication attempt.
/// Mirrors the AIProvider enum pattern used in AIModels.swift.
enum GitHubAuthResult {
    /// A valid installation access token was obtained.
    case token(String)
    /// Credentials are missing or misconfigured — includes a human-readable reason.
    case unavailable(reason: String)
}

// MARK: - GitHub Auth Error

/// Errors that can occur during GitHub App JWT signing and token exchange.
enum GitHubAuthError: Error, LocalizedError {
    /// App ID or installation ID is empty or missing from configuration.
    case credentialsNotConfigured
    /// PEM file cannot be parsed — base64 decode failure or malformed PEM envelope.
    case invalidPEM
    /// `SecKeyCreateWithData` returned nil; associated value contains the CFError description.
    case keyCreationFailed(String)
    /// `SecKeyCreateSignature` returned nil; associated value contains the CFError description.
    case signFailed(String)
    /// UTF-8 encoding of the JWT header/payload failed.
    case encodingFailed
    /// `expires_at` field in the token response is not a valid ISO 8601 date string.
    case invalidExpiryDate
    /// GitHub API returned a non-success HTTP status; includes the status code and response body.
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .credentialsNotConfigured:
            return "GitHub App credentials not configured — set app_id and installation_id in github-app.json"
        case .invalidPEM:
            return "GitHub App private key is invalid — could not decode PEM file"
        case .keyCreationFailed(let detail):
            return "Failed to create RSA signing key: \(detail)"
        case .signFailed(let detail):
            return "JWT signing failed: \(detail)"
        case .encodingFailed:
            return "Failed to UTF-8 encode JWT message"
        case .invalidExpiryDate:
            return "GitHub API returned an unrecognized expiry date format in expires_at"
        case .httpError(let statusCode, let body):
            return "GitHub API error \(statusCode): \(body)"
        }
    }
}

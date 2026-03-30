# Phase 13: GitHub App Authentication - Research

**Researched:** 2026-03-30
**Domain:** GitHub App JWT authentication, RS256 signing, Security.framework, token lifecycle management
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- GitHub App private key (.pem) bundled as a Swift package resource (`Resources/github-app.pem`)
- App ID and Installation ID in a companion resource file (`Resources/github-app.json`)
- User can override with env vars: `GITHUB_APP_KEY_PATH`, `GITHUB_APP_ID`, `GITHUB_INSTALLATION_ID` (checked first, then ~/.cellar/.env, then bundled resource)
- Key rotation via CLI updates only — no phone-home or startup network check
- During development: placeholder IDs in resource files, tests mock GitHub API; real credentials dropped in before shipping
- Self-hosting supported via env override cascade; `CELLAR_MEMORY_REPO` defaults to `cellar-community/memory`
- No extra UI or config surface needed — existing .env pattern covers it
- Org: `cellar-community`, Repo: `memory` (full path: `cellar-community/memory`)
- Phase 13 builds auth code only — GitHub App and repo created manually when ready
- All GitHub API interactions use the REST Contents API (no git clone/push, no git binary dependency)
- No new SPM dependencies — Security.framework for RS256 JWT; URLSession handles API calls
- New `GitHubAuthService` in `Sources/cellar/Core/`
- Extend `Package.swift` target resources to include `github-app.pem` and `github-app.json`
- swift-crypto already available transitively via Vapor — but Security.framework is preferred (no async needed)
- Future phases (15, 16) call `GitHubAuthService.getToken()` before Contents API requests

### Claude's Discretion

- RS256 JWT implementation details (Security.framework vs swift-crypto via Vapor)
- Token caching strategy (in-memory with TTL check vs file-based)
- Error types and internal error handling structure
- Test structure and mocking approach for GitHub API

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUTH-01 | Agent authenticates to GitHub API using GitHub App credentials (RS256 JWT + installation token) shipped with CLI | Security.framework RS256 signing + GitHub POST /app/installations/{id}/access_tokens |
| AUTH-02 | Agent token refreshes automatically before expiry (1-hour lifetime, refresh at 55 minutes) | In-memory cache with `expires_at` TTL check; re-fetch JWT + installation token when stale |
</phase_requirements>

---

## Summary

Phase 13 implements GitHub App authentication as a standalone service (`GitHubAuthService`) that produces installation access tokens for use by later phases. The full flow has two steps: (1) generate a short-lived RS256-signed JWT using the bundled private key and App ID, and (2) exchange that JWT for a 1-hour installation access token via the GitHub REST API. Both steps are well-documented with stable, production-verified APIs.

The RS256 JWT can be implemented entirely with Apple's `Security.framework` (available on macOS 14+, already targeted) using `SecKeyCreateWithData` + `SecKeyCreateSignature`. This avoids any new SPM dependency and aligns with the project decision to keep the stack lean. The approach is confirmed working in real-world Swift macOS CLI apps (RepoBar uses this exact pattern). GitHub generates App private keys in **PKCS#1 RSAPrivateKey format** (`-----BEGIN RSA PRIVATE KEY-----`), and Security.framework's `SecKeyCreateWithData` accepts this directly after stripping headers and base64-decoding.

Token caching should be in-memory with a TTL check (compare `Date.now` against stored `expires_at - 5 minutes`). File-based caching adds complexity and creates a credential-on-disk security surface that isn't necessary for a CLI tool that starts and stops. The 55-minute refresh threshold from AUTH-02 is achieved by treating tokens as expired when `Date.now >= expires_at - 5 minutes` (since token lifetime is 1 hour, this naturally gives a ~55-minute validity window).

**Primary recommendation:** Implement `GitHubAuthService` as a pure Security.framework RS256 signer with in-memory token cache and TTL-based refresh. Mirror the `callAPI` + `DispatchSemaphore` pattern from `AIService.swift` for all HTTP calls.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Security.framework | macOS 14 (system) | RS256 JWT signing via `SecKeyCreateWithData` + `SecKeyCreateSignature` | Zero new dependencies; confirmed working for GitHub App JWT in Swift CLI apps; synchronous API suits DispatchSemaphore pattern |
| Foundation | macOS 14 (system) | URLSession HTTP calls, JSONEncoder/Decoder, Data base64 | Already used project-wide |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| swift-testing | 0.12.0 (already in project) | Unit tests for JWT generation and token cache | Test the signer and cache logic in isolation with mocked HTTP |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Security.framework | vapor/jwt-kit | jwt-kit is async-only (async/await API); doesn't fit DispatchSemaphore pattern; adds async complexity to a sync codebase |
| Security.framework | swift-crypto (Apple) | swift-crypto does not expose RSA PKCS#1v15 signing on Apple platforms — it delegates to Security.framework underneath; using Security directly is simpler |
| In-memory cache | File-based token cache (~/.cellar/github-token.json) | File cache survives restarts but creates a credential on disk, adds file I/O error surface, no meaningful benefit for a CLI |

**Installation:** No new packages. Security.framework is a system framework, no import in Package.swift needed (just `import Security` in Swift files).

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/cellar/
├── Core/
│   └── GitHubAuthService.swift      # New: JWT signer + token cache + installation token fetch
├── Models/
│   └── GitHubModels.swift           # New: Codable structs for API request/response
├── Resources/
│   ├── github-app.pem               # New: placeholder PKCS#1 private key (replaced before ship)
│   └── github-app.json              # New: placeholder {"app_id":"","installation_id":""}
```

### Pattern 1: RS256 JWT Generation (Security.framework)

**What:** Strip PEM headers → base64-decode to DER → `SecKeyCreateWithData` → `SecKeyCreateSignature(.rsaSignatureMessagePKCS1v15SHA256)`
**When to use:** Once per token request cycle (JWT is only needed to exchange for installation token, not cached itself)

```swift
// Source: RepoBar JWTSigner pattern (deepwiki.com/steipete/RepoBar/11.3-jwt-signing-for-github-apps)
// + Apple Developer Forums thread/702003

import Foundation
import Security

enum JWTError: Error {
    case invalidPEM
    case keyCreationFailed(CFError?)
    case signFailed(CFError?)
    case encodingFailed
}

func makeGitHubJWT(appID: String, pemString: String) throws -> String {
    // 1. PEM → DER (PKCS#1 RSAPrivateKey format from GitHub)
    let der = try derFromPEM(pemString)

    // 2. Create SecKey
    let attrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
    ]
    var cfError: Unmanaged<CFError>?
    guard let secKey = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &cfError) else {
        throw JWTError.keyCreationFailed(cfError?.takeRetainedValue())
    }

    // 3. Build header + payload (base64url-encoded)
    let now = Int(Date().timeIntervalSince1970)
    let header = base64url(try JSONEncoder().encode(["alg": "RS256", "typ": "JWT"]))
    let payload = base64url(try JSONEncoder().encode([
        "iss": appID,
        "iat": now - 60,          // 60s in past for clock skew
        "exp": now + 510,         // 8.5 min: safe margin under GitHub's 10-min max
    ]))

    // 4. Sign
    let message = "\(header).\(payload)"
    guard let messageData = message.data(using: .utf8) else { throw JWTError.encodingFailed }
    guard let signature = SecKeyCreateSignature(
        secKey, .rsaSignatureMessagePKCS1v15SHA256, messageData as CFData, &cfError
    ) else {
        throw JWTError.signFailed(cfError?.takeRetainedValue())
    }

    // 5. Assemble
    return "\(header).\(payload).\(base64url(signature as Data))"
}

private func derFromPEM(_ pem: String) throws -> Data {
    // GitHub App keys use "BEGIN RSA PRIVATE KEY" (PKCS#1 format)
    let stripped = pem
        .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
        .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
        .trimmingCharacters(in: .whitespaces)
    guard let data = Data(base64Encoded: stripped) else { throw JWTError.invalidPEM }
    return data
}

private func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
```

### Pattern 2: Installation Token Exchange

**What:** POST to GitHub REST API with JWT, parse `token` + `expires_at` from response
**When to use:** After JWT generation, to get the actual write-capable installation access token

```swift
// Source: GitHub Docs - POST /app/installations/{installation_id}/access_tokens
// Response confirmed: {"token": "ghs_...", "expires_at": "2026-03-30T13:00:00Z", ...}

struct InstallationTokenResponse: Codable {
    let token: String
    let expiresAt: String        // ISO 8601, parse with ISO8601DateFormatter

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

func fetchInstallationToken(jwt: String, installationID: String) throws -> (token: String, expiresAt: Date) {
    let url = URL(string: "https://api.github.com/app/installations/\(installationID)/access_tokens")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

    let data = try callAPI(request: req)    // reuse DispatchSemaphore pattern
    let resp = try JSONDecoder().decode(InstallationTokenResponse.self, from: data)
    let formatter = ISO8601DateFormatter()
    guard let expiry = formatter.date(from: resp.expiresAt) else {
        throw GitHubAuthError.invalidExpiryDate
    }
    return (resp.token, expiry)
}
```

### Pattern 3: In-Memory Token Cache with TTL

**What:** Store token + expiry in `GitHubAuthService`; re-fetch when within 5 minutes of expiry
**When to use:** Every call to `getToken()` from future phases — cache miss triggers full JWT + exchange flow

```swift
// Conceptual implementation — mirrors AIService.detectProvider() load-on-demand pattern
final class GitHubAuthService {
    private var cachedToken: String?
    private var tokenExpiry: Date?

    func getToken() throws -> String {
        // Refresh if absent or expiring within 5 minutes (= effective 55-min TTL)
        if let token = cachedToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(5 * 60) {
            return token
        }
        let creds = try loadCredentials()   // env var > .env > bundled resource cascade
        let jwt = try makeGitHubJWT(appID: creds.appID, pemString: creds.pemString)
        let (newToken, newExpiry) = try fetchInstallationToken(jwt: jwt, installationID: creds.installationID)
        cachedToken = newToken
        tokenExpiry = newExpiry
        return newToken
    }
}
```

### Pattern 4: Credential Loading (Priority Cascade)

**What:** env var → ~/.cellar/.env → bundled resource (mirrors existing `AIService.loadEnvironment()` pattern)
**When to use:** Inside `loadCredentials()` called once per token refresh

```swift
// Mirror of AIService.loadEnvironment() — same KEY=VALUE parser, same priority order
func loadCredentials() throws -> GitHubCredentials {
    let env = loadEnvironment()  // reuse AIService pattern

    // PEM key: env var path override → .env path override → bundled resource
    let pemString: String
    if let keyPath = env["GITHUB_APP_KEY_PATH"] {
        pemString = try String(contentsOfFile: keyPath, encoding: .utf8)
    } else {
        // Fall back to bundled Resources/github-app.pem
        pemString = try loadBundledPEM()
    }

    let appID = env["GITHUB_APP_ID"] ?? loadBundledConfig().appID
    let installationID = env["GITHUB_INSTALLATION_ID"] ?? loadBundledConfig().installationID

    guard !appID.isEmpty, !installationID.isEmpty else {
        throw GitHubAuthError.credentialsNotConfigured
    }
    return GitHubCredentials(appID: appID, installationID: installationID, pemString: pemString)
}
```

### Pattern 5: Graceful Degradation

**What:** When credentials absent/misconfigured, return `.unavailable` instead of crashing
**When to use:** `getToken()` is called from agent loop context; must not interrupt the loop

```swift
// Mirror of AIService.detectProvider() returning .unavailable
enum GitHubAuthResult {
    case token(String)
    case unavailable(reason: String)
}

// Callers in Phase 15/16 check result before making API calls:
// if case .unavailable(let reason) = result { print("Skipping memory: \(reason)"); return }
```

### Anti-Patterns to Avoid

- **Caching the JWT itself:** JWTs are valid for max 10 minutes. Cache the installation token (1-hour lifetime), not the JWT. Generate a fresh JWT only when fetching a new installation token.
- **Using Bundle.module for PEM file:** `Bundle.module` has known issues with symlink execution on macOS (Homebrew installs via symlinks). Use `Bundle.main.url(forResource:withExtension:)` first, then fall back to `CommandLine.arguments[0]`-relative path, matching `RecipeEngine.swift`'s multi-strategy approach.
- **Storing token to disk:** Installation tokens are short-lived credentials — storing to disk creates unnecessary security surface with no benefit for a CLI.
- **Fetching new JWT per API call:** JWT generation involves RSA signing (CPU cost). Generate JWT only when the cached installation token is about to expire.
- **Hardcoding `expires_at` offset:** Parse the actual `expires_at` from the GitHub API response rather than computing `now + 3600`. GitHub's expiry is authoritative.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| RS256 signing | Custom ASN.1 / big-integer RSA | `SecKeyCreateSignature(.rsaSignatureMessagePKCS1v15SHA256)` | Security.framework handles PKCS#1v15 padding, SHA-256 hashing, and DER encoding correctly; hand-rolling RSA signing is cryptographically dangerous |
| Base64URL encoding | Custom encoder | `Data.base64EncodedString()` + `.replacingOccurrences` | JWT base64url is standard base64 with 3 character replacements; 3 lines is sufficient |
| HTTP retry | Custom retry loop | Reuse existing `withRetry` from `AIService.swift` or mirror the exponential backoff pattern | Already battle-tested in the project |
| ISO 8601 date parsing | Custom date string parser | `ISO8601DateFormatter()` | GitHub `expires_at` is always ISO 8601; the formatter handles timezone correctly |

**Key insight:** RS256 with Security.framework is 50–80 lines of Swift. The complexity is in the cryptographic correctness (PEM stripping, DER format, PKCS#1v15 padding), not in the business logic — Security.framework eliminates all of that.

---

## Common Pitfalls

### Pitfall 1: PKCS#1 vs PKCS#8 PEM Header Mismatch

**What goes wrong:** Code strips `-----BEGIN PRIVATE KEY-----` (PKCS#8) but GitHub generates `-----BEGIN RSA PRIVATE KEY-----` (PKCS#1). `Data(base64Encoded:)` returns `nil` because the key still has headers embedded.
**Why it happens:** PKCS#8 is the "modern" format (Java, many web tutorials use it); GitHub App keys are PKCS#1.
**How to avoid:** Strip `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----` explicitly. Add defensive stripping for PKCS#8 headers too so keys work if the user converts format.
**Warning signs:** `SecKeyCreateWithData` returns nil with `errSecParam` (-50); `Data(base64Encoded:)` returns nil.

### Pitfall 2: `iat` Clock Drift Causing JWT Rejection

**What goes wrong:** GitHub rejects JWT with "JWT issued at future time" if the machine clock is even slightly ahead of GitHub's servers.
**Why it happens:** Network latency means the JWT arrives after it was signed; clocks aren't perfectly synced.
**How to avoid:** Set `iat = now - 60` (60 seconds in the past). This is the officially recommended value in GitHub documentation.
**Warning signs:** HTTP 401 with `"'Issued at' claim ('iat') must be an Integer representing the time that the assertion was issued"` or similar JWT validation error.

### Pitfall 3: JWT Used for Installation Token Expired by the Time of Exchange

**What goes wrong:** JWT has 10-minute max lifetime. If token exchange is slow or the JWT is cached and reused, the exchange call gets a 401.
**Why it happens:** Temptation to cache the JWT to avoid re-signing. Don't cache JWTs.
**How to avoid:** Generate a fresh JWT immediately before each installation token exchange call. JWT generation is fast (local RSA operation); it doesn't need caching.
**Warning signs:** Intermittent 401 on the `/access_tokens` endpoint despite valid credentials.

### Pitfall 4: `Bundle.module` Fails Under Homebrew Symlink

**What goes wrong:** `Bundle.module.url(forResource: "github-app", withExtension: "pem")` returns nil at runtime when Cellar is installed via Homebrew (which symlinks the binary).
**Why it happens:** SPM's generated `Bundle.module` accessor uses the symlink path, not the resolved executable path, breaking resource lookup. This is a known open SPM issue (swiftlang/swift-package-manager#8510).
**How to avoid:** Follow the `RecipeEngine.swift` multi-strategy pattern: try `Bundle.main.url(forResource:withExtension:subdirectory:)` first, then fall back to path relative to `CommandLine.arguments[0]`.
**Warning signs:** Resource loads work in `swift run` and `swift test` but fail in release `.build/release/cellar` or Homebrew-installed binary.

### Pitfall 5: Installation ID Not Known at Development Time

**What goes wrong:** The GitHub App and its installation ID don't exist yet (Phase 13 builds auth code only, App created manually later). Code that requires a real installation ID to compile or test will block development.
**Why it happens:** Conflating "building the auth service" with "having real credentials."
**How to avoid:** Use placeholder values (`"0"` or `"dev-placeholder"`) in `Resources/github-app.json`. Tests mock the HTTP layer entirely and never hit real GitHub API. The credential loading code must gracefully handle placeholder IDs by returning `.unavailable` rather than crashing.
**Warning signs:** Tests fail or code won't compile without real App credentials.

### Pitfall 6: Thread Safety on Cached Token

**What goes wrong:** Two concurrent callers both see expired token, both call `fetchInstallationToken`, race condition on `cachedToken` assignment.
**Why it happens:** `GitHubAuthService` is a shared object; agent tools may be called from multiple contexts.
**How to avoid:** Use a simple serial queue (`DispatchQueue`) to serialize token refresh, or make `GitHubAuthService` an actor (if adopting async later). For now, given the existing project uses a synchronous DispatchSemaphore pattern, a `NSLock` or serial queue is sufficient.

---

## Code Examples

Verified patterns from official sources and confirmed working implementations:

### JWT Payload Fields (GitHub-Required)
```swift
// Source: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app
let payload: [String: Any] = [
    "iss": appID,             // GitHub App client ID (or numeric App ID)
    "iat": now - 60,          // 60 seconds in the past (clock skew protection)
    "exp": now + 510,         // 8.5 minutes ahead (< 10-minute GitHub maximum)
]
// Header: {"alg": "RS256", "typ": "JWT"}
```

### Installation Token Request
```swift
// Source: https://docs.github.com/en/rest/apps/apps?apiVersion=2022-11-28#create-an-installation-access-token-for-an-app
// POST https://api.github.com/app/installations/{installation_id}/access_tokens
// Headers:
//   Authorization: Bearer {JWT}
//   Accept: application/vnd.github+json
//   X-GitHub-Api-Version: 2022-11-28
// Response (HTTP 201):
//   { "token": "ghs_...", "expires_at": "2026-03-30T14:00:00Z", "permissions": {...} }
```

### Finding Installation ID (Manual, Pre-Ship)
```bash
# Authenticate as the GitHub App, then list installations
# GET https://api.github.com/app/installations
# Authorization: Bearer {JWT}
# Returns array with "id" field — that is the installation_id
```

### Bundled Resource Loading (Multi-Strategy, Matching RecipeEngine Pattern)
```swift
// Strategy 1: Bundle.main (release build, Homebrew)
if let url = Bundle.main.url(forResource: "github-app", withExtension: "pem") {
    return try String(contentsOf: url, encoding: .utf8)
}
// Strategy 2: Relative to executable (swift run / .build/debug)
let execDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
let cwdURL = execDir.appendingPathComponent("github-app.pem")
if FileManager.default.fileExists(atPath: cwdURL.path) {
    return try String(contentsOf: cwdURL, encoding: .utf8)
}
```

### Placeholder Resource Files (Development)
```json
// Resources/github-app.json
{"app_id": "", "installation_id": ""}

// Resources/github-app.pem — valid RSA key structure but placeholder values
// (generate a throw-away key: openssl genrsa -out placeholder.pem 2048)
// Tests mock the HTTP layer; placeholder key only needs to parse without error
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| GitHub App JWT using third-party JWT libraries | Pure Security.framework (no deps) | Established pattern, RepoBar 2023+ | No new SPM dependencies; synchronous API fits project |
| Octokit SDK for GitHub API calls | Direct URLSession + Codable | Always been possible | Keeps codebase lean, matches existing AIService pattern |
| PKCS#8 "BEGIN PRIVATE KEY" assumption | PKCS#1 "BEGIN RSA PRIVATE KEY" (GitHub's actual format) | GitHub's documented behavior | Must strip correct headers in PEM parser |
| jwt-kit (Vapor's JWT library) | Security.framework directly | jwt-kit moved to async-only API in v5 | Cannot use jwt-kit without async refactor of entire project |

**Deprecated/outdated:**
- **swift-jwt (Kitura):** Kitura is unmaintained (IBM archived it 2022); do not use Kitura/Swift-JWT.
- **jwt-kit v4 synchronous API:** jwt-kit v5+ is async-only. Using it would require `Task { }.wait()` workaround or async refactor; Security.framework is simpler.

---

## Open Questions

1. **`iss` claim: App ID (numeric) or Client ID (string)?**
   - What we know: GitHub docs say "client ID (recommended) or application ID." Both are accepted. Client ID is a string like `"Iv1.abc123"`; App ID is a numeric string like `"12345"`.
   - What's unclear: Which field value will be in the bundled `github-app.json` when real credentials are added? The resource file should document which format is stored.
   - Recommendation: Accept either; store whichever identifier GitHub provides in the App settings page. Name the JSON field `"app_id"` and document that it accepts both formats.

2. **PEM file contains newlines — how is it stored in the bundle?**
   - What we know: PEM files have embedded newlines; JSON strings need them escaped. The PEM is stored as a separate `.pem` file (not embedded in JSON), so newlines are preserved verbatim.
   - What's unclear: No issue here — storing PEM as a standalone file is the right call per the CONTEXT.md decision.
   - Recommendation: Load PEM as `String(contentsOf: url, encoding: .utf8)`; newlines are preserved automatically.

3. **Thread safety requirement for `GitHubAuthService`?**
   - What we know: Current agent loop is single-threaded (DispatchSemaphore serializes HTTP). Phase 15/16 will call `getToken()` from agent tool callbacks, which run on the same thread.
   - What's unclear: Whether Vapor web routes (Phase 12) could call `getToken()` from concurrent request handlers.
   - Recommendation: Add an `NSLock` around the cache read/write for safety. Minimal overhead, future-proof.

---

## Validation Architecture

> `workflow.nyquist_validation` is not present in `.planning/config.json` — skipping this section.

---

## Sources

### Primary (HIGH confidence)
- GitHub Docs — [Generating a JSON Web Token (JWT) for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app) — JWT structure, required claims, iat/exp values, RS256 requirement
- GitHub Docs — [Authenticating as a GitHub App installation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation) — POST endpoint, headers, token lifetime (1 hour)
- GitHub Docs — [Managing private keys for GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps) — Confirmed PKCS#1 RSAPrivateKey format, key rotation guidance
- GitHub REST API — [Create an installation access token](https://docs.github.com/en/rest/apps/apps?apiVersion=2022-11-28#create-an-installation-access-token-for-an-app) — Response JSON structure: `token`, `expires_at`, HTTP 201

### Secondary (MEDIUM confidence)
- DeepWiki — [RepoBar JWTSigner for GitHub Apps](https://deepwiki.com/steipete/RepoBar/11.3-jwt-signing-for-github-apps) — Complete working Swift Security.framework RS256 JWT implementation; confirmed no external dependencies; `iat = now - 60`, `exp = now + 510` pattern
- SPM Issue — [Bundle.module fails via symlink #8510](https://github.com/swiftlang/swift-package-manager/issues/8510) — Known issue with `Bundle.module` under Homebrew symlink execution; use `Bundle.main` first
- Apple Developer Forums — [Generate JWT token using RS256](https://developer.apple.com/forums/thread/702003) — Confirmed `SecKeyCreateWithData` attributes and `SecKeyCreateSignature` algorithm constant for PKCS#1v15 SHA256

### Tertiary (LOW confidence)
- WebSearch results for jwt-kit v5 async-only API — multiple sources agree it is async-only; not independently verified against changelog

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Security.framework is system-native, macOS 14+ target, confirmed by multiple working implementations
- Architecture: HIGH — mirrors existing patterns in AIService.swift and RecipeEngine.swift directly; GitHub API is well-documented
- Pitfalls: HIGH for PKCS#1/iat/bundle issues (verified via official docs and known SPM issue); MEDIUM for thread safety (based on code analysis)

**Research date:** 2026-03-30
**Valid until:** 2026-09-30 (GitHub App authentication API is stable; Security.framework is a system framework)

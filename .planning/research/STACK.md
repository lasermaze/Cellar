# Stack Research

**Domain:** macOS CLI Wine launcher — v1.2 Collective Agent Memory stack additions
**Researched:** 2026-03-29
**Confidence:** HIGH (GitHub API patterns — official docs) / HIGH (JWT with Security.framework — Apple dev forums) / HIGH (jwt-kit 5.0 — verified against GitHub repo) / MEDIUM (GitHub App token caching — well-understood pattern, no Swift-specific example found)

---

## Context: What This File Is

This file covers **only new stack additions for v1.2**. The existing stack (Swift 6, ArgumentParser, URLSession, Foundation.Process, Vapor, Leaf, SwiftSoup) is validated in previous STACK.md files. Do not re-litigate those decisions.

The three technical questions for v1.2:

1. How does the agent write JSON config entries to a shared GitHub repo without a local git clone?
2. How does the agent authenticate as a GitHub App bot (no human PAT)?
3. How does the agent read the collective memory repo to query existing configs?

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| GitHub REST API (Contents) | v2022-11-28 | Create/update individual JSON files in the collective memory repo | Single `PUT /repos/{owner}/{repo}/contents/{path}` call writes a file as a new commit. No local git clone, no libgit2, no shell. Already fits the URLSession pattern used for the Anthropic API. |
| GitHub REST API (Git Database) | v2022-11-28 | Batch-read the memory index in one request | `GET /repos/{owner}/{repo}/git/trees/{sha}?recursive=1` returns the entire repo file tree without cloning. Used for the initial "does a config for this game already exist?" query. |
| Security.framework (built-in) | macOS 14+ | RS256 JWT signing for GitHub App authentication | `SecKeyCreateSignature` with `.rsaSignatureMessagePKCS1v15SHA256` produces a valid RS256 JWT without any third-party library. The JWT is only needed to bootstrap an installation access token — 10-20 lines of Swift with `Security` import. |
| vapor/jwt-kit | 5.0.0 | RS256 JWT signing (alternative to Security.framework approach) | Pure Swift, SPM-native, Swift 6 compatible, supports RSA signing. Only add this if the native Security.framework approach proves brittle in practice. jwt-kit is already adjacent to the existing Vapor dependency. |

**Core decision: GitHub REST API over libgit2.** The agent's write pattern is: produce a JSON file, push it to GitHub. The agent never needs a full local clone with history, branching, or merging. Using `PUT /repos/.../contents/{path}` handles this in one HTTP call. Every libgit2 Swift binding surveyed (SwiftGit2, SwiftGitX 0.4.0, swift-libgit2) adds a compiled C library dependency and significant complexity for no benefit here.

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| vapor/jwt-kit | 5.0.0 | RS256 JWT generation for GitHub App authentication | Only if the native Security.framework RS256 approach proves too verbose or fails edge cases (e.g., key format variations). jwt-kit is adjacent to the existing Vapor dependency so adding it does not increase vendor surface much. |

No other new SPM dependencies are required for v1.2.

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| (no new tools) | — | No new toolchain additions for v1.2 |

---

## Feature-by-Feature Analysis

### 1. Writing Configs to GitHub — GitHub REST Contents API

**Approach: `PUT /repos/{owner}/{repo}/contents/{path}`**

This is the correct tool for the v1.2 write pattern. The agent produces a `SuccessRecord`-derived JSON struct and wants to store it at a known path like `entries/cossacks-european-wars/abc123.json`. One HTTP call does it.

**Sequence for writing a new memory entry:**

1. Check if the file already exists: `GET /repos/{owner}/{repo}/contents/{path}` — returns the current SHA if it exists.
2. Write (create or update): `PUT /repos/{owner}/{repo}/contents/{path}` with `message`, `content` (base64-encoded JSON), and `sha` (only needed for updates, omit for creates).

**Request body:**
```swift
struct ContentsWriteBody: Encodable {
    let message: String            // commit message, e.g. "agent: add cossacks config (wine 9.0, arm64)"
    let content: String            // base64-encoded JSON
    let sha: String?               // nil for new file, blob SHA for update
    let branch: String?            // default: repo's default branch
}
```

**Conflict handling:** If two agents simultaneously write to the same path, the second PUT will return 409 (the SHA in its request will be stale). The correct handling is: retry the write once by re-fetching the current SHA and re-PUT-ing. The collective memory model naturally avoids destructive conflicts — each agent entry is scoped by game ID and a timestamp or run ID, so duplicate writes at identical paths should be rare.

**Why not the Git Database API for writes?** The Git Database API (blobs + trees + commits + refs) is 4-5 sequential HTTP calls to write one file. The Contents API does it in 1-2 calls. The Git Database API is useful for reading (tree traversal) but excessive for writing single files.

**Confidence:** HIGH — official GitHub documentation, well-documented endpoint.

---

### 2. Reading the Collective Memory — GitHub REST Git Trees API

**Approach: `GET /repos/{owner}/{repo}/git/trees/{sha}?recursive=1`**

When the agent starts, it needs to know what games have known configs before downloading individual entries. The tree API returns every file path in the repo in one call.

```swift
// 1. Get current HEAD SHA
GET /repos/{owner}/{repo}/git/ref/heads/main
// Response: { "object": { "sha": "abc..." } }

// 2. Walk the tree
GET /repos/{owner}/{repo}/git/trees/abc...?recursive=1
// Response: { "tree": [{ "path": "entries/cossacks/abc.json", "sha": "..." }, ...] }
```

From the tree response, the agent can determine "entries exist for this game ID" without downloading every file. It then fetches only the relevant entry files via `GET /repos/{owner}/{repo}/contents/{path}`.

For reading, unauthenticated requests to a public repo get 60 requests/hour. Authenticated requests get 5,000/hour. The agent should always use its installation token for reads — this avoids rate limiting and also works for private repos during development.

**Confidence:** HIGH — official GitHub documentation.

---

### 3. GitHub App Authentication — RS256 JWT to Installation Token

**The two-step auth flow:**

```
GitHub App private key (.pem)
    → RS256-signed JWT (10 minute TTL)
    → POST /app/installations/{installation_id}/access_tokens
    → Installation access token (1 hour TTL)
    → Use as: Authorization: Bearer ghs_...
```

**Step 1: Build the JWT (no third-party library needed)**

GitHub requires RS256 (PKCS#1 v1.5 + SHA-256). macOS `Security.framework` provides exactly this via `SecKeyCreateSignature(.rsaSignatureMessagePKCS1v15SHA256)`.

Required JWT claims:
- `iss`: GitHub App client ID (or numeric App ID for legacy apps)
- `iat`: current Unix time minus 60 seconds (clock skew buffer)
- `exp`: `iat + 600` (10 minutes maximum)

```swift
import Security
import Foundation

func buildGitHubAppJWT(appId: String, privateKeyPEM: String) throws -> String {
    // 1. Encode header + payload
    let header = #"{"alg":"RS256","typ":"JWT"}"#
    let now = Int(Date().timeIntervalSince1970)
    let payload = "{\"iss\":\"\(appId)\",\"iat\":\(now - 60),\"exp\":\(now + 540)}"

    let headerB64  = base64url(header.data(using: .utf8)!)
    let payloadB64 = base64url(payload.data(using: .utf8)!)
    let message    = "\(headerB64).\(payloadB64)"

    // 2. Load RSA private key from PEM
    let key = try loadRSAPrivateKey(pem: privateKeyPEM)

    // 3. Sign with RS256
    var error: Unmanaged<CFError>?
    guard let sig = SecKeyCreateSignature(
        key,
        .rsaSignatureMessagePKCS1v15SHA256,
        message.data(using: .utf8)! as CFData,
        &error
    ) else { throw error!.takeRetainedValue() }

    return "\(message).\(base64url(sig as Data))"
}

private func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
```

Loading the PEM key requires `SecItemImport` or `SecKeyCreateWithData` — the PEM must be stripped of its header/footer and base64-decoded to DER before passing to `SecKeyCreateWithData`. This is ~20 lines but well-documented on Apple developer forums.

**Alternative (simpler): vapor/jwt-kit 5.0**

If the native Security.framework approach produces too much boilerplate, add jwt-kit:

```swift
// Package.swift
.package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0")

// Usage
import JWTKit
let keys = JWTKeyCollection()
try await keys.add(rsa: Insecure.RSA.PrivateKey(pem: privateKeyPEM), digestAlgorithm: .sha256, kid: "github-app")
let token = try await keys.sign(payload, kid: "github-app")
```

jwt-kit 5.0 is Swift 6 compatible, does not require Vapor, and is standalone. Note that RSA key types are placed in the `Insecure` namespace in v5 (GitHub notes this discourages new RSA use in favor of ECDSA, but GitHub Apps require RS256, so Insecure.RSA is the correct choice here).

**Recommendation:** Start with native Security.framework. If the PEM loading proves fiddly, add jwt-kit. The functionality is identical; jwt-kit is just more ergonomic.

**Step 2: Exchange JWT for Installation Access Token**

```swift
// POST /app/installations/{installation_id}/access_tokens
// Header: Authorization: Bearer <JWT>
// Response: { "token": "ghs_...", "expires_at": "2026-03-29T15:00:00Z" }
```

**Token caching:** Installation tokens expire after 1 hour. The agent should cache the token with its `expires_at` timestamp and refresh it proactively when less than 5 minutes remain. A simple `TokenCache` struct with an expiry check before each API call is sufficient — no complex refresh middleware needed since agent runs are typically short-lived.

```swift
struct InstallationToken {
    let token: String
    let expiresAt: Date

    var isValid: Bool { Date().addingTimeInterval(300) < expiresAt }  // 5 min buffer
}
```

**Where to store the private key:** The GitHub App private key (.pem) and App ID are configuration — store in `~/.cellar/.env` alongside `ANTHROPIC_API_KEY`. The existing `loadEnvironment()` in `AIService.swift` already handles this pattern.

```
GITHUB_APP_ID=123456
GITHUB_APP_INSTALLATION_ID=78901234
GITHUB_APP_PRIVATE_KEY_PATH=/path/to/private-key.pem
COLLECTIVE_MEMORY_REPO=owner/cellar-memory
```

**Confidence:** HIGH — GitHub App auth flow documented in official GitHub docs. RS256 via Security.framework confirmed on Apple developer forums.

---

### 4. Collective Memory Schema — Extending SuccessRecord

The existing `SuccessRecord` struct in `SuccessDatabase.swift` already captures the right fields: Wine version, OS, bottle type, environment variables, DLL overrides, registry, pitfalls, and a narrative. This is the right foundation.

The collective memory entry needs three additions over the local `SuccessRecord`:

```swift
struct CollectiveMemoryEntry: Codable {
    // Core config (same as SuccessRecord)
    let schemaVersion: Int           // start at 1, increment on breaking changes
    let gameId: String
    let gameName: String
    let wineVersion: String?
    let os: String?                  // "macOS 15.2"
    let arch: String?                // "arm64", "x86_64"
    let bottleType: String?
    let environment: [String: String]
    let dllOverrides: [DLLOverrideRecord]
    let registry: [RegistryRecord]
    let gameSpecificDlls: [GameSpecificDLL]
    let pitfalls: [PitfallRecord]

    // Collective additions
    let reasoningChain: [String]     // agent's diagnosis steps in order
    let confidenceVotes: Int         // times other agents confirmed this config works
    let contributedAt: String        // ISO8601
    let contributedBy: String        // agent run ID or "community"
    let environmentFingerprint: EnvironmentFingerprint
}

struct EnvironmentFingerprint: Codable {
    let wineVersion: String          // "wine-9.0 (Gcenx)"
    let macOSVersion: String         // "15.2"
    let cpuArch: String              // "arm64"
    let metalSupported: Bool
    let gptInstalled: Bool           // GPTK/D3DMetal present
}
```

**Repo layout:**

```
cellar-memory/
  index.json                         # game IDs with entry counts + last updated
  entries/
    {gameId}/
      {contributedAt}-{arch}.json    # e.g. cossacks-european-wars/2026-03-29T10:00:00Z-arm64.json
```

The `index.json` is a lightweight catalog the agent can download on startup (~1-5KB for early versions) to determine what games have known configs before fetching full entries.

**Confidence:** HIGH — based on analysis of existing SuccessRecord schema, architecture follows established Git-backed knowledge base patterns.

---

### 5. Environment Matching — No New Library

The agent's "reason about fit" step is a comparison function, not a new library. It takes a stored `EnvironmentFingerprint` and a `LocalEnvironment` struct and returns a confidence score.

```swift
func configFitScore(stored: EnvironmentFingerprint, local: LocalEnvironment) -> ConfigFit {
    // Exact match: full confidence
    // Wine major version match, different minor: high confidence
    // Different CPU arch: reject (arm64 config will not help x86_64 and vice versa)
    // GPTK present locally but not in stored entry: might unlock new options (flag to agent)
    // macOS major version match, minor differs: medium confidence
}
```

`LocalEnvironment` is populated at agent startup from `sw_vers`, `uname -m`, and `wine --version` shell calls — all already used in the codebase.

**Confidence:** HIGH — logic only, no library needed.

---

## Installation

```swift
// Package.swift — ONLY if using jwt-kit instead of Security.framework for JWT:
.package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0")

// Add to target dependencies if jwt-kit is used:
.product(name: "JWTKit", package: "jwt-kit")
```

If the native Security.framework RS256 approach is used, **no Package.swift changes are needed for v1.2**. All GitHub API calls use URLSession (already in use). All JWT crypto uses Security.framework (already available on macOS 14+).

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| GitHub REST API (URLSession) | libgit2 via SwiftGitX or SwiftGit2 | Only if Cellar needs full local clone semantics (branch management, history traversal, local-first offline writes). Not needed for v1.2's "read index, write entry" pattern. |
| GitHub REST API (URLSession) | `git` process via Foundation.Process | Viable fallback if GitHub API rate limits become a problem. `git clone --depth 1` + `git add/commit/push` with a bot token in the URL works fine. Adds ~100ms per operation and requires a temp directory. Do not implement preemptively — the API approach is cleaner. |
| Security.framework RS256 | vapor/jwt-kit | Use jwt-kit if PEM key loading via Security.framework proves too verbose or if the project already imports jwt-kit for another reason. |
| Security.framework RS256 | Kitura/Swift-JWT | Swift-JWT is Kitura-era (IBM), minimally maintained since 2022. Do not add. jwt-kit is the active alternative if Security.framework is not used. |
| Contents API (PUT /contents) | Git Database API (blobs + trees + commits) | Use the Git Database API if writing many files in one commit (e.g., bulk import). For single-file writes, the Contents API is simpler: 2 HTTP calls vs 5. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| SwiftGit2 | Last meaningful SPM support PR was 2020, libgit2 version is stale, does not support Swift 6 Sendable | GitHub REST API via URLSession |
| SwiftGitX 0.4.0 | Newest Swift libgit2 wrapper (December 2025), but push/authentication support is unconfirmed in docs. Version 0.x signals API instability. Would add a compiled C library (libgit2) to the build. | GitHub REST API via URLSession |
| Kitura/Swift-JWT | Minimally maintained since 2022, Kitura project effectively dormant | vapor/jwt-kit 5.0 or Security.framework |
| Octokit.swift | Version 0.11.0, does not document GitHub App authentication or git database operations | Direct URLSession calls to GitHub REST API |
| GitHub Personal Access Token (PAT) | Tied to a human account, requires manual rotation, does not scale to community use | GitHub App installation token (bot identity, scoped, auto-expires) |
| Vector embedding / RAG for memory lookup | Massively over-engineered for v1.2. The game ID is a stable key; config lookup is a dictionary lookup, not semantic search. | Direct JSON file fetch by game ID from GitHub repo |

## Stack Patterns by Variant

**If the collective memory repo is private (during development):**
- Use authenticated requests for all reads (not just writes)
- The GitHub App installation token handles both read and write to private repos it has access to

**If the collective memory repo is public (community launch):**
- Use unauthenticated GET for reads (60 req/hour per IP is fine for startup query)
- Use installation token only for writes (POST/PUT)
- This avoids distributing the private key to users who only want to read

**If the GitHub App private key is not configured:**
- Agent skips the "push to collective memory" step after solving a game
- Agent can still read from a public repo without auth
- Degrade gracefully — never block the agent loop on missing collective memory auth

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| vapor/jwt-kit 5.0.0 | Swift 6.0+, macOS 14+ | Swift 6 native. RSA is in `Insecure` namespace by design (GitHub Apps require RS256, so this is the correct choice regardless of the namespace name). |
| Security.framework (built-in) | macOS 14+ | `SecKeyCreateSignature` with `.rsaSignatureMessagePKCS1v15SHA256` is available since macOS 10.12. Not deprecated. |
| GitHub REST API v2022-11-28 | — | Current stable API version. Set `X-GitHub-Api-Version: 2022-11-28` header on all requests. |

## Sources

- [GitHub Docs — Creating or updating file contents](https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents) — PUT /contents endpoint, SHA requirement for updates (HIGH confidence — official docs)
- [GitHub Docs — Using the REST API to interact with your Git database](https://docs.github.com/en/rest/guides/using-the-rest-api-to-interact-with-your-git-database) — Git trees/blobs/commits sequence (HIGH confidence — official docs)
- [GitHub Docs — Generating a JWT for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app) — RS256 requirement, iss/iat/exp claims, 10-minute expiry (HIGH confidence — official docs)
- [GitHub Docs — Generating an installation access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app) — POST /app/installations/{id}/access_tokens, 1-hour token expiry (HIGH confidence — official docs)
- [Apple Developer Forums — Generate JWT token using RS256](https://developer.apple.com/forums/thread/702003) — SecKeyCreateSignature with rsaSignatureMessagePKCS1v15SHA256 confirmed (HIGH confidence)
- [vapor/jwt-kit GitHub](https://github.com/vapor/jwt-kit) — v5.0.0, Swift 6, standalone (no Vapor required), RSA in Insecure namespace (HIGH confidence)
- [JWTKit is no longer Boring! — Vapor Blog](https://blog.vapor.codes/posts/jwtkit-v5/) — v5 migration notes, RSA moved to Insecure namespace (HIGH confidence)
- [ibrahimcetin/SwiftGitX GitHub](https://github.com/ibrahimcetin/SwiftGitX) — v0.4.0 December 2025, push auth unconfirmed (MEDIUM confidence)

---
*Stack research for: Cellar v1.2 Collective Agent Memory — new capabilities only*
*Researched: 2026-03-29*

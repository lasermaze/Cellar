# Phase 13: GitHub App Authentication - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

The agent can authenticate to GitHub as a bot — generating RS256 JWTs, exchanging them for installation tokens, and refreshing those tokens automatically. This phase builds the auth layer only; reading and writing collective memory entries are Phase 15 and 16 respectively.

</domain>

<decisions>
## Implementation Decisions

### Key distribution
- GitHub App private key (.pem) bundled as a Swift package resource (`Resources/github-app.pem`)
- App ID and Installation ID in a companion resource file (`Resources/github-app.json`)
- User can override with env vars: `GITHUB_APP_KEY_PATH`, `GITHUB_APP_ID`, `GITHUB_INSTALLATION_ID` (checked first, then ~/.cellar/.env, then bundled resource)
- Key rotation happens via CLI updates only — no phone-home or startup network check
- During development: placeholder IDs in resource files, tests mock GitHub API; real credentials dropped in before shipping

### Custom app support
- Env override cascade naturally enables self-hosting: users set their own app credentials in ~/.cellar/.env
- Memory repo also overridable via `CELLAR_MEMORY_REPO` env var, defaults to `cellar-community/memory`
- No extra UI or config surface needed — the existing .env pattern covers it

### Repo identity
- Org: `cellar-community` (dedicated org, separate from Cellar source)
- Repo: `memory` (full path: `cellar-community/memory`)
- Phase 13 builds auth code only — GitHub App and repo created manually when ready
- All GitHub API interactions use the REST Contents API (no git clone/push, no git binary dependency)

### Claude's Discretion
- RS256 JWT implementation details (Security.framework vs swift-crypto via Vapor)
- Token caching strategy (in-memory with TTL check vs file-based)
- Error types and internal error handling structure
- Test structure and mocking approach for GitHub API

</decisions>

<specifics>
## Specific Ideas

- Priority cascade for credentials follows existing pattern: env var > ~/.cellar/.env > bundled resource (matches how Anthropic API keys work today)
- Contents API for all GitHub operations: `GET /repos/{owner}/{repo}/contents/...` for reads, `PUT` for writes (SHA-based conflict detection built in)
- Placeholder resource files during development so auth code compiles and tests pass without real credentials

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CellarConfig.swift`: Codable config with priority cascade (env > file > default) — extend for GitHub App settings
- `CellarPaths.swift`: Centralized path management under ~/.cellar — add GitHub token cache path
- `.env` loading in SettingsController: existing KEY=VALUE parser with env var override — reuse for GitHub credentials
- URLSession + DispatchSemaphore pattern in AgentLoop/AIService: synchronous HTTP calls — reuse for GitHub API

### Established Patterns
- HTTP calls: URLSession.shared with DispatchSemaphore bridge (AgentLoop lines 407-465)
- Retry: exponential backoff [1s, 2s, 4s], retry on 5xx/429, abort on other 4xx
- Credential storage: ~/.cellar/.env for secrets, ~/.cellar/config.json for settings
- Models: Codable structs in Sources/cellar/Models/ (AnthropicRequest/Response pattern)
- Services: standalone files in Sources/cellar/Core/ with injected dependencies

### Integration Points
- New `GitHubAuthService` in Sources/cellar/Core/ — provides installation tokens to future phases
- Extend Package.swift target resources to include github-app.pem and github-app.json
- swift-crypto already available transitively via Vapor dependency (RSA signing support)
- Future phases (15, 16) will call GitHubAuthService.getToken() before Contents API requests

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 13-github-app-authentication*
*Context gathered: 2026-03-30*

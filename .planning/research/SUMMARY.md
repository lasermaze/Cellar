# Project Research Summary

**Project:** Cellar v1.2 — Collective Agent Memory
**Domain:** Git-backed shared knowledge base for AI agents contributing and consuming Wine game compatibility configs
**Researched:** 2026-03-29
**Confidence:** HIGH

## Executive Summary

Cellar v1.2 extends a working local-first Wine game launcher with collective memory: after an AI agent solves a game, it pushes a structured config entry to a shared GitHub repository so future agents on other machines can find and apply the solution. This is an agent-first compatibility database — the first of its kind, as ProtonDB, WineHQ AppDB, and similar databases are all human-written and human-read. The key differentiator is the stored reasoning chain: not just "what settings work" but "why they work," enabling future agents to adapt configs intelligently rather than copy them blindly. The architecture is deliberately minimal — GitHub as the database, GitHub App authentication for writes, URLSession (already in use) for all API calls, and no new infrastructure dependencies beyond an optional `vapor/jwt-kit` fallback for JWT signing.

The recommended implementation avoids two major wrong turns. First, libgit2 wrappers are not the right tool: this feature writes one JSON file per game via the GitHub Contents API, which is two HTTP calls. A libgit2 dependency adds a compiled C library and significant complexity with no benefit. Second, and non-negotiably, the GitHub App private key must not ship with the CLI binary — every user would be able to impersonate the bot. The correct architecture is a thin server-side token proxy that holds the private key and returns short-lived installation access tokens on demand. This is the standard pattern for open-source CLI bots (Renovate, Probot, semantic-release) and skipping it is a security failure, not a simplification.

The critical risk concentration is in Phase 1 (GitHub App auth + proxy). Once the authentication plumbing works and the collective memory entry schema is locked, the remaining phases follow clear patterns with low uncertainty. Schema design must happen before any community entries are written — retroactive migrations on a public Git repo are painful and breaking schema changes require coordinated rollouts across all client versions. Confidence voting requires Sybil resistance from day one; per-game-per-account deduplication is the minimum viable protection before public launch.

---

## Key Findings

### Recommended Stack

No new SPM dependencies are required if the native `Security.framework` RS256 approach is used for JWT signing. `SecKeyCreateSignature(.rsaSignatureMessagePKCS1v15SHA256)` is available on macOS 14+ and produces a valid GitHub App JWT in ~60 lines of Swift. The optional alternative is `vapor/jwt-kit 5.0.0` — Swift 6 compatible, standalone (does not require Vapor), RSA in the `Insecure` namespace by design. All GitHub API calls use URLSession, which already handles the Anthropic API. See `.planning/research/STACK.md` for full analysis.

**Core technologies:**
- GitHub REST API — Contents endpoint (`PUT /repos/.../contents/{path}`): single HTTP call to write a memory entry file; no local git clone needed
- GitHub REST API — Git Trees endpoint (`GET /repos/.../git/trees/{sha}?recursive=1`): efficient bulk read of the repo file index for startup queries
- Security.framework (built-in, macOS 14+): RS256 JWT signing for GitHub App auth with no SPM dependency
- vapor/jwt-kit 5.0.0 (optional fallback): if PEM key loading via Security.framework proves verbose; already adjacent to the existing Vapor dependency

**What to avoid:**
- SwiftGit2 / SwiftGitX: Swift 6 incompatible or 0.x API instability; compiled C dependency for no benefit over the Contents API
- Kitura/Swift-JWT: dormant since 2022; use Security.framework or jwt-kit instead
- Vector embeddings / RAG for memory lookup: massively over-engineered; game ID is a stable key, not a semantic query
- GitHub Personal Access Token: tied to a human account, does not scale to community use

### Expected Features

See `.planning/research/FEATURES.md` for full analysis, competitor comparison, and dependency graph.

**Must have (table stakes — v1.2 core, P1):**
- Memory entry schema definition — must be locked before any code is written; fields: game_id, wine_config, reasoning_chain, environment snapshot (arch, wine_flavor, macOS version), confirmations, status, schemaVersion
- GitHub App authentication — app credentials configured for write access; required by all write features
- Query collective memory — agent checks for existing solutions before diagnosis; best-effort, non-blocking
- Environment-aware fit assessment — agent reasons about environment delta before applying any stored config; never blindly applies
- Automatic push after success — agent pushes after `save_success` + user-confirmed launch; no human approval in the path
- Confidence accumulation — increments confirmations on matching config; tracks unique environment hashes; deduplication from day one

**Should have (v1.2 stretch, add after P1 path validated, P2):**
- Staleness detection — flags entries where current Wine major version is more than one ahead of last confirmation; triggers re-validation
- Web interface memory state — extend existing web UI to show memory stats, per-game entries, recent contributions
- Entry deprecation (superseded status) — marks old configs without deleting; Git history provides audit trail

**Defer to v2+:**
- Environment diversity weighting for confidence — meaningful only at 50+ games in database
- Cross-game config transfer (same-engine suggestions) — requires enough entries per engine to be useful
- Abuse / spam detection — defer until community scale makes it a real problem

**Anti-features (do not build):**
- Human approval workflow for contributions — kills automatic contribution, which is the core value prop; WineHQ AppDB's gated model explains its staleness
- Centralized backend API instead of Git — adds server infrastructure, hosting costs, uptime requirements
- User identity / attribution — privacy concern; environment hash is sufficient contributor identity
- Mandatory collective memory with no opt-out — forced contribution of system specs violates user trust

### Architecture Approach

The integration is additive and surgical: two new Core files (`CollectiveMemoryClient.swift`, `GitHubAppAuth.swift`), one new Model (`CollectiveMemoryEntry.swift`), one new web Controller (`MemoryController.swift`), and targeted modifications to `AIService.runAgentLoop()`, `CellarConfig`, `CellarPaths`, and `WebApp`. `AgentLoop`, `AgentTools`, `BottleManager`, `SuccessDatabase`, `RecipeEngine`, and all existing Controllers are untouched. The agent does NOT get new tools for collective memory — query and push happen in the AIService orchestration layer, before and after the loop. This preserves the agent's role as a problem-solver rather than a data curator. See `.planning/research/ARCHITECTURE.md` for component diagrams, data flow, and the recommended build order.

**Major components:**
1. `GitHubAppAuth` — JWT generation via Security.framework + installation token exchange; token cached with 5-minute safety buffer before the 1-hour expiry
2. `CollectiveMemoryClient` — read/write operations against GitHub Contents API; best-effort (returns Optional / Bool, never throws; network failure is a soft failure that degrades gracefully)
3. `CollectiveMemoryEntry` — lean Codable schema derived from `SuccessRecord`; includes `schemaVersion`, `reasoningChain`, `environmentContext`, `confirmations`; lenient decoding for forward compatibility
4. `AIService.runAgentLoop()` modifications — query before loop (injects memory context into initial user message); push after loop on confirmed success (never blocks the success message to user)
5. `MemoryController` — Vapor routes for web UI `/memory` list and `/memory/:gameId` detail views

**Key patterns:**
- Best-effort reads: `CollectiveMemoryClient.query()` returns `Optional`, never throws; nil = proceed without context, same as pre-v1.2 behavior
- Post-loop push: write happens after `AgentLoop.run()` completes, never inside the loop or in agent tools
- Optimistic locking: PUT requires current blob SHA; on 409 Conflict, retry once with fresh GET (fetch-rebase-push pattern)
- Single file per game: `entries/{gameId}.json`; same-game concurrent writes are rare and resolved by retry

### Critical Pitfalls

See `.planning/research/PITFALLS.md` for all 10 pitfalls with full prevention strategies, warning signs, recovery steps, and a "Looks Done But Isn't" checklist.

1. **GitHub App private key cannot ship in the binary** — use a token proxy server (Cloudflare Worker, Railway, or Fly.io); private key stays server-side; CLI requests short-lived installation tokens from the proxy. Non-negotiable: embedding the key grants every user bot impersonation capability. Address in Phase 1 before any other code is written.

2. **Push race condition on concurrent agent writes** — implement fetch-rebase-push retry loop (max 3 attempts, exponential backoff: 2s, 4s, 8s); missing retry means confirmed solutions are silently lost; confirmed by real GitHub internal issue report (`push_repo_memory.cjs` bug #19476). One file per game minimizes conflicts. Address in Phase 1/2.

3. **Environment schema underspecified** — capture `arch` (arm64/x86_64), `wine_flavor` (crossover/stable/devel), `metal_supported`, `rosetta`, `gptk_installed`, not just `wine_version` and `macos_version`. ARM/Intel mismatch is a hard rejection, not a warning. Address in Phase 2 (schema design, before first write).

4. **Schema forward compatibility** — include `schemaVersion: 1` from day one; all non-identifier fields optional for readers; use lenient Codable decoding; new fields must have defaults. Breaking this retroactively requires migrating a public repo. Address in Phase 2.

5. **Reasoning chain privacy** — sanitize paths (`/Users/`, `WINEPREFIX=`, username patterns) before committing to the public repo; store a summarized diagnosis narrative (2KB cap), not the raw tool-call transcript. Make reasoning chain sharing opt-in. Address in Phase 3.

---

## Implications for Roadmap

Based on combined research, the dependency graph drives the phase order: auth is foundational for all writes, schema must be locked before first community write, read path must be validated before write path, and web UI is purely additive and comes last.

### Phase 1: GitHub App Authentication + Token Proxy

**Rationale:** Auth is the critical path and the highest technical uncertainty. It is also the most security-sensitive: getting it wrong means shipping a binary with a compromised credential surface. Nothing else can be built correctly until the auth model is settled. Per pitfall research, the proxy architecture must be decided before any code is written — it affects what the CLI sends, what the server validates, and how token refresh works. The 1-hour token expiry must be handled from the start; retrofitting it after a session-length bug appears in production is harder.

**Delivers:** Working GitHub App installation token flow; RS256 JWT via Security.framework; token caching with 5-minute safety buffer; thin proxy endpoint (or documented per-user setup if proxy deployment is deferred to v1.3); `GitHubAppAuth.swift`; `CellarPaths.githubAppKeyFile`

**Addresses:** GitHub App authentication (P1 feature); token expiry handling (Pitfall 5); private key security model (Pitfall 1)

**Avoids:** Embedding private key in binary or `~/.cellar/config`; unhandled 401 on long sessions; blocking downstream phases on unresolved auth design

---

### Phase 2: Memory Entry Schema + Collective Memory Repo

**Rationale:** Schema must be locked before any community entries are written — one bad design decision now means a painful migration across all public entries later. This phase has zero code dependencies on Phase 1 (it is pure data modelling) and can be designed in parallel with Phase 1, but the repo setup (creating `cellar-community/memory`, establishing `entries/` structure, testing writes) requires auth from Phase 1.

**Delivers:** `CollectiveMemoryEntry.swift` model; `entries/{gameId}.json` repo layout; `index.json` catalog for fast startup queries; `schemaVersion: 1` from entry one; lenient Codable decoding pattern (unknown fields ignored, optional fields defaulted); `CellarConfig` additions for GitHub App config fields

**Addresses:** Memory entry schema (P1 feature); forward compatibility (Pitfall 7); environment underspecification (Pitfall 3)

**Implements:** `CollectiveMemoryEntry` schema component; collective memory repo structure

**Avoids:** Strict Codable decode on community data; missing `arch`/`wine_flavor` fields; schema without version field

---

### Phase 3: Read Path — Query + Environment-Aware Fit Assessment

**Rationale:** The read path (query → assess → apply) is the primary user-facing value. Get reads right before writes. Wrong reads waste the agent's time; wrong writes corrupt community data. The read path also validates that the Phase 2 schema design works in the agent context before the write path commits entries to the public repo.

**Delivers:** `CollectiveMemoryClient.swift` (read operations: `query(gameId:)`, `queryAll()`); `AIService.runAgentLoop()` modification to inject memory context into initial user message before the loop; local/collective priority router logic (local successdb match wins over collective memory query for already-solved games); `MemoryRouter` or equivalent

**Addresses:** Query collective memory (P1 feature); environment-aware fit assessment (P1 feature); local/collective inconsistency (Pitfall 10); performance trap of cloning on every launch (Pitfall 6)

**Implements:** `CollectiveMemoryClient` read path; `AIService` pre-loop integration

**Avoids:** Blocking launch on network fetch; replacing local successdb match with collective query; agent applying configs without environment reasoning

---

### Phase 4: Write Path — Automatic Push + Confidence Accumulation

**Rationale:** Write path requires Phase 1 (auth) and Phase 3 (read path, to fetch existing entry SHA for updates). Building write on top of a validated read path reduces the risk of writing malformed entries. Confidence accumulation ships with the write path — a write path without deduplication is a Sybil attack surface from day one, and retrofitting it after public launch requires migrating all existing vote counts.

**Delivers:** `CollectiveMemoryClient.swift` (write operations: `push(entry:)`); `AIService.runAgentLoop()` post-loop push (best-effort, never blocks success message); `CollectiveMemoryEntry.from(successRecord:reasoningChain:existingEntry:)` factory; retry-on-409 conflict handling (max 3 attempts, exponential backoff); per-game-per-account confirmation deduplication; reasoning chain sanitization (path pattern replacement); pending-contributions local queue for push failures

**Addresses:** Automatic push after success (P1 feature); confidence accumulation (P1 feature); push race condition (Pitfall 2); memory poisoning / confidence inflation (Pitfalls 4, 9); reasoning chain privacy (Pitfall 8)

**Avoids:** Push without retry; raw agent transcript stored in public entry; new entry starting at high confidence; same account voting multiple times on same game

---

### Phase 5: Web UI — Memory State View

**Rationale:** Informational only; no blocking dependencies except needing real entries to display. Ships after the core agent-facing features are working and the database has real entries to show. Lower risk, follows the exact same Vapor + Leaf pattern as `GameController`.

**Delivers:** `MemoryController.swift`; `/memory` list and `/memory/:gameId` detail Leaf templates; `WebApp.configure()` registration; `SettingsController` additions for memory config fields (GitHub App ID, installation ID, memory repo, key path)

**Addresses:** Web interface memory state (P2 stretch feature); transparency in trust model ("57 games solved, 234 confirmations")

**Implements:** `MemoryController` web component

---

### Phase 6: End-to-End Validation + Stretch Features

**Rationale:** Full flow validation across two agent sessions (solve → push → new session sees context) requires all prior phases to be complete. Staleness detection and entry deprecation are P2 stretch features that need real entries to be meaningful.

**Delivers:** End-to-end test: solve game → verify push to test repo → launch again → verify agent sees memory context in initial message; staleness detection (flag entries where current Wine major version is ahead of last confirmation range); entry deprecation (`superseded` status without deletion); performance verification (clone time with 500-entry synthetic repo); all "Looks Done But Isn't" checklist items from PITFALLS.md verified

**Addresses:** Staleness detection (P2 stretch); entry deprecation (P2 stretch); offline behavior verified; schema version handling verified

---

### Phase Ordering Rationale

- Auth before everything: the proxy architecture decision cascades into CLI request format, server validation, and token refresh — it cannot be retrofitted cleanly
- Schema before first write: public Git repos cannot be cleanly migrated; every field omission becomes permanent debt across all community entries
- Read before write: validates the schema works in practice before committing to the public; wrong reads are recoverable (agent falls back to fresh diagnosis), wrong writes pollute community data
- Write before web UI: the web UI has nothing meaningful to display until real entries exist
- Confidence deduplication ships with write path, not as a later addition: Sybil resistance cannot be retroactively applied to existing vote counts
- `AgentLoop`, `AgentTools`, `SuccessDatabase`, `BottleManager` are never touched: the integration lives entirely in `AIService` orchestration, preserving the agent's stable tool surface

---

### Research Flags

Phases likely needing deeper research during planning:

- **Phase 1 (GitHub App Auth + Proxy):** The proxy server architecture needs concrete implementation decisions — hosting platform (Cloudflare Worker vs Railway vs Fly.io), request format, rate limiting strategy per-IP or per-Cellar-installation. The CLI-side auth flow is well-documented; the proxy design is not. Recommend `/gsd:research-phase` focus on "open-source CLI bot token proxy patterns."
- **Phase 4 (Write Path):** Confidence deduplication across a distributed system with no user accounts requires careful design. The GitHub account age + per-account weekly limit approach from pitfalls research is directionally correct but the GitHub App rejection mechanism implementation is unspecified. Needs concrete design before Phase 4 begins.

Phases with standard patterns (skip research-phase):

- **Phase 2 (Schema):** Codable schema design and lenient JSON decoding are well-documented Swift patterns. The schema fields are fully specified across FEATURES.md and ARCHITECTURE.md.
- **Phase 3 (Read Path):** GitHub Contents API GET is simple and well-documented. URLSession pattern is established in the codebase. No unknowns.
- **Phase 5 (Web UI):** Vapor + Leaf route pattern is established in the codebase. `MemoryController` follows the exact same structure as `GameController`.
- **Phase 6 (Validation):** Integration testing, not research.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | GitHub REST API and GitHub App auth flow verified against official docs. Security.framework RS256 confirmed on Apple developer forums. vapor/jwt-kit 5.0.0 verified from source. No ambiguous dependency choices remain. |
| Features | MEDIUM | No direct prior art for agent-first Git-backed game config sharing. Analogous systems (ProtonDB, WineHQ AppDB, DebugBase MCP) researched and compared. Core table-stakes features are clear; confidence voting design has implementation unknowns around Sybil resistance. |
| Architecture | HIGH | Integration points verified by direct codebase inspection. Data flow is explicit. Build order follows clear dependency graph. Component responsibilities cleanly bounded and non-overlapping. |
| Pitfalls | HIGH | GitHub App auth mechanics verified against official docs. Git concurrency pitfall confirmed by real GitHub internal issue report. Memory poisoning vectors from OWASP Agentic AI taxonomy. Key leakage threat confirmed by industry data. |

**Overall confidence:** HIGH

### Gaps to Address

- **Token proxy hosting and deployment:** The proxy architecture is the correct answer for key distribution, but the specific hosting platform and request protocol are unspecified. Needs a decision before Phase 1 implementation begins. If proxy deployment is out of scope for v1.2, the per-user installation fallback (each user provides their own app ID + key) needs documented UX — first-run setup flow and clear error messaging when auth is unconfigured.

- **Confidence deduplication mechanism:** The per-game-per-account weekly limit requires server-side state or GitHub-side enforcement. How this state is maintained without a full database is unresolved. Options: store a `confirmed_by_accounts` set in the entry JSON (readable by the proxy before accepting a write), or use GitHub App rate limiting per installation. Needs concrete design before Phase 4.

- **Collective memory repo naming and ownership:** Research assumes `cellar-community/memory` but the actual GitHub org, repo name, and who administers the GitHub App are unresolved. Needs a decision before any auth code is written — the app ID and installation ID are baked into the CLI config format.

- **Opt-in UX for collective memory contribution:** FEATURES.md specifies opt-in with a first-run prompt ("Contribute working configs to the community? Y/n"). The exact flow — where in the setup sequence, what the default is, how to toggle later in web settings — is unspecified. Needs UX decisions before Phase 4 implementation.

---

## Sources

### Primary (HIGH confidence)

- [GitHub Docs — Creating or updating file contents](https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents) — Contents API PUT endpoint, SHA requirement for updates
- [GitHub Docs — Generating a JWT for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app) — RS256 requirement, claims format, 10-minute expiry
- [GitHub Docs — Generating an installation access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app) — 1-hour token expiry (explicit statement)
- [GitHub Docs — Best practices for creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/best-practices-for-creating-a-github-app) — "never ship private key with native clients"; public vs confidential client distinction
- [GitHub Docs — Rate limits for the REST API](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) — authenticated vs unauthenticated limits
- [Apple Developer Forums — Generate JWT token using RS256](https://developer.apple.com/forums/thread/702003) — SecKeyCreateSignature with rsaSignatureMessagePKCS1v15SHA256 confirmed
- [Apple Security framework: SecKeyCreateSignature](https://developer.apple.com/documentation/security/seckeycreatesignature(_:_:_:_:)) — RS256 signing without CryptoKit
- [vapor/jwt-kit GitHub](https://github.com/vapor/jwt-kit) — v5.0.0, Swift 6, RSA in Insecure namespace
- [JWTKit v5 migration blog — Vapor](https://blog.vapor.codes/posts/jwtkit-v5/) — RSA moved to Insecure namespace by design
- [GitHub issue: push_repo_memory.cjs has no retry/backoff](https://github.com/github/gh-aw/issues/19476) — concurrent push data loss confirmed in real agent workflows
- [OWASP Agentic AI: Agent Knowledge Poisoning](https://github.com/precize/OWASP-Agentic-AI/blob/main/agent-knowledge-poisoning-10.md) — knowledge base poisoning taxonomy and mitigations
- Direct codebase inspection: `AIService.swift`, `AgentLoop.swift`, `AgentTools.swift`, `SuccessDatabase.swift`, `CellarPaths.swift`, `CellarConfig.swift`, `WebApp.swift`, `Package.swift` (2026-03-29)

### Secondary (MEDIUM confidence)

- [WineHQ AppDB FAQ + Rating Definitions](https://wiki.winehq.org/AppDB_FAQ) — human-gated submission model and its staleness consequences
- [DebugBase MCP server](https://github.com/DebugBase/mcp-server) — agent-first shared error/fix knowledge base design
- [Kaspersky: GitVenom campaign](https://www.kaspersky.com/blog/malicious-code-in-github/53085/) — GitHub repo-based malware distribution confirms threat model is real
- [The Register: AI companies leaking API keys to GitHub](https://www.theregister.com/2025/11/10/ai_companies_private_api_keys_github/) — widespread key leakage in production projects; 65% of Forbes AI 50 had leaked secrets
- [Resultsense — Multi-Agent Memory as Computer Architecture](https://www.resultsense.com/insights/2026-03-19-multi-agent-memory-computer-architecture-perspective) — collective memory architecture patterns
- [DEV Community — Each AI Agent Gets Its Own GitHub Identity](https://dev.to/agent_paaru/each-ai-agent-gets-its-own-github-identity-how-we-gave-every-bot-its-own-bot-commit-signature-1197) — GitHub App for bot commits pattern
- [Letta: Git-backed memory for coding agents](https://www.letta.com/blog/context-repositories) — Git as agent memory backing store
- [ProtonDB](https://www.protondb.com/) — community compatibility report model; hardware + notes schema (observed from site structure)
- [Sophia Bits — Avoid JSON file merge conflicts](https://sophiabits.com/blog/avoid-json-file-merge-conflicts) — one-file-per-entity conflict avoidance pattern

### Tertiary (LOW confidence)

- None identified — all findings have at least MEDIUM-confidence corroboration from multiple sources.

---

*Research completed: 2026-03-29*
*Ready for roadmap: yes*

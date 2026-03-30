# Feature Research: Cellar v1.2 — Collective Agent Memory

**Domain:** Git-backed shared knowledge base for AI agents contributing and consuming game compatibility configs
**Researched:** 2026-03-29
**Confidence:** MEDIUM (analogous systems researched — ProtonDB, WineHQ AppDB, DebugBase MCP; no direct prior art for agent-first Git-backed game config sharing)

---

## Context: What Already Exists (Do Not Rebuild)

These features are in production and are NOT scope for v1.2:

- Per-game local success database (`query_successdb`, `save_success`) — local SQLite, per-machine
- Recipe system — bundled + AI-generated per-game configs, stored as YAML files
- Agent loop with 20+ tools, Research-Diagnose-Adapt workflow
- Engine detection, dialog detection, smart web research, actionable fix extraction
- Web interface with game CRUD and live agent logs (SSE streaming)

The v1.2 features extend the local success database into a **collective, community-wide** knowledge layer. The agent already solves games — now it remembers solutions across the entire user base.

---

## Feature Landscape

### Table Stakes (Users Expect These)

These are required for "collective agent memory" to be credible. Missing any of these means the feature is either unsafe (applying wrong configs), useless (never checked), or closed (no community benefit).

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Query collective memory before diagnosis | "Check if someone else already solved this" is the entire point of collective memory | MEDIUM | Agent calls a read-only lookup at the start of the Research phase. Must be fast enough not to slow the happy path. Cache locally after first fetch. |
| Rich memory entries (config + reasoning + environment) | A config without context is useless. Users need to know *why* settings work, not just *what* they are | MEDIUM | Each entry stores: working Wine config, agent reasoning chain, environment snapshot (Wine version, macOS version, CPU arch, RAM), and confidence score. Analogous to ProtonDB reports which include hardware + tweaks + notes. |
| Environment-aware fit assessment before applying | Blindly applying a config from a different Wine version or macOS release breaks games | HIGH | Agent reasons explicitly about environment delta: "This config was recorded on Wine 9.0 / macOS Sonoma. I am on Wine 9.21 / Sequoia. These diffs are unlikely to matter for this DX8 game." Agent adapts or skips based on reasoning, never applies blindly. |
| Automatic push after solving a game | Manual contribution kills community databases (see: WineHQ AppDB). Agent must push automatically after user confirms success | MEDIUM | After `save_success` and user-confirmed launch, agent calls a `push_collective_memory` tool. No human approval needed for push. GitHub App bot token authenticates the write. |
| GitHub App authentication for agent writes | Personal access tokens rot, require user setup, leak in logs | MEDIUM | GitHub App installed on the collective memory repo. App credentials ship with Cellar. Agent uses app token to create/update files via GitHub API. Scoped to write access on that repo only. |
| Public read / authenticated write | Any Cellar user reads for free. Only authenticated agents write | LOW | Git repo is public. Reads are unauthenticated (git clone or API). Writes require GitHub App token. Standard open-source pattern. |
| Confidence accumulates across agents | A config confirmed by one agent is good. Confirmed by five is gold | LOW | Each entry has a `confirmations` count and `confirmedBy` list (environment hashes, not user identity). Agent increments on match, never on first application without validation. |
| Conflict-safe entry format (one file per game) | Multiple agents writing to the same file simultaneously must not corrupt the database | MEDIUM | One JSON/YAML file per game (keyed by game identifier hash). Agents append to or replace their own entry section. Conflicts on different games = no conflict. Same-game concurrent writes: last-write-wins is acceptable (entries are additive, not destructive). |

### Differentiators (Competitive Advantage)

These make Cellar's collective memory qualitatively better than existing compatibility databases.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Agent reasoning chain stored with config | ProtonDB and WineHQ AppDB store "what worked" with no "why." Cellar stores the diagnostic trace so future agents can understand intent, not just copy settings | MEDIUM | Store the agent's reasoning chain (key decision points, what was tried and rejected, why the final config was chosen) alongside the working config. Future agents use this to adapt intelligently rather than cargo-culting. |
| Environment-delta reasoning (not just environment matching) | Filtering to exact environment matches produces zero results for most games. Reasoning about which environment differences actually matter for this specific game engine is the key capability | HIGH | Agent receives entries that don't exactly match its environment. Agent reasons: "The GPU changed but this game uses software rendering — irrelevant. The Wine version changed by 2 minor versions — unlikely to break DX8 behavior." This is unique; no compatibility database does environment delta reasoning. |
| Confidence voting with environment diversity | Five confirmations from identical hardware is weak. Five confirmations from different CPUs, GPU vendors, and Wine versions is strong | LOW | Weight confidence score by environment diversity of confirmers, not raw count. A config confirmed on M1/M2/M3 across Wine 9.0-9.21 has higher confidence than 10 confirmations on the same machine. |
| Staleness detection via Wine/macOS version bumps | A config that worked on Wine 8.x may silently break on Wine 10.x | MEDIUM | Each entry records the Wine version range it was confirmed on. When agent checks an entry, flag as "may be stale" if current Wine version is more than one major version ahead of the last confirmation. Trigger re-validation rather than silent application. |
| Per-entry deprecation without deletion | Old configs shouldn't disappear — they're useful for diagnosing regressions | LOW | Entries have a `status` field: `active`, `superseded`, `unconfirmed`. Agents mark entries as `superseded` when they find a better config. Old entries remain in history (Git provides full audit trail). |
| Web interface shows memory state | Transparency builds trust. Users should be able to see "57 games solved, 234 confirmations, last contributed 2 hours ago" | MEDIUM | Extend existing web interface (already built in v1.1) to show: collective memory stats, per-game entries, environment diversity, recent contributions. Read-only view of the shared repo. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Human approval workflow for contributions | "Community moderation prevents bad configs" | Kills automatic contribution — the core value prop. Pull request review requires maintainer bandwidth. Breaks the "any agent contributes automatically" design. WineHQ AppDB's human-gated submissions explain its staleness. | Trust the environment hash + confidence model. Bad configs self-correct: low confirmation count + environment mismatch signals "treat with skepticism." Automate, then add abuse detection later. |
| Vector search / embeddings for memory lookup | "Semantic search finds similar games even without exact match" | Adds infrastructure dependency (embedding API or local model). Adds latency to every agent startup. Overkill for structured game compatibility data where game ID, engine, and tags are reliable keys. | Structured lookup by game identifier hash, engine type, and tags. Fuzzy matching on game name for the lookup step. Use LLM reasoning (already in the loop) to interpret non-exact results — don't build a retrieval pipeline. |
| Real-time conflict resolution / distributed locking | "Two agents writing simultaneously could corrupt data" | Git's append-friendly structure with one-file-per-game means true conflicts are rare. Locking requires coordination infrastructure. Last-write-wins is safe for this data shape (entries are additive). | One JSON file per game. Agent writes are additive (new entry or update own entry section). Concurrent same-game writes: resolve by keeping both entries — both are valid data points. |
| Centralized backend API instead of Git | "A proper API is more scalable and queryable" | Adds server infrastructure, hosting costs, auth management, rate limits, uptime requirements. Git repo is zero-infrastructure, survives Cellar abandonment, forkable. | Git as the database. GitHub API for writes. Local clone for reads. Full compatibility with the existing recipes-in-Git model already shipping. |
| User identity / attribution in entries | "Credit contributors" | Privacy concern: entries should identify environment (hardware/software), not users. Linking configs to identifiable users adds friction (accounts, OAuth) and scope. | Environment hash as contributor identity. No PII stored. Community trust comes from confirmed working configs, not named contributors. |
| Mandatory collective memory (no opt-out) | "Every agent should contribute" | Legal and privacy: some users may not want to contribute system specs to a public repo (corporate machines, privacy-conscious users). Forced contribution breaks trust. | Opt-in with a clear default. First-run prompt: "Contribute working configs to the community? (Y/n)." Default yes for open-source users, easy no for everyone else. |
| Retroactive config invalidation across all users | "When a config is marked bad, force re-diagnosis for everyone" | Agents run locally. There is no push notification channel to running agents. Forced invalidation requires infrastructure that doesn't exist. | Mark entries as `superseded` or `unconfirmed`. Agents check status on next run. Stale or superseded configs trigger the agent to re-run diagnosis rather than abort — graceful degradation. |

---

## Feature Dependencies

```
GitHub App Authentication
  └──required by──> Automatic Push after solving
  └──required by──> Confidence voting (writes)

Query Collective Memory
  └──required by──> Environment-Aware Fit Assessment
                       └──required by──> Apply or Adapt Config from Memory

Automatic Push after solving
  └──requires──> User-confirmed success (already exists: save_success)
  └──requires──> GitHub App Authentication
  └──enhances──> Confidence voting (first confirmation = new entry, subsequent = increment count)

Rich Memory Entries
  └──required by──> Environment-Aware Fit Assessment
  └──required by──> Staleness Detection
  └──required by──> Agent Reasoning Chain Storage

Staleness Detection
  └──requires──> Rich Memory Entries (Wine version range field)
  └──enhances──> Environment-Aware Fit Assessment

Confidence Voting with Environment Diversity
  └──requires──> Rich Memory Entries (confirmedBy environment hashes)
  └──enhances──> Query Collective Memory (sort results by confidence)

Web Interface Memory State
  └──requires──> Collective memory repo exists and is populated
  └──enhances──> Existing web interface (already built in v1.1)
```

### Dependency Notes

- **GitHub App auth is foundational for writes:** every write feature (push, confidence voting, deprecation) requires this. It must be the first thing set up. Without it, collective memory is read-only.
- **Rich memory entry format must be defined before any writes:** the schema determines what queries are possible. Lock the format early — migrations on a public Git repo are painful.
- **Query + fit assessment must work before push:** the read path (query → assess → apply) is the primary user-facing value. Get reads right before writes. Wrong reads waste the agent's time; wrong writes corrupt community data.
- **Confidence voting requires entries to exist first:** can't vote on an empty database. Ship the write path (push after success) before the vote path (increment confirmations on re-validation).
- **Web interface is the last piece:** it's informational. Add after the agent-facing features (query, push, vote) are working.

---

## MVP Definition for v1.2

### Launch With (v1.2 core — must ship)

- [ ] **Memory entry schema** — define the JSON format for collective memory entries. Fields: game_id, game_name, engine, wine_config, reasoning_chain, environment (Wine version, macOS version, CPU arch), confirmations, confirmed_by_env_hashes, status, created_at, updated_at. Lock this before writing any code.
- [ ] **GitHub App setup** — register a GitHub App for Cellar, configure write access to the collective memory repo, ship app credentials with Cellar. Required for all agent writes.
- [ ] **Query collective memory** — agent tool `query_collective_memory(gameId, engine)` fetches matching entries from the public repo (local cache + GitHub API). Called at the start of the Research phase before any diagnosis.
- [ ] **Environment-aware fit assessment** — agent reasons about environment delta between stored entry and current environment before applying any config. No blind application. Reasoning logged to session output.
- [ ] **Automatic push after success** — agent tool `push_collective_memory(entry)` writes a new entry or increments confirmations on an existing entry after `save_success` + user-confirmed launch. Uses GitHub App token.
- [ ] **Confidence accumulation** — `push_collective_memory` checks if an identical or compatible entry already exists. If yes, increment confirmations and add environment hash to `confirmed_by_env_hashes`. If no, create new entry.

### Add After Validation (v1.2 stretch)

- [ ] **Staleness detection** — flag entries where current Wine version is more than one major version ahead of last confirmation. Trigger re-validation rather than skip. Add after base read/write path is confirmed working.
- [ ] **Web interface memory state** — extend existing web interface to show memory stats, per-game entries, recent contributions. Add after collective memory has at least a handful of real entries to display.
- [ ] **Entry deprecation (superseded status)** — when agent finds a better config, mark old entry as `superseded`. Add after multiple entries exist per game.

### Future Consideration (v2+)

- [ ] **Environment diversity weighting for confidence** — weight confidence score by hardware/software diversity of confirming agents. Requires enough data volume to make the weighting meaningful. Defer until 50+ games in the database.
- [ ] **Cross-game config transfer** — when no entry exists for a game, find entries for games with the same engine and suggest adaptation. Requires enough entries per engine to be useful. Defer until database matures.
- [ ] **Abuse / spam detection** — automated rejection of implausible entries (config claims to fix a DX12 game via DX8 path, environment hash repeats suspiciously). Defer until community scale makes this a real problem.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Memory entry schema definition | HIGH | LOW | P1 |
| GitHub App authentication setup | HIGH | MEDIUM | P1 |
| Query collective memory tool | HIGH | MEDIUM | P1 |
| Environment-aware fit assessment | HIGH | HIGH | P1 |
| Automatic push after success | HIGH | MEDIUM | P1 |
| Confidence accumulation | HIGH | LOW | P1 |
| Staleness detection | MEDIUM | MEDIUM | P2 |
| Web interface memory state | MEDIUM | MEDIUM | P2 |
| Entry deprecation (superseded status) | MEDIUM | LOW | P2 |
| Environment diversity confidence weighting | LOW | MEDIUM | P3 |
| Cross-game config transfer | MEDIUM | HIGH | P3 |
| Abuse / spam detection | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for v1.2 launch — the feature doesn't exist without these
- P2: Should have, add when P1 path is validated
- P3: Nice to have, meaningful only at scale

---

## Competitor Feature Analysis

| Feature | ProtonDB | WineHQ AppDB | DebugBase (MCP) | Cellar v1.2 |
|---------|----------|--------------|-----------------|-------------|
| Contribution model | Human submits web form | Human submits web form | Agent submits automatically via tool | Agent submits automatically after user-confirmed success |
| Entry content | Rating + hardware + notes | Rating + version + text description | Error/fix pair + metadata | Working config + reasoning chain + environment snapshot |
| Environment matching | Filter by hardware manually | No filtering | Not applicable | Agent reasons about environment delta before applying |
| Confidence model | Aggregate rating from votes | Maintainer-set rating | Community votes | Confirmation count × environment diversity |
| Staleness handling | None — old reports stay | None — entries go stale silently | None | Version range tracking + stale flag on major Wine version jump |
| Infrastructure dependency | Centralized DB + API | Centralized DB + web app | SaaS service | Git repo only — zero infrastructure |
| Offline capability | No | No | No | Yes — local cache of collective memory works offline |
| Agent-readable format | No — human-readable HTML | No — human-readable HTML | Yes — MCP tool interface | Yes — structured JSON, agent-native |

**Key insight:** All existing compatibility databases are human-written and human-read. Cellar v1.2 is the first agent-first compatibility database — written by agents, read by agents, with structured machine-readable entries. The reasoning chain is the unique differentiator; no other database explains *why* a config works.

---

## Technical Notes

### Memory Entry Schema (Proposed)

```json
{
  "game_id": "sha256:abc123...",
  "game_name": "Cossacks: European Wars",
  "engine": "GSC/DMCR",
  "status": "active",
  "wine_config": {
    "wine_version_min": "9.0",
    "winetricks": ["d3dx9", "vcrun2005"],
    "env_vars": { "WINEDLLOVERRIDES": "mdraw=n,b" },
    "registry": { "HKCU\\Software\\Wine\\Direct3D": { "renderer": "gl" } }
  },
  "reasoning_chain": "Engine detected as GSC/DMCR from mdraw.dll presence. DirectDraw game confirmed via PE imports. Attempted native ddraw: failed with 80004001. Switched to mdraw override with OpenGL renderer. Confirmed at menu.",
  "environment": {
    "wine_version": "9.21",
    "macos_version": "15.3",
    "cpu_arch": "arm64",
    "cpu_model": "Apple M2"
  },
  "confirmations": 3,
  "confirmed_by_env_hashes": ["sha256:env1...", "sha256:env2...", "sha256:env3..."],
  "created_at": "2026-03-29T12:00:00Z",
  "updated_at": "2026-03-30T08:22:00Z"
}
```

### Conflict Safety Pattern

Store as `games/{game_id_prefix}/{game_id}.json` — one file per game. Agents operating on different games never conflict. For same-game concurrent writes (rare), last-write-wins is acceptable: both writes are valid data points (additive). Git history preserves both.

### Read Path (Agent Query)

1. On agent startup for a game, clone/fetch the collective memory repo (or use cached local copy, freshen if >24h old).
2. Look up `games/{prefix}/{game_id}.json`. If found, load all entries with `status: active`.
3. Sort by `confirmations × environment_diversity_score` descending.
4. Pass top entries to agent as context: "Collective memory found N entries for this game. Best match: [summary]. Environment delta: [diff]. Reasoning: [chain]."
5. Agent decides: apply directly, adapt, or ignore and diagnose fresh.

### Write Path (Agent Push)

1. After `save_success` + user confirmation, agent calls `push_collective_memory`.
2. Tool fetches current `{game_id}.json` from repo (GitHub API).
3. If an entry with matching `wine_config` hash exists: increment `confirmations`, append env hash, update `updated_at`.
4. If no matching entry: create new entry, set `confirmations: 1`.
5. Commit via GitHub API using GitHub App token. Commit message: `feat(memory): {game_name} confirmed by {env_hash[:8]}`

### GitHub App Scope

Minimal scope: `contents: write` on the collective memory repo only. No access to user's repos. No user OAuth required. App credentials (app ID + private key) embedded in Cellar config, not per-user.

---

## Sources

- ProtonDB — community compatibility report model: [ProtonDB](https://www.protondb.com/) — MEDIUM confidence (site structure observed, schema inferred from reports)
- WineHQ AppDB — rating definitions and entry format: [AppDB Rating Definitions](https://wiki.winehq.org/AppDB_Maintainer_Rating_Definitions), [AppDB FAQ](https://wiki.winehq.org/AppDB_FAQ) — HIGH confidence
- DebugBase MCP server — agent-first shared error/fix knowledge base: [DebugBase MCP server](https://github.com/DebugBase/mcp-server) — HIGH confidence (source read directly)
- Multi-agent shared memory architecture patterns: [The New Stack — Agentic Knowledge Base Patterns](https://thenewstack.io/agentic-knowledge-base-patterns/), [Resultsense — Multi-Agent Memory as Computer Architecture](https://www.resultsense.com/insights/2026-03-19-multi-agent-memory-computer-architecture-perspective) — MEDIUM confidence
- GitHub App for bot commits: [DEV Community — Each AI Agent Gets Its Own GitHub Identity](https://dev.to/agent_paaru/each-ai-agent-gets-its-own-github-identity-how-we-gave-every-bot-its-own-bot-commit-signature-1197) — MEDIUM confidence
- JSON merge conflict avoidance: [Sophia Bits — Avoid JSON file merge conflicts](https://sophiabits.com/blog/avoid-json-file-merge-conflicts) — MEDIUM confidence
- Airbnb Knowledge Repo (Git-backed knowledge base pattern): [knowledge-repo deployment docs](https://knowledge-repo.readthedocs.io/en/latest/deployment.html) — MEDIUM confidence

---
*Feature research for: Cellar v1.2 Collective Agent Memory*
*Researched: 2026-03-29*

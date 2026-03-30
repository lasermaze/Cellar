# Pitfalls Research: Cellar v1.2 Collective Agent Memory

**Domain:** Adding Git-backed collective memory, GitHub App authentication, and environment-aware config matching to an existing local-first macOS Swift CLI tool
**Researched:** 2026-03-29
**Confidence:** HIGH for GitHub App auth mechanics (official docs verified); HIGH for git concurrency patterns (confirmed with real-world cases); MEDIUM for AI agent memory poisoning vectors (academic + community sources); MEDIUM for Wine config portability specifics (community sources, architecture well-understood)

---

## Critical Pitfalls

### Pitfall 1: GitHub App Private Key Cannot Be Shipped With the CLI Binary

**What goes wrong:**
The naive approach — bundle the GitHub App private key inside the Cellar binary or distribute it in the repo — grants every user the ability to authenticate as the bot and push arbitrary content to the collective memory repo. Any user who extracts the key can impersonate the Cellar bot, inject malicious configs, or exhaust the app's rate limits on behalf of every other user.

**Why it happens:**
GitHub App authentication for server-side bots requires a PEM private key to sign JWTs. When the bot runs server-side, the key stays on the server. For a CLI tool running on user machines, there is no server — so developers assume they must ship the key. The GitHub docs explicitly classify CLI tools as "public clients" that cannot secure secrets, but this is easy to miss when the GitHub Apps UI presents "private key" as the standard auth method.

**How to avoid:**
Never embed the private key in the binary or repo. The correct architecture for a distributed open-source CLI bot is one of two patterns:

1. **Proxy service (recommended):** Run a thin server-side token proxy (a simple cloud function or small server) that holds the private key and returns short-lived installation access tokens on request. The CLI calls the proxy to get a 1-hour token, then uses that token directly with the GitHub API. The private key never leaves the proxy. This is the standard pattern for open-source bots like Renovate, Probot apps, and semantic-release.

2. **Per-user GitHub App installation (acceptable for small scale):** Each Cellar user installs the app on their own GitHub account and provides their own installation ID + private key in `~/.cellar/config`. This distributes the trust model but adds user setup friction.

The proxy pattern is strongly preferred. The proxy is stateless, cheap to run (a single Cloudflare Worker or Railway instance), and keeps the credential surface to one place.

**Warning signs:**
- The GitHub App private key appears anywhere in the source repo, binary, or distribution package.
- The `~/.cellar/config` format includes a `github_private_key` field that users copy-paste from the GitHub App settings.
- A secret scanning tool (GitHub's own, or `truffleHog`) flags the repo during CI.

**Phase to address:** GitHub App auth phase (first phase). The proxy architecture must be decided before any code is written — it affects what the CLI sends, what the server validates, and how token refresh works.

---

### Pitfall 2: Push Race Condition When Multiple Agents Contribute Simultaneously

**What goes wrong:**
Two Cellar agents running on different machines both solve the same game around the same time. Both do `git pull` → build their memory entry → `git commit` → `git push`. The first push succeeds. The second push fails with `non-fast-forward` because the remote advanced while the second agent was working. The second agent's successful config is silently lost if the push failure is not handled with a retry.

**Why it happens:**
Git push atomicity protects the remote from inconsistency, but it provides no automatic resolution for the losing writer. An agent that finishes a 10-minute diagnosis session and tries to contribute its result has a non-trivial chance of collision as the community grows. Without explicit retry logic (fetch → rebase → push), the error is typically surfaced as a generic `git push` failure, easy to swallow or log-and-ignore.

Real-world confirmation: a documented issue in GitHub's own repo memory implementation (`push_repo_memory.cjs`) explicitly flags missing retry/backoff as a bug that causes data loss in concurrent agent workflows.

**How to avoid:**
Implement the optimistic concurrency loop for all memory writes:
```
1. git fetch origin
2. git rebase origin/main
3. git push origin main
4. If push fails with non-fast-forward: go to 1 (max 3 retries, exponential backoff: 2s, 4s, 8s)
5. If still failing after retries: log warning, store entry locally, schedule background retry
```

Memory entries for different games are independent files — rebases almost never have content conflicts (only fast-forward failures). Structure the memory store so each game gets its own file path (e.g., `configs/<game-id>.json`), which makes auto-merge almost always succeed.

**Warning signs:**
- The contribution code has a single `git push` call with no retry logic.
- Agent contribution logs show "push failed" but the session is marked as complete.
- The collective memory repo has fewer entries than expected given the number of reported successful solves.

**Phase to address:** Git-backed memory store phase (core data layer). Retry logic must be in the initial implementation, not added later.

---

### Pitfall 3: Environment Fields Are Underspecified, Making Config Matching Unreliable

**What goes wrong:**
An agent records a successful config with environment context like `{"wine_version": "9.0", "macos": "14.0"}`. Another agent on a different machine has Wine 9.22 and macOS 15.3. The matching logic naively accepts this record as applicable. But the config uses `wined3d` with a specific GLSL workaround that was broken in Wine 9.1–9.15 and fixed in 9.16. The applying agent runs the config, gets a broken render, and either blames the collective memory or silently fails.

**Why it happens:**
Environment context feels simple (OS version, Wine version) but the actual compatibility surface is much wider: Wine sub-version, Gcenx build flavor (wine-crossover vs wine-stable vs wine-devel), macOS GPU driver version, Metal API version, Rosetta 2 presence, display resolution, and whether the user is on Intel vs Apple Silicon. Developers capture the obvious fields and miss the differentiating ones.

A second failure mode: the environment fields are captured at the wrong time — after `wineboot` or after applying config — instead of reflecting the state under which the config was proven to work.

**How to avoid:**
Define a mandatory environment schema for memory entries that captures all Wine-compatibility-relevant dimensions:

```json
{
  "wine_version": "9.22",
  "wine_flavor": "wine-crossover",    // gcenx tap flavor
  "macos_version": "15.3",
  "arch": "arm64",                     // arm64 or x86_64
  "rosetta": false,                    // is wine running under Rosetta?
  "metal_supported": true,
  "gptk_installed": false,
  "display_scale": 2.0                 // Retina vs non-Retina affects some old games
}
```

Capture environment at solve-time (after user confirms "game reached the menu"), not at session start.

For matching, implement tiered confidence:
- **Exact match** (same wine_flavor + wine major.minor): apply directly.
- **Compatible match** (same flavor, version within ±2 minor): apply with a "verify before trusting" note.
- **Cross-flavor or cross-arch**: surface as a hint with explicit warning, never apply automatically.

**Warning signs:**
- Environment schema in memory entries has fewer than 4 fields.
- Matching logic does string-equal on the full version string (breaks on any patch release increment).
- No `arch` field — Apple Silicon vs Intel is a critical differentiator for Wine behavior.

**Phase to address:** Memory entry schema design phase. Must be defined before first write; schema changes after entries exist are painful.

---

### Pitfall 4: Memory Poisoning via Bogus Contributed Configs

**What goes wrong:**
A malicious user runs a modified Cellar client that writes fabricated memory entries claiming a game works with a config that doesn't actually work — or worse, one that sets registry keys or DLL overrides in ways that silently break Wine bottles. Because the system is designed for automatic agent writes without human approval, these entries enter the collective memory and are served to other agents.

The attack surface for a community-contributed config store is real. GitHub repos hosting "useful tools" have been repeatedly used to distribute malware via scripts, and the GitVenom campaign (2025) used fake GitHub repos with backdoored config files actively for years.

**Why it happens:**
The design goal — "no human approval needed" — removes the friction that would otherwise catch bad contributions. An automated system that cannot distinguish a "good" config from a "bad" one based on its content alone is inherently vulnerable to adversarial inputs.

**How to avoid:**
Two layers of defense:

1. **Structural validation before storage:** Every memory entry must pass a schema validator before being committed. DLL paths must be within `~/.cellar/` or known Wine system paths. Registry keys must start with `HKCU\Software\` (not `HKLM`). Config values for known fields must be within a known-valid range.

2. **Confidence gating before application:** New entries from a single contributor start at confidence 0.1. An agent should only apply a config automatically when confidence ≥ 0.7. Low-confidence entries are surfaced as hints ("Another agent tried this but it's unverified") and require user confirmation before application. Confidence rises only when multiple independent agents confirm the config works on their machines.

Additionally: require GitHub account age or a minimum number of prior successful contributions before accepting writes. The GitHub App can reject pushes from accounts created less than 30 days ago.

**Warning signs:**
- The memory store accepts entries without schema validation.
- New entries from first-time contributors are applied automatically at the same confidence as entries with 10+ confirmations.
- DLL paths or registry keys in stored entries are not validated on read.

**Phase to address:** Confidence and validation phase. Confidence thresholds must be enforced in the agent reasoning layer, not just in the storage layer.

---

### Pitfall 5: Installation Access Tokens Expire After 1 Hour — Unhandled Expiry Causes Silent Auth Failures

**What goes wrong:**
GitHub App installation access tokens expire after exactly 1 hour. A Cellar agent that does a long diagnosis session (which can easily exceed 1 hour for a stubborn game), then tries to push the result, uses an expired token. The GitHub API returns 401 Unauthorized. If the auth module doesn't handle token refresh before push, the contribution is silently dropped and the user sees a generic "could not contribute to collective memory" message with no actionable explanation.

**Why it happens:**
Token expiry of "1 hour" sounds long enough that developers don't think to handle it during normal development. During testing, sessions are short. In production with real users, a game that requires 30+ retries can push the session well past the token lifetime. The 1-hour clock starts at token issuance, not at first use.

GitHub docs are explicit: "The installation access token will expire after 1 hour." Some developers misread older community discussions claiming 8-hour expiry — that applies to user access tokens, not installation tokens.

**How to avoid:**
- Cache the token with its issued-at timestamp.
- Before any GitHub API call, check: `if Date.now() - issuedAt > 55 * 60`: re-fetch a fresh token (55-minute threshold gives a 5-minute safety margin).
- The token proxy (from Pitfall 1) should return both the token and its expiry time; the CLI refreshes proactively.
- Never store the installation token to disk. It is a short-lived credential. Store only the mechanism to obtain a new one (the proxy endpoint).

**Warning signs:**
- Token issuance happens once at session start with no refresh logic.
- Long sessions (>1 hour) fail to contribute configs but short sessions succeed.
- The auth module has no `tokenExpiresAt` tracking field.

**Phase to address:** GitHub App auth phase. Token lifecycle management must be part of the initial auth implementation.

---

### Pitfall 6: Git Repository Clone/Pull On Every Agent Start Blocks Launch Performance

**What goes wrong:**
The collective memory feature requires reading the community config store before starting diagnosis. The obvious implementation: `git clone` the memory repo at session start. On a fresh machine this takes 5–30 seconds depending on repo size and network speed. As the community grows, the repo grows. In 6 months the repo could have thousands of entries. The naive clone blocks the user from doing anything while it runs, or worse, the agent skips the memory lookup on timeout and loses the primary value of the feature.

A subtler version: doing `git pull` on every launch to "stay fresh" adds 1–5 seconds to every game launch even for games the user has already solved.

**Why it happens:**
Developers test with an empty repo (instant clone) or on fast home networks. They don't account for repo growth, slow networks, or the frequency of "already solved" launches where network overhead is pure waste.

**How to avoid:**
- Clone once to `~/.cellar/collective-memory/` on first use, not on every launch.
- Use shallow clone (`--depth=1`) for initial setup to minimize download size.
- Use `git fetch --depth=1` + `git merge --ff-only` for updates, not `git pull`.
- Update frequency: pull at most once per day (cache the last-fetch timestamp in `~/.cellar/config`). Not on every launch.
- On first use, show progress: "Downloading collective memory (first time only)..."
- For the query path: read from the local clone only. Never block a launch on a network fetch.
- If the local clone is absent (fresh install, no network), proceed without collective memory and inform the user once: "Collective memory unavailable offline — solving locally."

**Warning signs:**
- The code calls `git clone` or `git pull` in the critical path of `cellar launch`.
- No timestamp check before fetching — fetches on every invocation.
- The clone is not shallow.
- Unit tests pass because they use a local fixture repo, not a real network clone.

**Phase to address:** Memory query integration phase (when agent reads before diagnosis). Performance must be designed in from the start.

---

### Pitfall 7: Config Schema Breaks Forward Compatibility When Fields Are Added Later

**What goes wrong:**
The memory entry schema starts simple: `{game_id, wine_config, environment, confidence}`. In v1.3, `reasoning_chain` is added. In v1.4, `environment.gptk_installed` is added. Old clients reading new entries fail to parse because they enforce strict schemas. New clients reading old entries can't populate newly-required fields and either reject valid entries or crash.

The problem compounds because the memory repo is community-contributed and long-lived. Once entries are written, they stay. You cannot retroactively add required fields to 500 existing entries.

**Why it happens:**
Schema design feels like a "later problem" during initial implementation. Developers write the parser to match exactly what they currently produce. Community-facing stores that outlive the initial version have different requirements than private databases where you control all writers and can run migrations.

**How to avoid:**
- Design the entry schema with explicit versioning from day one: `{"schema_version": 1, ...}`.
- All fields beyond core identifiers should be optional for readers, with documented defaults.
- New fields added in later versions must have default values that make old entries still valid.
- Readers must ignore unknown fields (don't strict-decode to a closed struct).
- When adding a required field in a new version, include a migration step that backfills existing entries with the default value, and keep schema_version to signal to old clients they may be seeing a newer format.

In Swift: use `Codable` with `@DecodingStrategy(.useDefaultValues)` or manual `init(from decoder:)` that provides defaults for missing keys. Never use strict decoding for community-sourced data.

**Warning signs:**
- The Swift `Codable` struct for memory entries uses required (non-optional) properties for fields that could be absent in older entries.
- No `schema_version` field in the entry format.
- Parser crashes when it encounters an unrecognized key.

**Phase to address:** Memory entry schema design phase. Must be correct before the first community entries are written — retroactive migration is painful.

---

### Pitfall 8: Reasoning Chain Storage Creates Privacy and Size Risks

**What goes wrong:**
The agent's reasoning chain — the full sequence of tool calls, observations, and conclusions — is valuable for debugging and for other agents to understand why a config works. But the reasoning chain can inadvertently contain:
- User's local file paths (`/Users/johndoe/Games/Cossacks/`)
- User's macOS username embedded in `WINEPREFIX` paths
- System-specific Wine log lines that reveal installed software or system state

If these are stored verbatim in the public community repo, users are unknowingly contributing identifying information to a public dataset.

A secondary issue: reasoning chains can be long (several KB per entry). If stored verbatim for thousands of entries, the repo grows large and slows down clones.

**Why it happens:**
The reasoning chain is generated by the AI agent and passed through to storage without a sanitization step. During development, the developer's own machine is the only test case — the privacy issue is invisible.

**How to avoid:**
- Sanitize before storage: replace the user's home directory path with `<home>`, Wine prefix paths with `<wineprefix>`, and macOS username with `<user>` before committing any reasoning chain.
- Store reasoning chains as a summarized form, not raw tool call transcripts. The agent should produce a `diagnosis_summary` (a few sentences describing what was tried and why the winning config worked) rather than the full tool-call log.
- Cap reasoning chain storage at 2KB per entry. If the summary exceeds this, truncate it — the config itself is what matters, the reasoning is supplementary.
- Make reasoning chain storage opt-in: `cellar config set share_reasoning true` (default: false). Only the config and environment fields contribute automatically.

**Warning signs:**
- The storage code writes `agent.messageHistory` or raw tool results directly to the memory entry.
- Test entries in the dev repo contain `/Users/<developer-name>/` paths.
- A single memory entry file exceeds 10KB.

**Phase to address:** Memory entry contribution phase (agent writes). Sanitization must be applied before the first real community push.

---

### Pitfall 9: Confidence Score Inflation via Coordinated False Confirmations

**What goes wrong:**
The confidence model relies on multiple independent agents confirming a config works. An attacker (or a misconfigured bot) can run the same game on the same machine multiple times, each time contributing a "works" confirmation, artificially inflating confidence from 0.1 to 0.9 on a config that has only ever been tested by one user. High-confidence entries get applied automatically to other agents' sessions.

**Why it happens:**
The confidence model assumes contributions come from independent machines. Without deduplication at the identity level (device fingerprint or GitHub account), the same user can vote many times. This is the Sybil attack applied to distributed confidence systems.

**How to avoid:**
- Each contribution must be tied to a stable identity. Options in order of strength:
  1. GitHub account (requires OAuth or App installation per user) — strongest
  2. Device-derived ID (hash of hardware identifiers) — reasonable for anonymous use
  3. IP address — weak, but better than nothing for rate limiting
- Limit one confirmation per (game_id, contributor_identity) per calendar week. The system records which identities have confirmed which games.
- Confidence weight should diminish for rapid consecutive confirmations from the same account: first confirmation = +0.3, second from same account in same week = +0.0 (ignored).
- Show confirmation count alongside confidence in the web interface: "Confidence: 0.85 (12 unique contributors)" is much more informative than just "Confidence: 0.85."

**Warning signs:**
- The confidence calculation has no deduplication — it increments on every received confirmation regardless of source.
- A game with 1 actual user shows confidence > 0.5 after multiple pushes from the same account.
- No `contributors` list or `confirmation_count` field in the memory entry.

**Phase to address:** Confidence and voting phase. Sybil resistance must be designed in before any public launch — retroactive fixes require migrating all existing entries.

---

### Pitfall 10: Local JSON Store and Collective Memory Becoming Inconsistent

**What goes wrong:**
Cellar already has a local success database (`~/.cellar/successdb/`). v1.2 adds collective memory as a separate Git-backed store. Now there are two sources of truth for "has this game been solved?" The agent logic for which store to query first, which to write to, and how to reconcile them is underspecified at design time. Common failure: agent solves a game locally (writes to successdb), then queries collective memory (finds nothing), applies a fresh diagnosis from scratch instead of using the local solution, and overwrites its own successdb entry with a worse config.

**Why it happens:**
The two stores are designed independently by different phases. The integration layer — "which store wins, in what order, with what fallback" — is nobody's explicit responsibility and falls through the cracks.

**How to avoid:**
Define the query priority order explicitly and enforce it in one place (a `MemoryRouter` or similar):

```
1. Collective memory: exact match (same game_id, compatible environment)
   → Apply directly, skip diagnosis
2. Local successdb: exact match
   → Apply directly, skip diagnosis
3. Collective memory: compatible match (same game, slightly different env)
   → Use as starting hypothesis for diagnosis
4. Local successdb: similarity match
   → Use as starting hypothesis
5. No match
   → Full diagnosis from scratch
```

Write order: always write to local successdb first (synchronous, never fails). Write to collective memory second (async, can fail silently without breaking the session). Never let a collective memory write failure prevent the local save.

**Warning signs:**
- Agent code has separate code paths for "query local" vs "query collective" with no unified router.
- A successful solve that's already in successdb triggers a redundant diagnosis because collective memory was checked first and returned no result.
- A collective memory write failure causes the session to end without saving to successdb.

**Phase to address:** Agent query integration phase (when the agent is wired up to read collective memory). The priority router must be the first thing built, before either store is wired in.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Embed GitHub App private key in binary | No proxy server needed | Every user can impersonate the bot; key rotation requires shipping a new binary | Never |
| Single `git push` with no retry | Simpler contribution code | Concurrent contributions silently lost; community grows slower than it should | Never — retry loop is 10 lines |
| `git clone` on every `cellar launch` | Always-fresh data | 5–30 second launch penalty grows as repo grows | Never in the hot path — clone once, update daily |
| Store raw reasoning chain | Preserves full detail | Privacy leakage of paths/usernames; repo bloat; slow clones | Only in a private dev repo, never in community repo |
| Confidence = count of confirmations (no dedup) | Simple counter | One user votes 10 times = confidence 0.9 = config applied to everyone | Never — dedup is essential for community trust |
| Strict Codable decode of memory entries | Compile-time safety | Crashes on any unknown field from newer clients | Never for community data — use lenient decoding |
| Skip environment schema, store only wine_version | Minimal friction | Configs applied across ARM/Intel boundary; wrong Wine flavor; silent failures | Only in single-user private testing, not in community store |

---

## Integration Gotchas

Common mistakes when connecting collective memory to the existing system.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| GitHub App auth in Swift CLI | Generate JWT + installation token directly in CLI using embedded private key | Use a proxy service; CLI requests a short-lived token from the proxy endpoint; private key never leaves the proxy |
| Git operations from Swift | Shell out `git` commands with `Process` and parse stdout | Use libgit2 via a Swift wrapper (e.g., SwiftGit2) for reliable structured output, or shell out with explicit error code checking and structured JSON output flags where available |
| Local successdb + collective memory | Two separate query paths in agent loop | Single `MemoryRouter` with defined priority order; collective memory read failure degrades to local-only, never blocks |
| Memory entry write on solve | Write synchronously before session ends, blocking the "success" message to user | Write asynchronously after user confirmation; show "contributing to collective memory..." as a background status, never block the success message |
| Schema validation on incoming entries | Decode and trust incoming YAML/JSON directly | Validate against JSON Schema before any decode; reject entries with unexpected DLL paths or registry prefixes; log rejections for audit |
| GitHub API rate limits | Unlimited API calls for presence checks and metadata reads | Batch reads: fetch the full game index once, cache it, query locally; never make per-game API calls in the diagnosis hot path |

---

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full repo clone per launch | Launch takes 30+ seconds; hangs on slow network | Clone once to `~/.cellar/collective-memory/`, shallow clone; read from local copy only | At repo size > ~10MB (100+ entries with reasoning chains) |
| Fetching all entries to find one game | Query time grows linearly with repo size | Maintain an `index.json` in the repo root mapping `game_id` → file path; agents query the index, then fetch only the relevant entry file | At 50+ entries |
| Per-push GitHub API call for token validation | Rate limit hit by active contributors | Cache valid tokens for 55 minutes; batch contributions (if multiple games solved in session, push once) | At GitHub App secondary rate limit: 100 concurrent requests |
| Confidence recalculation on every read | CPU spike when loading game list | Pre-compute confidence score in entry, recalculate only on new confirmation | At 500+ entries with frequent reads |
| Fetching collective memory before every agent tool call | Redundant network I/O during diagnosis | Fetch collective memory once at session start, cache in memory for the session duration | Every tool call after first in a session |

---

## Security Mistakes

Domain-specific security issues for collective agent memory and GitHub App auth.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Private key in binary or repo | Any user can impersonate bot; key compromise affects all users permanently until rotation | Proxy architecture: key lives server-side only; rotation is a server-side operation |
| No validation of DLL paths in contributed entries | Malicious entry specifies an absolute DLL path outside Wine system dirs; agent loads attacker-controlled DLL | Validate all DLL paths are relative or within known Wine/Cellar directories; reject absolute paths outside `~/.cellar/` and Wine system DLL paths |
| Raw agent reasoning chain stored in public repo | User home directory, username, file paths contributed to public dataset | Sanitize all path-like strings before storage; replace with `<home>`, `<user>`, `<wineprefix>` tokens |
| No rate limiting on memory contributions | Spammer submits thousands of fake entries, inflating repo size and poisoning results | GitHub App can enforce: max 5 contributions per account per day, min account age 30 days for first contribution |
| Memory entry applied without environment check | Config proven on Intel Mac applied on Apple Silicon; Wine crashes silently | Never apply a memory entry without running environment compatibility check first; enforce `arch` field match as hard requirement |
| Token stored to disk unencrypted | Installation access token in `~/.cellar/config` readable by other processes | Never persist installation tokens to disk; only persist the proxy endpoint URL; re-fetch token each session |

---

## UX Pitfalls

User experience mistakes specific to the collective memory feature.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| "Contributing to collective memory..." appears after every launch, even when offline | Confusing error noise for users without internet | Only show contribution flow when: (a) game was newly solved AND (b) network is reachable AND (c) user has not already contributed this game |
| Confidence score shown as a decimal (0.73) with no context | Users don't know what it means or whether to trust it | Show as "Verified by 8 contributors" or a simple label: "Community-verified / Unverified / Experimental" |
| Collective memory lookup failure blocks the launch | Network outage prevents playing a game the user has already solved locally | Collective memory is never in the critical path; local successdb always wins for games already solved locally |
| Agent applies a high-confidence community config that doesn't work on user's machine | User confused: "but it says it works" | Always tell the user: "Applying community config (verified by 12 users). If the game doesn't start, run `cellar solve <game>` for a custom diagnosis." |
| First-time clone takes 20 seconds with no progress indicator | User thinks the app is hung | Show "Downloading collective memory for the first time..." with a progress indicator; this is a one-time cost |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces specific to v1.2 features.

- [ ] **GitHub App auth:** Token proxy is deployed AND CLI is tested with an expired token (verifying refresh fires before a push attempt, not after a 401 failure).
- [ ] **Git concurrency:** Retry-with-rebase loop is tested by simulating a concurrent push from a second agent (not just unit-tested in isolation).
- [ ] **Environment schema:** `arch` field (arm64/x86_64) and `wine_flavor` (crossover/stable/devel) are captured — not just `wine_version` and `macos_version`.
- [ ] **Config matching:** Tested with an entry from an Intel machine being queried on Apple Silicon — result must be "hint, not automatic application."
- [ ] **Schema versioning:** Memory entries have `schema_version` field AND the reader gracefully handles a `schema_version` it doesn't recognize (skips entry, does not crash).
- [ ] **Sanitization:** Reasoning chain / diagnosis summary is checked for user path patterns (`/Users/`, `WINEPREFIX=`, username-like strings) before commit.
- [ ] **Confidence dedup:** A single GitHub account confirmed to be unable to push the same game_id twice in the same week.
- [ ] **Local/collective priority:** Verified that a game already in local successdb does NOT trigger a full re-diagnosis even when collective memory has no entry for it.
- [ ] **Offline behavior:** Tested with no network connection — `cellar launch` proceeds using local successdb only, with a single non-blocking notice about collective memory being unavailable.
- [ ] **Repo size growth:** Clone time measured with a synthetic 500-entry repo to verify the daily-update-only policy keeps launch performance acceptable.

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Private key leaked in repo | HIGH | Immediately revoke and rotate the GitHub App private key; audit all pushes since leak; consider invalidating all entries contributed post-leak and requiring re-verification |
| Poisoned entry reaches high confidence | MEDIUM | Admin (repo owner) deletes the entry file and force-pushes; downstream agents auto-update on next daily fetch; add the game_id to a blocklist until re-verified |
| Schema breaking change shipped | HIGH | Bump schema_version; write migration script that backfills old entries; ship a reader that handles both schema_version 1 and 2 |
| Collective memory repo corrupted | LOW | Collective memory is supplementary — local successdb is unaffected. Rebuild collective memory from successdb exports of willing users. |
| Installation token not refreshed, push fails | LOW | Contribution is queued locally in `~/.cellar/pending-contributions/`; background process retries on next launch with a fresh token |
| Concurrent push collision (retry exhausted) | LOW | Contribution saved to `~/.cellar/pending-contributions/`; retried on next launch; user is informed: "Will contribute on next launch" |

---

## Pitfall-to-Phase Mapping

How v1.2 roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| GitHub App private key in binary | GitHub App auth phase (Phase 1) | Secret scanning CI check passes; private key is not in binary, repo, or `~/.cellar/config` |
| Push race condition | Git-backed memory store phase (Phase 2) | Concurrent push simulation: second push succeeds via rebase-retry, not drops |
| Environment fields underspecified | Memory entry schema design (Phase 2) | Schema includes `arch`, `wine_flavor`, `metal_supported`; ARM/Intel mismatch is correctly flagged as incompatible |
| Memory poisoning | Confidence and validation phase (Phase 3) | Structural validator rejects entry with invalid DLL path; new entry starts at confidence < 0.2 |
| Token expiry unhandled | GitHub App auth phase (Phase 1) | Long-session test: token issued at t=0, push at t=65min succeeds via proactive refresh |
| Clone on every launch | Agent query integration phase (Phase 4) | Clone happens once; subsequent launches use local copy; launch time with empty network verified < 1 second overhead |
| Schema forward compatibility | Memory entry schema design (Phase 2) | Reader handles unknown fields without crashing; `schema_version` field present from first entry |
| Reasoning chain privacy | Agent contribution phase (Phase 3) | Automated test: synthesized reasoning chain with `/Users/testuser/` path is sanitized before commit |
| Confidence inflation / Sybil | Confidence and voting phase (Phase 3) | Same account cannot push confirmation for same game_id twice in one week; verified via GitHub App rejection |
| Local/collective inconsistency | Agent query integration phase (Phase 4) | Game already in local successdb: collective memory lookup happens but result does not override local match; no re-diagnosis triggered |

---

## Sources

- [GitHub Docs: Generating an installation access token for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app) — HIGH confidence: 1-hour token expiry is explicitly documented
- [GitHub Docs: Best practices for creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/best-practices-for-creating-a-github-app) — HIGH confidence: "never ship private key with native clients"; public vs confidential client distinction
- [GitHub Docs: Authenticating as a GitHub App installation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation) — HIGH confidence: JWT + installation token flow
- [GitHub Docs: Rate limits for the REST API](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) — HIGH confidence: 1,000 requests/hour for GITHUB_TOKEN; secondary rate limits
- [GitHub issue: push_repo_memory.cjs has no retry/backoff](https://github.com/github/gh-aw/issues/19476) — HIGH confidence: real-world confirmation of concurrent push data loss in agent workflows; retry loop is the fix
- [GitHub Gist: Retry Git push with backoff](https://gist.github.com/jauderho/fac23f45196860a3a7f4413ff139f859) — MEDIUM confidence: standard fetch-rebase-push retry pattern
- [OWASP Agentic AI: Agent Knowledge Poisoning](https://github.com/precize/OWASP-Agentic-AI/blob/main/agent-knowledge-poisoning-10.md) — MEDIUM confidence: taxonomy of knowledge base poisoning vectors; validation + confidence gating as mitigations
- [Kaspersky: Malicious code in fake GitHub repositories (GitVenom)](https://www.kaspersky.com/blog/malicious-code-in-github/53085/) — MEDIUM confidence: real campaign using GitHub repos for malware distribution; confirms the threat model is real
- [The Register: AI companies keep publishing private API keys to GitHub](https://www.theregister.com/2025/11/10/ai_companies_private_api_keys_github/) — MEDIUM confidence: widespread key leakage in real projects; 65% of Forbes AI 50 had leaked secrets
- [RxDB: Downsides of Local First / Offline First](https://rxdb.info/downsides-of-offline-first.html) — MEDIUM confidence: conflict resolution and sync complexity when adding network to local-first apps
- [TechRxiv: Memory in LLM-based Multi-agent Systems](https://www.techrxiv.org/users/1007269/articles/1367390) — MEDIUM confidence: information asymmetry, synchronization challenges, and consistency requirements in multi-agent memory systems
- Cellar project: `.planning/PROJECT.md` — HIGH confidence: project constraints (Swift 6, Gcenx Wine, Apple Silicon target, local JSON successdb already exists)

---
*Pitfalls research for: Cellar v1.2 Collective Agent Memory — adding Git-backed collective memory, GitHub App auth, and environment-aware config matching to an existing local-first macOS Swift CLI*
*Researched: 2026-03-29*

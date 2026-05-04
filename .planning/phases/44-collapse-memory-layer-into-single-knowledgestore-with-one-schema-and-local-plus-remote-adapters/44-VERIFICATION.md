---
phase: 44-collapse-memory-layer-into-single-knowledgestore-with-one-schema-and-local-plus-remote-adapters
verified: 2026-05-03T17:01:00Z
status: passed
score: 11/11 must-haves verified
re_verification: false
---

# Phase 44: Collapse Memory Layer into KnowledgeStore — Verification Report

**Phase Goal:** Unify three parallel memory paths (CollectiveMemoryService, WikiService, WikiIngestService) into one KnowledgeStore protocol with local + remote adapters. Existing services become thin wrappers over the store. Worker generalized: WIKI_PAGE_PATTERN loosened, fenced-section preservation for game pages, auto-index append, new /api/knowledge/write endpoint. PolicyResources owns the only allowlists (winetricks verbs moved in). Restores config-entry context that was dropped from runAgentLoop.
**Verified:** 2026-05-03T17:01:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | KnowledgeStore protocol with fetchContext / write / list exists | VERIFIED | `Sources/cellar/Core/KnowledgeStore.swift` — protocol, KnowledgeStoreContainer enum, NoOpKnowledgeStore |
| 2  | KnowledgeEntry discriminated union (config, gamePage, sessionLog) with full Codable round-trip | VERIFIED | `Sources/cellar/Core/KnowledgeEntry.swift` — custom encode/init(from:), DecodingError on unknown kind |
| 3  | KnowledgeCache TTL + stale-on-failure helper | VERIFIED | `Sources/cellar/Core/KnowledgeCache.swift` — isFresh, read, readStale, write |
| 4  | PolicyResources.shared.winetricksVerbAllowlist loads from winetricks_verbs.json (22 verbs) | VERIFIED | `Sources/cellar/Core/PolicyResources.swift` lines 246-261; JSON file exists at `Sources/cellar/Resources/policy/winetricks_verbs.json` |
| 5  | agentValidWinetricksVerbs literal deleted; all callers read through PolicyResources | VERIFIED | `AgentTools.swift` line 210: `static var agentValidWinetricksVerbs: Set<String> { PolicyResources.shared.winetricksVerbAllowlist }` — no hardcoded Set literal |
| 6  | KnowledgeStoreLocal (cache-only adapter) conforms to KnowledgeStore | VERIFIED | `Sources/cellar/Core/KnowledgeStoreLocal.swift` — struct KnowledgeStoreLocal: KnowledgeStore; uses CellarPaths.knowledgeCacheDir |
| 7  | KnowledgeStoreRemote (network adapter) conforms to KnowledgeStore; reads raw.githubusercontent.com; posts to /api/knowledge/write; sanitizer reads PolicyResources.shared | VERIFIED | `Sources/cellar/Core/KnowledgeStoreRemote.swift` — fetchConfig/fetchGamePage use raw.githubusercontent.com; postToWorker POSTs to `wikiProxyURL.appendingPathComponent("api/knowledge/write")`; sanitizeConfigEntry reads PolicyResources.shared.envAllowlist/.registryAllowlist/.winetricksVerbAllowlist |
| 8  | Worker: loosened WIKI_PAGE_PATTERN, isPathSafe, applyFencedUpdate, appendToIndex, /api/knowledge/write endpoint, allowlist sync comment | VERIFIED | `worker/src/helpers.ts` exports WIKI_PAGE_PATTERN + isPathSafe + applyFencedUpdate; `worker/src/index.ts` lines 543-638 appendToIndex; handleKnowledgeWrite line 860; allowlist comment lines 16-20 |
| 9  | AIService.runAgentLoop uses KnowledgeStoreContainer.shared at startup (NoOp guard) and at all five call sites | VERIFIED | AIService.swift line 674-675: startup guard; lines 789, 866, 879, 938, 1022: fetchContext + three write calls |
| 10 | CollectiveMemoryService, CollectiveMemoryWriteService, WikiService, WikiIngestService are thin wrappers delegating to KnowledgeStoreContainer.shared | VERIFIED | All four files confirmed: public methods delegate to KnowledgeStoreContainer.shared; private helpers retained for helper extraction |
| 11 | Build is green; 231/232 Swift tests pass; 22/22 worker Vitest tests pass | VERIFIED | `swift build`: Build complete; `swift test`: 232 tests, 1 failure (pre-existing CellarConfigTests Kimi model ID — unrelated to phase 44); worker: 22 passed |

**Score:** 11/11 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Core/KnowledgeStore.swift` | KnowledgeStore protocol + KnowledgeStoreContainer + NoOpKnowledgeStore | VERIFIED | 48 lines; protocol KnowledgeStore, enum KnowledgeStoreContainer, struct NoOpKnowledgeStore (internal visibility for startup guard) |
| `Sources/cellar/Core/KnowledgeEntry.swift` | Discriminated union with Codable, KnowledgeListFilter, KnowledgeEntryMeta | VERIFIED | 167 lines; all required types present; custom Codable with kind+entry shape; unknown kind throws DecodingError |
| `Sources/cellar/Core/KnowledgeCache.swift` | TTL cache with read/readStale/write/isFresh | VERIFIED | 71 lines; all four methods; defaultTTL=3600; stale files never deleted |
| `Sources/cellar/Resources/policy/winetricks_verbs.json` | Plain JSON array of winetricks verbs | VERIFIED | Exists; 22 verbs decoded from JSON array |
| `Sources/cellar/Core/PolicyResources.swift` | winetricksVerbAllowlist field; loaded via Bundle.module | VERIFIED | Lines 143, 246-261; loaded identically to envAllowlist pattern |
| `Sources/cellar/Core/KnowledgeStoreLocal.swift` | Cache-only adapter; no network | VERIFIED | 223 lines; struct KnowledgeStoreLocal: KnowledgeStore; CellarPaths.knowledgeCacheDir; ttl=.infinity |
| `Sources/cellar/Core/KnowledgeStoreRemote.swift` | Network adapter; PolicyResources sanitizer; /api/knowledge/write POST | VERIFIED | 495 lines; HTTPClient protocol + URLSession extension; sanitizeConfigEntry reads PolicyResources.shared; postToWorker POSTs to /api/knowledge/write |
| `Sources/cellar/Persistence/CellarPaths.swift` | knowledgeCacheDir helper | VERIFIED | Line 160: `static var knowledgeCacheDir: URL` |
| `Sources/cellar/Core/AIService.swift` | KnowledgeStoreContainer.shared wired at startup + 5 call sites | VERIFIED | 13 total KnowledgeStoreContainer.shared references; startup guard at line 674; fetchContext at 789; write calls at 866, 879, 938, 1022 |
| `Sources/cellar/Core/CollectiveMemoryService.swift` | Thin wrapper | VERIFIED | Public fetchBestEntry delegates to KnowledgeStoreContainer.shared.fetchContext |
| `Sources/cellar/Core/CollectiveMemoryWriteService.swift` | Thin wrapper | VERIFIED | push() delegates to KnowledgeStoreContainer.shared.write(.config) |
| `Sources/cellar/Core/WikiService.swift` | Thin wrapper | VERIFIED | fetchContext, search, ingest, postSessionLog, postFailureSessionLog all delegate to KnowledgeStoreContainer.shared |
| `Sources/cellar/Core/WikiIngestService.swift` | Thin wrapper | VERIFIED | ingest() writes via KnowledgeStoreContainer.shared.write(.gamePage) at line 61 |
| `Sources/cellar/Core/Tools/ResearchTools.swift` | queryWiki routes through KnowledgeStoreContainer.shared | VERIFIED | Lines 251-261: list + fetchContext via KnowledgeStoreContainer.shared |
| `worker/src/index.ts` | handleKnowledgeWrite + legacy endpoints | VERIFIED | handleKnowledgeWrite at line 860; /api/contribute and /api/wiki/append remain at lines 936, 940 |
| `worker/src/helpers.ts` | isPathSafe + applyFencedUpdate + WIKI_PAGE_PATTERN | VERIFIED | 56 lines; all three exported |
| `Tests/cellarTests/KnowledgeStoreIntegrationTests.swift` | Integration tests with StubKnowledgeStore | VERIFIED | 13 tests covering all wrapper delegation paths |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| AIService.runAgentLoop entry | KnowledgeStoreContainer.shared = KnowledgeStoreRemote() | NoOp guard at startup | WIRED | Line 674-675: `if KnowledgeStoreContainer.shared is NoOpKnowledgeStore { KnowledgeStoreContainer.shared = KnowledgeStoreRemote() }` |
| AIService.runAgentLoop line ~789 | KnowledgeStoreContainer.shared.fetchContext | Replaces WikiService.fetchContext | WIRED | Confirmed present; restores config-entry context capability |
| AIService success path | KnowledgeStoreContainer.shared.write(.gamePage + .sessionLog + .config) | Three write calls replacing WikiService.ingest + postSessionLog + CollectiveMemoryWriteService.push | WIRED | Lines 866, 879, 1022 |
| AIService failure path | KnowledgeStoreContainer.shared.write(.sessionLog) | Replaces WikiService.postFailureSessionLog | WIRED | Line 938 |
| KnowledgeStoreRemote.sanitize | PolicyResources.shared.envAllowlist + registryAllowlist + winetricksVerbAllowlist | Direct read at call time | WIRED | Lines 275, 300, 317 in KnowledgeStoreRemote.swift |
| KnowledgeStoreRemote.write | wikiProxyURL/api/knowledge/write | POST with correct kind discriminant | WIRED | postToWorker builds WorkerWriteEnvelope with kind string |
| KnowledgeStoreRemote.fetchContext | raw.githubusercontent.com/{repo}/main/... | URLSession via HTTPClient protocol | WIRED | fetchConfig (raw URL line 135), fetchGamePage (line 170) |
| worker/src/index.ts writeWikiPage games/ branch | applyFencedUpdate | Called when overwrite=true AND path starts with games/ | WIRED | Line 622: `updated = applyFencedUpdate(existing, entry)` inside games/ branch |
| worker handleWikiAppend | isPathSafe | Replaces old WIKI_PAGE_PATTERN inline check | WIRED | Line 490 comment: "WIKI_PAGE_PATTERN is imported from ./helpers.ts" |
| worker appendToIndex | writeWikiPageRaw | After every successful wiki write | WIRED | Line 638: `await appendToIndex(page, updated, token, repo)` |

---

### Requirements Coverage

The requirement IDs (KS-FOUNDATION, KS-POLICY-WINETRICKS, WORKER-WIKI-PATTERN, WORKER-FENCED-GAMES, WORKER-INDEX-APPEND, WORKER-KNOWLEDGE-WRITE, KS-LOCAL-ADAPTER, KS-REMOTE-ADAPTER, KS-WIRE-AISERVICE, KS-WIRE-AGENT-TOOLS, KS-LEGACY-WRAPPERS) are phase-internal identifiers defined only in the plan frontmatter. They do not appear in `.planning/REQUIREMENTS.md` (which tracks v1.0–v1.3 product requirements with different IDs). All 11 phase-internal requirements are satisfied by artifacts verified above.

| Requirement | Source Plan | Status | Evidence |
|-------------|------------|--------|----------|
| KS-FOUNDATION | 44-01 | SATISFIED | KnowledgeStore.swift, KnowledgeEntry.swift, KnowledgeCache.swift all exist and compile |
| KS-POLICY-WINETRICKS | 44-01 | SATISFIED | winetricks_verbs.json + PolicyResources.shared.winetricksVerbAllowlist; literal deleted from AgentTools |
| WORKER-WIKI-PATTERN | 44-02 | SATISFIED | helpers.ts exports generalized WIKI_PAGE_PATTERN + isPathSafe |
| WORKER-FENCED-GAMES | 44-02 | SATISFIED | applyFencedUpdate in helpers.ts; called in writeWikiPage for games/ paths |
| WORKER-INDEX-APPEND | 44-02 | SATISFIED | appendToIndex function present; called after every writeWikiPage |
| WORKER-KNOWLEDGE-WRITE | 44-02 | SATISFIED | handleKnowledgeWrite at line 860; dispatches on kind; legacy endpoints untouched |
| KS-LOCAL-ADAPTER | 44-03 | SATISFIED | KnowledgeStoreLocal.swift — cache-only, no network, TTL=.infinity |
| KS-REMOTE-ADAPTER | 44-03 | SATISFIED | KnowledgeStoreRemote.swift — GitHub raw reads, Worker writes, PolicyResources sanitizer |
| KS-WIRE-AISERVICE | 44-04 | SATISFIED | 5 call sites rewired; startup guard at runAgentLoop entry |
| KS-WIRE-AGENT-TOOLS | 44-04 | SATISFIED | queryWiki in ResearchTools routes through KnowledgeStoreContainer.shared |
| KS-LEGACY-WRAPPERS | 44-04 | SATISFIED | All four legacy services delegate public methods to KnowledgeStoreContainer.shared |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Sources/cellar/Core/CollectiveMemoryService.swift` | 174 | `AgentTools.allowedEnvKeys` (indirect via computed property) | Info | Not a hardcoded literal — `AgentTools.allowedEnvKeys` is a computed property delegating to `PolicyResources.shared.envAllowlist` (defined in ConfigTools.swift line 11). Functionally correct but one indirection level more than the plan intended. No drift risk. |
| `Sources/cellar/Core/CollectiveMemoryService.swift` | 216 | `AIService.agentValidWinetricksVerbs` (indirect via computed property) | Info | Not a hardcoded literal — `AIService.agentValidWinetricksVerbs` is a computed property delegating to `PolicyResources.shared.winetricksVerbAllowlist` (AgentTools.swift line 210). Same pattern as above. Functionally correct. |
| `Tests/cellarTests/CellarConfigTests.swift` | 69 | Pre-existing test failure: "Kimi default model is moonshot-v1-128k" | Info | UNRELATED to phase 44. Test was failing before this phase. The Kimi fallback model list changed in an earlier phase; the test was written against an outdated expected value. Does not affect phase 44 goal. |

No blocker or warning-level anti-patterns found. The two Info items are indirect reads through delegating computed properties — semantically equivalent to direct `PolicyResources.shared` reads, not inline literals.

---

### Human Verification Required

**1. Fenced-section merge end-to-end**

**Test:** Run `cellar wiki ingest <game>` twice — once fresh, once after manually adding a paragraph outside the AUTO fence markers in the wiki repo.
**Expected:** The second run preserves the agent-authored paragraph verbatim while replacing only the fenced AUTO region.
**Why human:** The Worker merge logic executes in the Cloudflare runtime. The vitest unit tests cover the `applyFencedUpdate` pure function, but end-to-end round-trip (HTTP → GitHub API → fenced merge → commit) requires a real Worker environment.

**2. config-entry context restoration**

**Test:** Start an agent session for a game that has an entry in the cellar-memory repo. Inspect the system prompt context block.
**Expected:** The context block contains BOTH community config data AND wiki game page data in a single "Community config" / "Game page" / "Recent sessions" block — confirming `KnowledgeStoreRemote.fetchContext` returns the merged result and it is injected into the prompt.
**Why human:** fetchContext assembles three concurrent GitHub raw fetches. Verifying the combined output is injected correctly requires a live agent session with a real memory repo.

---

### Gaps Summary

No gaps. All 11 must-haves are verified.

The one pre-existing Swift test failure (`CellarConfigTests` — Kimi model ID) predates phase 44 and is unrelated to the memory layer unification. It does not block phase goal achievement.

---

_Verified: 2026-05-03T17:01:00Z_
_Verifier: Claude (gsd-verifier)_

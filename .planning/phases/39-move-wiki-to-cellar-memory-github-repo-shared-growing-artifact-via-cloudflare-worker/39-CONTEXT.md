# Phase 39: Move Wiki to cellar-memory Repo — Context

**Gathered:** 2026-04-10
**Status:** Ready for planning
**Source:** Discussion of Phase 38 architectural flaws

<domain>
## Phase Boundary

Refactor the wiki storage/sync model. Currently the wiki lives in `Sources/cellar/wiki/` bundled via SPM `.copy("wiki")`. This is fundamentally broken for the Karpathy pattern because:

1. **Bundled wiki is read-only on signed apps** — `Bundle.module` paths inside notarized `.app` bundles can't be written to. `WikiService.ingest` silently fails once installed via Homebrew.
2. **No cross-user sharing** — each user's wiki only grows from their own sessions. Defeats the "compounding knowledge" goal.
3. **Updates require brew upgrade** — users only see new seed pages on release.

Move wiki to the existing `cellar-memory` GitHub repo (alongside collective memory JSONs) and reuse the existing Cloudflare Worker write proxy infrastructure for authenticated wiki page writes.

</domain>

<decisions>
## Implementation Decisions

### Storage Layout
- **Repo:** Reuse existing `lasermaze/cellar-memory` GitHub repo
- **Path:** `wiki/` subdirectory in that repo (alongside existing `entries/` for collective memory JSONs)
- **Structure:** Same as current (SCHEMA.md, index.md, log.md, engines/, symptoms/, environments/)

### Read Path
- **Local cache:** `~/.cellar/wiki/` (writable)
- **Sync source:** GitHub raw URLs (public read, no auth needed)
- **Caching:** Reuse CollectiveMemoryService pattern — 1-hour TTL, stale-on-failure
- **On startup:** WikiService checks cache freshness, fetches from GitHub if stale
- **Fallback:** If cache empty AND GitHub unreachable, return nil gracefully (agent continues without wiki)

### Write Path
- **Via Cloudflare Worker** — reuse existing `worker/` infrastructure
- **New endpoint:** `POST /wiki/append` (or similar) that accepts page path + content to append
- **Auth:** Worker uses GitHub App private key to push (same as existing `/push` endpoint for collective memory)
- **Client:** WikiService.ingest serializes updates and POSTs to Worker
- **Dedup:** Worker-side substring check before committing (move dedup from local to server)

### Removed
- **SPM resource bundle** — remove `.copy("wiki")` from Package.swift
- **Bundle.module reads** — WikiService reads from `~/.cellar/wiki/` instead
- **Initial seed content in repo source** — move `Sources/cellar/wiki/` → `cellar-memory/wiki/` (git mv)

### First-Run Experience
- On first run, cache is empty → sync from GitHub immediately (blocking, ~200ms)
- If offline on first run, wiki unavailable that session, cache populated next run

### Claude's Discretion
- Exact Worker endpoint names and request/response schemas
- Cache invalidation strategy (ETags? Last-modified? Simple TTL?)
- How WikiService handles partial sync failures (some pages fetched, some failed)
- Whether to sync on every launch or lazily on first WikiService call
- Whether to expose a manual sync command (`cellar wiki sync`)
- How log.md conflicts are resolved when multiple users ingest concurrently

</decisions>

<specifics>
## Specific Ideas

- **Parallel to CollectiveMemoryService:** That service already does GitHub raw URL fetching + local cache + stale fallback — WikiService read path should mirror it closely
- **Parallel to CollectiveMemoryWriteService:** That service POSTs to the Worker for authenticated writes — WikiService.ingest write path should mirror it
- **Worker already handles auth:** The GitHub App private key is in Cloudflare secret storage — we just add a new route handler
- **Cellar-memory repo layout becomes:**
  ```
  entries/          # collective memory JSONs per game (existing)
  wiki/             # Karpathy wiki (new)
    SCHEMA.md
    index.md
    log.md
    engines/
    symptoms/
    environments/
  ```
- **Cache layout:**
  ```
  ~/.cellar/
    memory-cache/    # existing collective memory cache
    wiki/            # new wiki cache (mirrors cellar-memory/wiki/ structure)
  ```

</specifics>

<deferred>
## Deferred Ideas

- PR-based wiki writes (for human review before merging)
- Wiki versioning / page history beyond what git provides
- Search index build (BM25/vector) — keyword scoring is fine for now
- Multi-locale wiki pages
- Wiki page validation CI in cellar-memory repo
- Web UI for browsing wiki content (mentioned earlier as separate future phase)

</deferred>

---

*Phase: 39-move-wiki-to-cellar-memory-github-repo-shared-growing-artifact-via-cloudflare-worker*
*Context gathered: 2026-04-10*

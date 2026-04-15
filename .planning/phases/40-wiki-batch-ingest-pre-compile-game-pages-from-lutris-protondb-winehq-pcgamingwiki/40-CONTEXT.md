# Phase 40: Wiki Batch Ingest — Context

**Gathered:** 2026-04-14
**Status:** Ready for planning
**Source:** Discussion of redundant live fetching in agent sessions

<domain>
## Phase Boundary

Build a `cellar wiki ingest` CLI command that pre-compiles per-game wiki pages from 4 existing external sources: Lutris API, ProtonDB API, WineHQ AppDB, and PCGamingWiki. The agent currently spends 3-5 tool calls per session fetching and parsing these sources live. By materializing the results into wiki `games/` pages, the agent gets pre-compiled knowledge instantly via WikiService.fetchContext.

All fetching and parsing code already exists — this phase wires it into a batch pipeline that outputs wiki pages and pushes them via the existing Cloudflare Worker.

</domain>

<decisions>
## Implementation Decisions

### CLI Interface
- New subcommand group: `cellar wiki`
- `cellar wiki ingest "Game Name"` — ingest a single game
- `cellar wiki ingest --popular` — batch ingest top games from Lutris catalog
- `cellar wiki ingest --all-local` — ingest all games in local success database
- Output: creates/updates `wiki/games/{game-slug}.md` in cellar-memory repo

### Data Sources (all existing code)
- **Lutris API** via `CompatibilityService` — env vars, DLL overrides, winetricks verbs, registry edits
- **ProtonDB API** via `CompatibilityService` — tier rating, confidence, report count
- **WineHQ AppDB** via `PageParser.WineHQParser` — test results, community fixes
- **PCGamingWiki** via `PageParser.PCGamingWikiParser` — extracted_fixes (env, DLLs, winetricks, registry, INI)

### Page Format
- One page per game at `wiki/games/{game-slug}.md`
- Sections: Compatibility (ProtonDB), Known Working Config (Lutris), Fixes (WineHQ/PCGW), Engine cross-ref
- `Last updated:` footer with date and source list
- Plain markdown, same format as existing wiki pages per SCHEMA.md

### Write Path
- Push via existing Worker `POST /api/wiki/append` endpoint (Phase 39)
- For new game pages: Worker creates the file (may need a create endpoint, or append to empty file)
- Update `wiki/index.md` with new game entry
- Append to `wiki/log.md`

### Reusable Code
- `CompatibilityService.fetchReport(for:)` — already fetches Lutris + ProtonDB
- `PageParser` (WineHQ + PCGamingWiki parsers) — already extracts structured fixes
- `WikiService.postWikiAppend` — already POSTs to Worker
- `CellarPaths.slugify` — game name to slug conversion

### Claude's Discretion
- How to discover WineHQ/PCGamingWiki URLs for a game (search_web or URL pattern)
- Rate limiting strategy for batch ingest (delay between games)
- How to handle games with no data from any source (skip? create minimal page?)
- Whether to merge new data with existing page or overwrite
- Error handling for individual source failures (partial page vs skip)

</decisions>

<specifics>
## Specific Ideas

- Batch ingest could run as a RemoteTrigger on weekly schedule (like promo skill)
- Post-session auto-ingest: after agent completes, run ingest for that specific game to capture any sources it fetched live
- The `--popular` flag could use Lutris API's game listing sorted by popularity
- Game slug reuse: `CellarPaths.slugify` already exists and is used by SuccessDatabase

</specifics>

<deferred>
## Deferred Ideas

- Scheduled cron ingest via RemoteTrigger (can add after CLI works)
- Post-session automatic ingest (integrate into AIService flow)
- Incremental updates (only fetch sources newer than last ingest)
- Wiki page versioning / diff tracking
- Web UI for browsing ingested game pages

</deferred>

---

*Phase: 40-wiki-batch-ingest-pre-compile-game-pages-from-lutris-protondb-winehq-pcgamingwiki*
*Context gathered: 2026-04-14*

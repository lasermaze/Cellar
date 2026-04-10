# Phase 38: Rebuild Memory Layer — Context

**Gathered:** 2026-04-09
**Status:** Ready for planning
**Source:** Karpathy LLM Wiki gist (https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)

<domain>
## Phase Boundary

Replace the current config-file-based memory system (`~/.cellar/promo.json`, `~/.cellar/` configs) with a shared, LLM-maintained wiki stored in the repo. Agents should be able to read from and contribute to this wiki — building compounding knowledge rather than ephemeral per-run state.

The wiki serves as the persistent knowledge layer between raw sources (F5Bot emails, Reddit threads, game compatibility data) and the agents that act on them.

</domain>

<decisions>
## Implementation Decisions

### Architecture: Three-Layer Pattern (from Karpathy)
- **Raw sources:** Immutable inputs (F5Bot emails, Reddit threads, game data, user configs)
- **The wiki:** LLM-generated markdown files — summaries, entity pages, concept pages, cross-references
- **The schema:** Configuration document defining wiki structure, conventions, and workflows

### Two Special Files
- **index.md** — Content-oriented catalog of all wiki pages with one-line summaries, organized by category
- **log.md** — Append-only chronological record with consistent prefixes (e.g., `## [2026-04-09] ingest | Source Title`) for parseability

### Core Operations
- **Ingest:** New sources processed → LLM reads, writes summaries, updates index and relevant pages, appends to log
- **Query:** Search relevant pages, synthesize answers with citations. Valuable findings can become new wiki pages
- **Lint:** Periodic health checks for contradictions, stale claims, orphan pages, missing cross-references

### Claude's Discretion
- Exact directory structure within repo
- Which existing Cellar data/configs migrate to wiki format
- Page format conventions (frontmatter schema, linking style)
- How agents discover and read wiki pages at runtime
- Integration with existing collective memory system
- Whether wiki lives in main repo or separate repo
- Search/indexing approach (simple grep vs something more)

</decisions>

<specifics>
## Specific Ideas

- Wiki is a git repo — version controlled, diffable, branchable
- LLMs handle the maintenance humans struggle with: updating cross-references, keeping summaries current, noting contradictions
- "LLMs don't get bored, don't forget to update a cross-reference, and can touch 15 files in one pass"
- Pattern relates to Vannevar Bush's 1945 Memex — personal curated knowledge stores
- The wiki is a "persistent, compounding artifact" — knowledge compiled once and kept current rather than re-derived every query
- Accuracy concern: LLM-generated intermediate artifacts can amplify factual errors — keep raw sources as ground truth

</specifics>

<deferred>
## Deferred Ideas

- Advanced search infrastructure (BM25/vector hybrid search, LLM re-ranking)
- Obsidian integration / graph visualization
- Multi-agent concurrent wiki editing with conflict resolution
- Tiered memory density levels (L0/L1/L2)

</deferred>

---

*Phase: 38-rebuild-memory-layer-shared-wiki-for-agents-based-on-karpathy-principles*
*Context gathered: 2026-04-09 via Karpathy gist reference*

# Wiki Schema

Cellar's knowledge base follows the Karpathy LLM Wiki three-layer pattern:
raw sources → wiki pages → schema.

---

## Page Types

### Engine Pages (`engines/`)
One page per graphics/runtime engine. Covers Wine compatibility patterns, known issues,
required DLL overrides, and environment variables. Agents read these when a game's engine
is identified or suspected.

### Symptom Pages (`symptoms/`)
One page per observable failure mode. Covers causes, diagnostic steps, and fixes. Agents
read these when a specific symptom (black screen, crash, D3D error) is detected in logs.

### Environment Pages (`environments/`)
One page per host environment type. Covers platform-specific constraints, recommended
configs, and known regressions. Agents read these when the host environment is known
(e.g., Apple Silicon, Wine Stable 9.x).

### Game Pages (`games/`)
Reserved for per-game knowledge. Created by the ingest operation when a game accumulates
enough unique knowledge to warrant its own page. Not seeded manually — these emerge from
ingest. Per-game working configs remain in the collective memory JSON repo (not here).

---

## Page Format

- Plain markdown, no YAML frontmatter (keeps pages human-writable and grep-friendly)
- Optional `# Title` header at the top
- `Last updated: YYYY-MM-DD` line at the bottom of each page
- Relative links within the wiki: `[DirectDraw](engines/directdraw.md)`
- One concept per page — don't merge engine + symptom into one page
- Bullet lists for actionable configs, shell commands, and registry keys
- Cite sources when possible: "Source: Lutris installer scripts", "Source: ProtonDB reports"

---

## Linking Style

Use relative Markdown links. Always link both the text and the path:
```
[engines/directdraw.md](engines/directdraw.md)
[symptoms/black-screen.md](symptoms/black-screen.md)
```

Cross-references between pages use relative paths. For example, from `symptoms/black-screen.md`:
```
See also: [DirectDraw](../engines/directdraw.md)
```

---

## Operations

### Ingest
1. Read new source (Reddit thread, ProtonDB report, user session observation)
2. Identify which wiki pages are affected (create new pages or update existing)
3. Write summaries into affected pages
4. Update `index.md` if new pages were created
5. Append entry to `log.md` with date, operation type, title, and summary

### Query
1. Read `index.md` to find relevant page paths by keyword scoring
2. Load 2-3 most relevant pages (cap total content at ~4000 chars)
3. Return formatted context block for agent injection

### Lint
1. Check for pages not listed in `index.md` (orphans)
2. Check for pages listed in `index.md` that don't exist (broken links)
3. Flag pages with `Last updated:` dates older than 180 days as potentially stale
4. Surface contradictions (e.g., two pages recommending different DXVK versions)

---

## Scope Boundaries

**Wiki pages are project knowledge**, not user runtime configs.

| Belongs in wiki | Does NOT belong in wiki |
|-----------------|------------------------|
| "DirectDraw games need cnc-ddraw wrapper on Wine 9+" | Per-game working env vars |
| "DXVK 2.x works better for DX11 on Apple Silicon" | User's Wine install path |
| "Unity games crash in Mono runtime on Wine 8-" | Individual successdb entries |
| "Apple Silicon: WoW64 only, no native ARM Wine" | Session event logs |

Runtime configs stay in collective memory (GitHub JSON repo) and successdb.

---

Last updated: 2026-04-06

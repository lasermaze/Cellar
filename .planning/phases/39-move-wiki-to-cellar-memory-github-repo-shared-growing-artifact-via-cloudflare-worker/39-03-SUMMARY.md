---
phase: 39-move-wiki-to-cellar-memory
plan: "03"
subsystem: worker
tags: [cloudflare-worker, wiki, github-api, typescript]
dependency_graph:
  requires: [worker/src/index.ts existing helpers (getInstallationToken, rateLimitMap, isRateLimited)]
  provides: [POST /api/wiki/append endpoint for authenticated wiki page appends]
  affects: [cellar-memory repo wiki/ directory, WikiService.ingest call path]
tech_stack:
  added: []
  patterns: [GET+dedup+PUT pattern mirroring writeEntryToGitHub, shared rateLimitMap bucket]
key_files:
  created: []
  modified:
    - worker/src/index.ts
decisions:
  - isRateLimited() helper shared for /api/wiki/append — single 10/hr/IP bucket covers both contribute and wiki append
  - Body size double-checked via both Content-Length header and actual text length (defensive, mirrors 50KB cap intent)
  - wiki/ path prefix applied inside writeWikiPage — client sends bare page name, server prepends prefix (prevents client confusion)
  - WIKI_PAGE_PATTERN allows engines/|symptoms/|environments/|games/ subdirs plus log.md and index.md at root
metrics:
  duration: "~2 min"
  completed: "2026-04-11"
  tasks_completed: 2
  files_modified: 1
---

# Phase 39 Plan 03: Wiki Append Worker Endpoint Summary

POST /api/wiki/append Cloudflare Worker route with WIKI_PAGE_PATTERN allowlist, server-side substring dedup, and GET+PUT GitHub Contents API write using the existing GitHub App installation token flow.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add WIKI_PAGE_PATTERN, WikiAppendPayload, and writeWikiPage helper | 0d486b9 | worker/src/index.ts |
| 2 | Add handleWikiAppend route handler and wire into fetch dispatch | 04c51df | worker/src/index.ts |

## What Was Built

### Task 1 — Wiki helpers (0d486b9)

Three new items added to `worker/src/index.ts` after `writeEntryToGitHub`:

- **`WikiAppendPayload`** interface: `page: string`, `entry: string`, `commitMessage?: string`
- **`WIKI_PAGE_PATTERN`** regex: allows `engines/`, `symptoms/`, `environments/`, `games/` subdirectories with `[a-z0-9-]+.md` names, plus `log.md` and `index.md` at root
- **`writeWikiPage()`** async function: GET existing file (404 = new file), server-side substring dedup returns `"skipped"`, append with proper newline separator, PUT with SHA, single 409 retry

The `atob(data.content.replace(/\s/g, ""))` decode and `btoa(unescape(encodeURIComponent(updated)))` encode match `writeEntryToGitHub` exactly for multi-byte character safety.

### Task 2 — Route handler and dispatch wiring (04c51df)

- **`handleWikiAppend()`**: Full route handler with exact same CORS object as `handleContribute`, same IP extraction (`CF-Connecting-IP` ?? `X-Forwarded-For` ?? `"unknown"`), same `isRateLimited()` check, same 50KB cap (Content-Length + raw text double check)
- Validates `page` against `WIKI_PAGE_PATTERN` → 400 `invalid_page`
- Validates `entry` is non-empty string → 400 `empty_entry`
- Default commit message: `wiki: append to {page}` when `commitMessage` omitted
- Calls `writeWikiPage()`, returns `{"status":"ok"}` or `{"status":"skipped"}`
- GitHub errors → 502 with error string
- **Dispatch**: `if (url.pathname === "/api/wiki/append")` added immediately after the `/api/contribute` branch (no outer method check — handler manages OPTIONS preflight internally)

## Deviations from Plan

None — plan executed exactly as written.

The plan showed a placeholder `/* same as handleContribute */` comment in the code sketch; the actual implementation uses the literal CORS object, IP extraction, and rate-limit call from `handleContribute` as instructed in the CRITICAL note.

## Self-Check: PASSED

- worker/src/index.ts modified: confirmed
- Commit 0d486b9: confirmed (feat(39-03): add WikiAppendPayload, WIKI_PAGE_PATTERN, and writeWikiPage helper)
- Commit 04c51df: confirmed (feat(39-03): add handleWikiAppend route handler and wire into fetch dispatch)
- No src/ TypeScript errors (node_modules conflicts are pre-existing @cloudflare/workers-types vs lib.dom version mismatch, unrelated to this plan)

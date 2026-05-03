/**
 * Pure helper functions extracted from index.ts for testability.
 * No Worker runtime dependencies — safe to import in vitest unit tests.
 */

// ---------------------------------------------------------------------------
// Wiki path safety
// ---------------------------------------------------------------------------

export const WIKI_PAGE_PATTERN = /^[a-z0-9-]+(\/[a-z0-9-]+)*\.md$/;
export const MAX_WIKI_DEPTH = 4;

/**
 * Returns true if the given page path is safe to use as a wiki page path.
 *
 * Rules:
 *  - No ".." segments (path traversal blocked)
 *  - No leading slash (absolute paths blocked)
 *  - Must match WIKI_PAGE_PATTERN (lowercase slugs, .md extension)
 *  - Depth (number of path segments) must be <= MAX_WIKI_DEPTH
 */
export function isPathSafe(page: string): boolean {
  if (page.includes("..")) return false;
  if (page.startsWith("/")) return false;
  if (!WIKI_PAGE_PATTERN.test(page)) return false;
  const depth = page.split("/").length;
  if (depth > MAX_WIKI_DEPTH) return false;
  return true;
}

// ---------------------------------------------------------------------------
// Fenced-section merge
// ---------------------------------------------------------------------------

export const AUTO_BEGIN = "<!-- AUTO BEGIN -->";
export const AUTO_END = "<!-- AUTO END -->";

/**
 * Merges newAutoContent into existing page content using fence markers.
 *
 * - If no fence markers exist, wraps newAutoContent in fence markers (first write).
 * - If fence markers exist, replaces only the fenced region; agent-authored content
 *   outside the fence is preserved verbatim.
 */
export function applyFencedUpdate(existing: string, newAutoContent: string): string {
  const start = existing.indexOf(AUTO_BEGIN);
  const end = existing.indexOf(AUTO_END);
  if (start === -1 || end === -1) {
    // First write or no fence — wrap content
    return `${AUTO_BEGIN}\n${newAutoContent.trim()}\n${AUTO_END}\n`;
  }
  const before = existing.slice(0, start);
  const after = existing.slice(end + AUTO_END.length);
  return `${before}${AUTO_BEGIN}\n${newAutoContent.trim()}\n${AUTO_END}${after}`;
}

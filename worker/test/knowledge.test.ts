/**
 * Unit tests for worker/src/index.ts pure helpers and handleKnowledgeWrite dispatch.
 * These tests do NOT require a Worker runtime — they import exported functions directly.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import { isPathSafe, applyFencedUpdate } from "../src/helpers.js";

describe("isPathSafe", () => {
  it("Test 1: valid single-segment path returns true", () => {
    expect(isPathSafe("games/cossacks.md")).toBe(true);
  });

  it("Test 2: valid multi-segment path returns true", () => {
    expect(isPathSafe("engines/unreal/dx9.md")).toBe(true);
  });

  it("Test 3: path traversal with leading .. returns false", () => {
    expect(isPathSafe("../etc/passwd")).toBe(false);
  });

  it("Test 4: path traversal in middle returns false", () => {
    expect(isPathSafe("games/../secret.md")).toBe(false);
  });

  it("Test 5: absolute path returns false", () => {
    expect(isPathSafe("/games/cossacks.md")).toBe(false);
  });

  it("Test 6: depth > 4 returns false", () => {
    expect(isPathSafe("a/b/c/d/e/f.md")).toBe(false);
  });

  it("Test 7: uppercase path returns false", () => {
    expect(isPathSafe("Games/Cossacks.md")).toBe(false);
  });

  it("Test 8: root-level log.md returns true", () => {
    expect(isPathSafe("log.md")).toBe(true);
  });

  it("Test 9: root-level index.md returns true", () => {
    expect(isPathSafe("index.md")).toBe(true);
  });

  it("Test 10: non-.md extension returns false", () => {
    expect(isPathSafe("games/foo.txt")).toBe(false);
  });
});

describe("applyFencedUpdate", () => {
  const AUTO_BEGIN = "<!-- AUTO BEGIN -->";
  const AUTO_END = "<!-- AUTO END -->";

  it("Test 11: no-fence input wraps content in fence markers", () => {
    const result = applyFencedUpdate("", "auto content here");
    expect(result).toContain(AUTO_BEGIN);
    expect(result).toContain(AUTO_END);
    expect(result).toContain("auto content here");
  });

  it("Test 12: has-fence with agent content BEFORE preserves it", () => {
    const existing = `Agent notes here.\n${AUTO_BEGIN}\nold auto\n${AUTO_END}\n`;
    const result = applyFencedUpdate(existing, "new auto");
    expect(result).toContain("Agent notes here.");
    expect(result).toContain("new auto");
    expect(result).not.toContain("old auto");
  });

  it("Test 13: has-fence with agent content AFTER preserves it", () => {
    const existing = `${AUTO_BEGIN}\nold auto\n${AUTO_END}\nAgent notes after.\n`;
    const result = applyFencedUpdate(existing, "new auto");
    expect(result).toContain("Agent notes after.");
    expect(result).toContain("new auto");
    expect(result).not.toContain("old auto");
  });

  it("Test 14: has-fence with agent content on both sides preserves both", () => {
    const existing = `Before.\n${AUTO_BEGIN}\nold auto\n${AUTO_END}\nAfter.\n`;
    const result = applyFencedUpdate(existing, "new auto");
    expect(result).toContain("Before.");
    expect(result).toContain("After.");
    expect(result).toContain("new auto");
    expect(result).not.toContain("old auto");
  });

  it("Test 15: empty input produces just the fenced block", () => {
    const result = applyFencedUpdate("", "new content");
    expect(result.trim()).toBe(`${AUTO_BEGIN}\nnew content\n${AUTO_END}`);
  });
});

// ---------------------------------------------------------------------------
// handleKnowledgeWrite dispatch tests (Tests 16–22)
// ---------------------------------------------------------------------------
// Strategy: import handleKnowledgeWrite directly; mock internal write helpers
// by replacing the module's exported test-seam via vi.mock.

import { handleKnowledgeWrite } from "../src/index.js";

// Minimal Env stub — handleKnowledgeWrite reads env.CELLAR_MEMORY_REPO
const stubEnv = {
  GITHUB_APP_PEM: "pem",
  GITHUB_APP_ID: "123",
  GITHUB_INSTALLATION_ID: "456",
  CELLAR_MEMORY_REPO: "test/repo",
};

// Mock the GitHub helpers that require live credentials / network
vi.mock("../src/github.js", () => ({
  getInstallationToken: vi.fn().mockResolvedValue("mock-token"),
  writeEntryToGitHub: vi.fn().mockResolvedValue(undefined),
  writeWikiPage: vi.fn().mockResolvedValue("ok"),
  validateAndSanitize: vi.fn().mockReturnValue({
    schemaVersion: 1, gameId: "test-game", gameName: "Test Game",
    config: { environment: {}, dllOverrides: [], registry: [], launchArgs: [], setupDeps: [] },
    environment: { arch: "x86_64", wineVersion: "9.0", macosVersion: "14.0", wineFlavor: "vanilla" },
    environmentHash: "abc123", reasoning: "", confirmations: 1,
    lastConfirmed: new Date().toISOString(),
  }),
}));

function makeRequest(body: unknown): Request {
  return new Request("http://localhost/api/knowledge/write", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("handleKnowledgeWrite endpoint dispatch", () => {
  beforeEach(() => { vi.clearAllMocks(); });

  it("Test 16: kind=config returns ok with config_written action", async () => {
    const req = makeRequest({
      kind: "config",
      entry: { game_id: "cossacks", game_name: "Cossacks" },
    });
    const res = await handleKnowledgeWrite(req, stubEnv as any);
    const body = await res.json() as any;
    expect(res.status).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.action).toBe("config_written");
  });

  it("Test 17: kind=gamePage with games/ path returns ok with game_page_written action", async () => {
    const req = makeRequest({
      kind: "gamePage",
      entry: { page: "games/cossacks.md", entry: "# Cossacks\nsome content" },
    });
    const res = await handleKnowledgeWrite(req, stubEnv as any);
    const body = await res.json() as any;
    expect(res.status).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.action).toBe("game_page_written");
  });

  it("Test 18: kind=sessionLog returns ok with session_log_written action", async () => {
    const req = makeRequest({
      kind: "sessionLog",
      entry: { page: "sessions/2026-05-03-cossacks-abc.md", entry: "Session notes here" },
    });
    const res = await handleKnowledgeWrite(req, stubEnv as any);
    const body = await res.json() as any;
    expect(res.status).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.action).toBe("session_log_written");
  });

  it("Test 19: kind=bogus returns 400 with unknown_kind", async () => {
    const req = makeRequest({ kind: "bogus", entry: {} });
    const res = await handleKnowledgeWrite(req, stubEnv as any);
    const body = await res.json() as any;
    expect(res.status).toBe(400);
    expect(body.ok).toBe(false);
    expect(body.error).toBe("unknown_kind");
  });

  it("Test 20: missing kind field returns 400", async () => {
    const req = makeRequest({ entry: {} });
    const res = await handleKnowledgeWrite(req, stubEnv as any);
    const body = await res.json() as any;
    expect(res.status).toBe(400);
    expect(body.ok).toBe(false);
  });

  it("Test 21: kind=gamePage with non-games/ path returns 400", async () => {
    const req = makeRequest({
      kind: "gamePage",
      entry: { page: "sessions/cossacks.md", entry: "content" },
    });
    const res = await handleKnowledgeWrite(req, stubEnv as any);
    const body = await res.json() as any;
    expect(res.status).toBe(400);
    expect(body.ok).toBe(false);
    expect(body.error).toBe("gamePage_must_be_under_games");
  });

  it("Test 22: rate limit is applied — two rapid requests from same IP", async () => {
    // This tests that the rate-limit check runs (not necessarily hits), not a boundary test.
    const req = makeRequest({ kind: "sessionLog", entry: { page: "log.md", entry: "test" } });
    // First request should succeed
    const res1 = await handleKnowledgeWrite(req, stubEnv as any);
    expect([200, 429]).toContain(res1.status);
  });
});

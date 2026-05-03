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
// Strategy: import handleKnowledgeWrite directly; mock global fetch so no
// real network calls are made. Tests 19-22 fail before any GitHub calls.
// Tests 16-18 need fetch mocked for JWT + GitHub Contents API calls.

import { handleKnowledgeWrite } from "../src/index.js";

// Minimal Env stub
const stubEnv = {
  GITHUB_APP_PEM: "-----BEGIN PRIVATE KEY-----\nMIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQC7o4qne60TB8+4\n-----END PRIVATE KEY-----",
  GITHUB_APP_ID: "123",
  GITHUB_INSTALLATION_ID: "456",
  CELLAR_MEMORY_REPO: "test/repo",
};

// Mock SubtleCrypto so JWT signing doesn't require a real key
const mockCrypto = {
  subtle: {
    importKey: vi.fn().mockResolvedValue("mock-crypto-key"),
    sign: vi.fn().mockResolvedValue(new ArrayBuffer(8)),
  },
};

// Helper to build a fake successful GitHub fetch response
function githubOkResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

// Mock fetch: installation token → ok; contents GET → 404; contents PUT → ok
function makeFetchMock(getStatus = 404) {
  return vi.fn().mockImplementation(async (url: string, opts?: RequestInit) => {
    const u = typeof url === "string" ? url : (url as Request).url;
    // Installation token endpoint
    if (u.includes("/access_tokens")) {
      return githubOkResponse({ token: "mock-token" });
    }
    // Contents GET (existing file check)
    if ((opts?.method ?? "GET") === "GET" || !opts?.method) {
      if (getStatus === 404) return new Response("not found", { status: 404 });
      const content = btoa(unescape(encodeURIComponent("existing content")));
      return githubOkResponse({ sha: "abc", content });
    }
    // Contents PUT
    if (opts?.method === "PUT") {
      return githubOkResponse({ content: { sha: "def" } });
    }
    return new Response("unexpected", { status: 500 });
  });
}

function makeRequest(body: unknown, ip = "1.2.3.4"): Request {
  return new Request("http://localhost/api/knowledge/write", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "CF-Connecting-IP": ip,
    },
    body: JSON.stringify(body),
  });
}

describe("handleKnowledgeWrite endpoint dispatch", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal("crypto", mockCrypto);
    vi.stubGlobal("fetch", makeFetchMock());
  });

  it("Test 16: kind=config with valid entry returns ok with config_written action", async () => {
    const req = makeRequest({
      kind: "config",
      entry: {
        game_id: "cossacks", game_name: "Cossacks",
        environment_hash: "abc", schema_version: 1,
        config: { environment: {}, dll_overrides: [], registry: [], launch_args: [], setup_deps: [] },
        environment: { arch: "x86_64", wine_version: "9.0", macos_version: "14.0", wine_flavor: "vanilla" },
        confirmations: 1, last_confirmed: new Date().toISOString(), reasoning: "",
      },
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

  it("Test 21: kind=gamePage with non-games/ path returns 400 gamePage_must_be_under_games", async () => {
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

  it("Test 22: rate limit middleware runs — first request not blocked (different IP per test)", async () => {
    // Each test uses unique IP so rate limit bucket is fresh; first request should succeed (not 429)
    const req = makeRequest(
      { kind: "sessionLog", entry: { page: "log.md", entry: "test" } },
      `10.0.0.${Math.floor(Math.random() * 254) + 1}`
    );
    const res = await handleKnowledgeWrite(req, stubEnv as any);
    // Rate limit middleware runs — a fresh IP should not be blocked
    expect(res.status).not.toBe(429);
  });
});

/**
 * Unit tests for worker/src/index.ts pure helpers.
 * These tests do NOT require a Worker runtime — they import helper functions directly.
 */

import { describe, it, expect } from "vitest";
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

import { describe, expect, test } from "vitest";
import { safeMediaUrl } from "./format";

/**
 * Task 0018 step 18 (ASVS 1.2.2): an external video file or embed player
 * reaches a `<source>` or an `<iframe>` only as an absolute `https:` URL
 * without user info.
 */
describe("safeMediaUrl", () => {
  test("returns an https: URL in its parsed form", () => {
    expect(safeMediaUrl("https://cdn.example.org/clips/intro.webm")).toBe(
      "https://cdn.example.org/clips/intro.webm",
    );
    expect(safeMediaUrl("https://Player.Example.org:8443/watch?v=1#t=5")).toBe(
      "https://player.example.org:8443/watch?v=1#t=5",
    );
  });

  test.each([
    ["http:", "http://cdn.example.org/clips/intro.webm"],
    ["javascript:", "javascript:alert(1)"],
    ["upper-case javascript:", "JavaScript:alert(1)"],
    ["data:", "data:video/webm;base64,AAAA"],
    ["blob:", "blob:https://cdn.example.org/1"],
    ["a user name", "https://user@cdn.example.org/clips/intro.webm"],
    ["a user name and password", "https://user:pw@cdn.example.org/a.webm"],
    ["a password only", "https://:pw@cdn.example.org/a.webm"],
    ["a relative path", "/media/clip.webm"],
    ["a scheme-relative URL", "//cdn.example.org/clips/intro.webm"],
    ["an invalid URL", "https://"],
    ["an empty string", ""],
  ])("rejects %s", (_case, url) => {
    expect(safeMediaUrl(url)).toBeNull();
  });

  test("returns null for null and undefined", () => {
    expect(safeMediaUrl(null)).toBeNull();
    expect(safeMediaUrl(undefined)).toBeNull();
  });
});

import { describe, expect, test } from "vitest";
import { graphemeCount, initialsValid } from "./answers";

// Decomposed: each letter followed by U+0301 COMBINING ACUTE ACCENT.
const accented = (letters: string) =>
  [...letters].map((letter) => `${letter}́`).join("");

describe("initials of a checklist drill", () => {
  test("count grapheme clusters, as Elixir's String.length/1 does", () => {
    expect(graphemeCount(accented("ABCDE"))).toBe(5);
    expect([...accented("ABCDE")]).toHaveLength(10);
    expect(graphemeCount("\u{1F1E9}\u{1F1EA}\u{1F1E9}\u{1F1EA}")).toBe(2);
  });

  test("accept 2 to 5 grapheme clusters after trimming", () => {
    expect(initialsValid(accented("ABCDE"))).toBe(true);
    expect(initialsValid(accented("ABCDEF"))).toBe(false);
    expect(initialsValid(accented("A"))).toBe(false);
    expect(initialsValid("  AB  ")).toBe(true);
    expect(initialsValid(" A ")).toBe(false);
    expect(initialsValid("\u{1F1E9}\u{1F1EA}".repeat(3))).toBe(true);
    expect(initialsValid(undefined)).toBe(false);
  });
});

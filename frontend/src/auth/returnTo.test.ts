import { expect, test } from "vitest";
import { safeReturnTo } from "./returnTo";

test("a path on the own origin passes unchanged", () => {
  expect(safeReturnTo("/programs/demo?x=1")).toBe("/programs/demo?x=1");
});

test.each([
  ["a protocol-relative URL", "//evil.example"],
  ["a backslash after the slash", "/\\evil.example"],
  ["an absolute URL", "https://evil.example"],
  ["a javascript: URL", "javascript:alert(1)"],
  ["a tab character", "/\t/evil.example"],
  ["a line break", "/programs\n"],
  ["an empty value", ""],
  ["null", null],
])("%s yields /", (_name, value) => {
  expect(safeReturnTo(value)).toBe("/");
});

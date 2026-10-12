import { describe, expect, test } from "vitest";
import {
  BAR_WIDTHS,
  barWidth,
  formatMonth,
  formatShare,
  largestCount,
  packLang,
} from "./reportFormat";

/**
 * Task 0014 step 9: the helpers of the reports page. A bar takes one of the
 * literal Tailwind width classes in steps of five percent, the bars of a
 * count report scale to the largest visible count of the table, the
 * months of a report render as month and year, and pack text takes the
 * listed locale of the program or else the locale of the report.
 */
describe("barWidth", () => {
  test("lists a width class per step of five percent, from w-0 to w-full", () => {
    expect(BAR_WIDTHS).toHaveLength(21);
    expect(BAR_WIDTHS[0]).toBe("w-0");
    expect(BAR_WIDTHS[20]).toBe("w-full");
    for (let step = 1; step < 20; step++)
      expect(BAR_WIDTHS[step]).toBe(`w-${step}/20`);
  });

  test.each([
    [0, "w-0"],
    [0.02, "w-0"],
    [0.03, "w-1/20"],
    [0.5, "w-10/20"],
    [0.624, "w-12/20"],
    [0.625, "w-13/20"],
    [0.75, "w-15/20"],
    [1, "w-full"],
  ])("picks the nearest step for %s", (fraction, width) => {
    expect(barWidth(fraction)).toBe(width);
  });

  test("clamps a value outside 0 to 1 and treats a non-number as 0", () => {
    expect(barWidth(-0.5)).toBe("w-0");
    expect(barWidth(1.5)).toBe("w-full");
    expect(barWidth(Number.NaN)).toBe("w-0");
    expect(barWidth(Number.POSITIVE_INFINITY)).toBe("w-0");
  });
});

test("largestCount ignores suppressed cells", () => {
  expect(
    largestCount([
      { count: 6, value: 6 },
      { suppressed: true },
      { count: 12, value: 12 },
      { count: 9, value: 9 },
    ]),
  ).toBe(12);
  expect(largestCount([{ suppressed: true }])).toBe(0);
  expect(largestCount([])).toBe(0);
});

test("formatMonth renders the first day of a month as month and year in UTC", () => {
  expect(formatMonth("2026-10-01", "en")).toBe("October 2026");
  expect(formatMonth("2026-01-01", "de")).toBe("Januar 2026");
  expect(formatMonth("not a date", "en")).toBe("not a date");
});

test("formatShare renders a share as a whole percentage", () => {
  expect(formatShare(0.625, "en")).toBe("63%");
  expect(formatShare(1, "en")).toBe("100%");
  expect(formatShare(0, "en")).toBe("0%");
});

describe("packLang", () => {
  test("takes the locale of the list of published programs", () => {
    expect(packLang("en", { locale: "de" })).toBe("en");
  });

  test("falls back to the locale of the report for a program that the list lacks", () => {
    expect(packLang(undefined, { locale: "de" })).toBe("de");
  });
});

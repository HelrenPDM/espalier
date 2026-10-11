import { describe, expect, test } from "vitest";
import de from "../../i18n/de.json";
import en from "../../i18n/en.json";
import {
  AREAS,
  areaKey,
  DEPTHS,
  depthKey,
  STATUSES,
  statusKey,
} from "./labels";

const catalogs = { en, de } as const;

/** The value at the dotted `key` of a translation file, or `undefined`. */
function lookup(catalog: unknown, key: string): unknown {
  return key
    .split(".")
    .reduce<unknown>(
      (node, part) =>
        typeof node === "object" && node !== null
          ? (node as Record<string, unknown>)[part]
          : undefined,
      catalog,
    );
}

/** Every key of the labels of step 11. */
const keys = [
  ...AREAS.map(areaKey),
  ...DEPTHS.map(depthKey),
  ...STATUSES.map(statusKey),
];

describe("objective label lists", () => {
  test("hold exactly the expected values in order", () => {
    expect(AREAS).toEqual(["subject", "method", "self", "social"]);
    expect(DEPTHS).toEqual(["know", "apply", "judge"]);
    expect(STATUSES).toEqual(["evidenced", "practised", "open"]);
  });

  test("map each value to its translation key", () => {
    expect(keys).toEqual([
      "objectives.area.subject",
      "objectives.area.method",
      "objectives.area.self",
      "objectives.area.social",
      "objectives.depth.know",
      "objectives.depth.apply",
      "objectives.depth.judge",
      "objectives.status.evidenced",
      "objectives.status.practised",
      "objectives.status.open",
    ]);
  });
});

describe.each(Object.entries(catalogs))("%s.json", (_language, catalog) => {
  test.each(keys)("holds a non-empty label for %s", (key) => {
    const label = lookup(catalog, key);

    expect(typeof label).toBe("string");
    expect((label as string).trim()).not.toBe("");
  });

  test("holds no other area, depth or status label", () => {
    expect(
      Object.keys(lookup(catalog, "objectives.area") as object).sort(),
    ).toEqual([...AREAS].sort());
    expect(
      Object.keys(lookup(catalog, "objectives.depth") as object).sort(),
    ).toEqual([...DEPTHS].sort());
    expect(
      Object.keys(lookup(catalog, "objectives.status") as object).sort(),
    ).toEqual([...STATUSES].sort());
  });
});

test("the labels match the table of step 11", () => {
  const table: [key: string, en: string, de: string][] = [
    ["objectives.area.subject", "Subject competence", "Fachkompetenz"],
    ["objectives.area.method", "Method competence", "Methodenkompetenz"],
    ["objectives.area.self", "Self competence", "Selbstkompetenz"],
    ["objectives.area.social", "Social competence", "Sozialkompetenz"],
    ["objectives.depth.know", "Know", "Wissen"],
    ["objectives.depth.apply", "Apply", "Anwenden"],
    ["objectives.depth.judge", "Judge", "Beurteilen"],
    ["objectives.status.evidenced", "Evidence shown", "Nachgewiesen"],
    ["objectives.status.practised", "Practised", "Geübt"],
    ["objectives.status.open", "Open", "Offen"],
  ];

  expect(table.map(([key]) => key)).toEqual(keys);
  for (const [key, english, german] of table) {
    expect(lookup(en, key), key).toBe(english);
    expect(lookup(de, key), key).toBe(german);
  }
});

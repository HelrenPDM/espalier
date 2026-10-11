import { expect, test } from "vitest";
import de from "./de.json";
import en from "./en.json";

const keys = (value: object, prefix = ""): string[] =>
  Object.entries(value).flatMap(([key, child]) =>
    typeof child === "object" && child !== null
      ? keys(child, `${prefix}${key}.`)
      : [`${prefix}${key}`],
  );

test("en.json and de.json hold the same keys", () => {
  expect(keys(de).sort()).toEqual(keys(en).sort());
});

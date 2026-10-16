import { expect, test } from "vitest";

// The raw text of every source file, the entry pages of the SPA and of the
// SCORM player, and both tsconfig files. Vite reads them at build time, so
// the test needs no file system access.
const sources = import.meta.glob<string>("/src/**/*.{ts,tsx,css,json}", {
  query: "?raw",
  import: "default",
  eager: true,
});
const pages = import.meta.glob<string>("/{index,scorm}.html", {
  query: "?raw",
  import: "default",
  eager: true,
});
const indexHtml = pages["/index.html"];
const tsconfigs = import.meta.glob<string>("/tsconfig.{app,node}.json", {
  query: "?raw",
  import: "default",
  eager: true,
});

// A plugin element in any letter case, also as a type parameter named
// `Embed` in angle brackets. Built from parts, so that this file holds no
// such element either. Embed types take names such as `EmbedSource`
// (task 0018).
const PLUGIN = new RegExp(
  `<(${["object", "embed", "applet"].join("|")})\\b`,
  "i",
);

test("the plugin pattern finds every letter case and a type parameter", () => {
  const open = (name: string) => `<${name}`;

  for (const text of [
    `${open("object")} data="x">`,
    `${open("OBJECT")}>`,
    `${open("Embed")} src="x">`,
    `useState${open("Embed")}>(null)`,
    `Array${open("Applet")}>`,
    `${open("applet")}`,
  ])
    expect(PLUGIN.test(text), text).toBe(true);
  for (const text of [
    `useState${open("EmbedSource")}>(null)`,
    `${open("EmbedPlayer")} src={src} />`,
    `${open("objects")}>`,
    "an embed player, an object, an applet",
  ])
    expect(PLUGIN.test(text), text).toBe(false);
});

test("no source file, i18n string, type parameter or entry page holds a plugin element (ASVS 3.7.1)", () => {
  const files: Record<string, string> = { ...sources, ...pages };

  expect(Object.keys(sources).length).toBeGreaterThan(20);
  expect(Object.keys(sources)).toEqual(
    expect.arrayContaining(["/src/i18n/en.json", "/src/i18n/de.json"]),
  );
  expect(Object.keys(pages).sort()).toEqual(["/index.html", "/scorm.html"]);
  expect(Object.keys(files).filter((path) => PLUGIN.test(files[path]))).toEqual(
    [],
  );
});

test("index.html loads only the own entry module (ASVS 14.2.3)", () => {
  const scripts = [...indexHtml.matchAll(/<script\b[^>]*>/gi)].map(
    ([tag]) => tag,
  );

  expect(scripts).toEqual(['<script type="module" src="/src/main.tsx">']);
  expect(indexHtml).not.toMatch(/\b(https?:)?\/\/[a-z0-9.-]+\.[a-z]{2,}/i);
});

test("both tsconfig files compile in strict mode (ASVS 15.3.5)", () => {
  expect(Object.keys(tsconfigs).sort()).toEqual([
    "/tsconfig.app.json",
    "/tsconfig.node.json",
  ]);
  for (const text of Object.values(tsconfigs)) {
    expect(text).toMatch(/"strict":\s*true/);
  }
});

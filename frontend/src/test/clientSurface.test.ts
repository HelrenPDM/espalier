import { expect, test } from "vitest";

// The raw text of every source file, index.html and both tsconfig files.
// Vite reads them at build time, so the test needs no file system access.
const sources = import.meta.glob<string>("/src/**/*.{ts,tsx,css,json}", {
  query: "?raw",
  import: "default",
  eager: true,
});
const [indexHtml] = Object.values(
  import.meta.glob<string>("/index.html", {
    query: "?raw",
    import: "default",
    eager: true,
  }),
);
const tsconfigs = import.meta.glob<string>("/tsconfig.{app,node}.json", {
  query: "?raw",
  import: "default",
  eager: true,
});

test("no source file and no index.html holds a plugin element (ASVS 3.7.1)", () => {
  // Built from parts, so that this file holds no such element either.
  const plugin = new RegExp(
    `<(${["object", "embed", "applet"].join("|")})\\b`,
    "i",
  );
  const files: Record<string, string> = {
    ...sources,
    "/index.html": indexHtml,
  };

  expect(Object.keys(sources).length).toBeGreaterThan(20);
  expect(Object.keys(files).filter((path) => plugin.test(files[path]))).toEqual(
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

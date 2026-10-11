import { describe, expect, test } from "vitest";

/**
 * The module boundaries of task 0012 step 15: the player and the learner
 * pages reach the server through `Runtime` only, so the admin preview of
 * 0015 and the SCORM build of 0016 render them without the API client.
 * Vite reads the files at build time, so the test needs no file system
 * access.
 */
const sources = import.meta.glob<string>(
  ["../player/**/*.{ts,tsx}", "../learner/**/*.{ts,tsx}"],
  { query: "?raw", import: "default", eager: true },
);

/** The path of this file, against which the glob keys resolve. */
const HERE = "/src/test/boundaries.test.ts";

/** `/src/…` for a glob key or a relative specifier of `from`. */
const resolvePath = (specifier: string, from: string) =>
  new URL(specifier, `file://${from}`).pathname;

const files: Record<string, string> = Object.fromEntries(
  Object.entries(sources).map(([key, text]) => [resolvePath(key, HERE), text]),
);

interface ImportRecord {
  /** The specifier as written. */
  specifier: string;
  /** `import type …` or `export type … from`; erased under `verbatimModuleSyntax`. */
  typeOnly: boolean;
  kind: "static" | "side-effect" | "dynamic";
}

/**
 * Blanks comments and keeps string and template literals, so that a
 * comment that mentions an import adds none. Newlines stay in place.
 */
function stripComments(source: string): string {
  return source.replace(
    /("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)|\/\*[\s\S]*?\*\/|\/\/[^\n]*/g,
    (match, literal: string | undefined) =>
      literal !== undefined ? match : match.replace(/[^\n]/g, " "),
  );
}

// `import … from "x"` and `export … from "x"`, also across lines. The clause
// holds only names, braces, commas, `*` and `as`, so an expression such as
// `Array.from("x")` matches nothing.
const STATIC =
  /(?<![\w$.])(import|export)(\s+type(?![\w$]))?\s*([\w$\s{},*]*?)\s*(?<![\w$])from\s*(["'])([^"'\n]+)\4/g;
// `import "x"`
const SIDE_EFFECT = /(?<![\w$.])import\s*(["'])([^"'\n]+)\1/g;
// `import("x")`
const DYNAMIC = /(?<![\w$.])import\s*\(\s*(["'])([^"'\n]+)\1\s*[,)]/g;

/** Every import and re-export of `source`. */
function parseImports(source: string): ImportRecord[] {
  const code = stripComments(source);
  const records: { index: number; record: ImportRecord }[] = [];
  for (const match of code.matchAll(STATIC))
    records.push({
      index: match.index,
      record: {
        specifier: match[5],
        typeOnly: match[2] !== undefined,
        kind: "static",
      },
    });
  for (const match of code.matchAll(SIDE_EFFECT))
    records.push({
      index: match.index,
      record: { specifier: match[2], typeOnly: false, kind: "side-effect" },
    });
  for (const match of code.matchAll(DYNAMIC))
    records.push({
      index: match.index,
      record: { specifier: match[2], typeOnly: false, kind: "dynamic" },
    });
  return records.sort((a, b) => a.index - b.index).map(({ record }) => record);
}

/**
 * The module path that `specifier` names from `file`, without query and
 * extension: `/src/api/client` for `../api/client.ts` from a file in
 * `/src/player/`. A bare package name stays as written.
 */
function targetOf(specifier: string, file: string): string {
  const path = specifier.split("?")[0];
  const resolved =
    path.startsWith("./") || path.startsWith("../")
      ? resolvePath(path, file)
      : path;
  return resolved
    .replace(/\.(d\.ts|tsx?|mts|jsx?|mjs)$/, "")
    .replace(/\/index$/, "");
}

const API = "/src/api";
const RUNTIMES = "/src/runtimes";
const CLIENT = `${API}/client`;

const inside = (path: string, directory: string) =>
  path === directory || path.startsWith(`${directory}/`);

/** The learner pages that the SCORM build of 0016 renders. */
const RUNTIME_ONLY_PAGES = [
  "/src/learner/ModuleStation.tsx",
  "/src/learner/CompletionSummary.tsx",
  "/src/learner/ExamSection.tsx",
  "/src/learner/GlossaryPage.tsx",
];

/** The boundary violations of `files` (path to source), one line each. */
function violations(files: Record<string, string>): string[] {
  const found: string[] = [];
  for (const [file, source] of Object.entries(files)) {
    const inPlayer = file.startsWith("/src/player/");
    const runtimeOnly = inPlayer || RUNTIME_ONLY_PAGES.includes(file);
    for (const { specifier, typeOnly } of parseImports(source)) {
      const target = targetOf(specifier, file);
      if (target === CLIENT)
        found.push(`${file}: imports the API client (${specifier})`);
      else if (runtimeOnly && inside(target, API) && !typeOnly)
        found.push(`${file}: imports a value from src/api/ (${specifier})`);
      if (inPlayer && inside(target, RUNTIMES))
        found.push(`${file}: imports from src/runtimes/ (${specifier})`);
    }
  }
  return found;
}

describe("the import parser", () => {
  test("reads a value import, a type import and an inline-type import", () => {
    expect(
      parseImports(
        [
          'import { api } from "../api/client";',
          'import type { components } from "../api/schema";',
          'import { type ItemView, emptyResumeState } from "./runtime";',
          "import Default, * as all from 'module';",
        ].join("\n"),
      ),
    ).toEqual([
      { specifier: "../api/client", typeOnly: false, kind: "static" },
      { specifier: "../api/schema", typeOnly: true, kind: "static" },
      { specifier: "./runtime", typeOnly: false, kind: "static" },
      { specifier: "module", typeOnly: false, kind: "static" },
    ]);
  });

  test("reads a multi-line import", () => {
    expect(
      parseImports(
        'import {\n  usePrograms,\n  type ProgramSummary,\n} from\n  "../api/programs.ts";\n',
      ),
    ).toEqual([
      { specifier: "../api/programs.ts", typeOnly: false, kind: "static" },
    ]);
    expect(
      parseImports('import type {\n  A,\n  B,\n} from "../api/schema";'),
    ).toEqual([{ specifier: "../api/schema", typeOnly: true, kind: "static" }]);
  });

  test("reads re-exports", () => {
    expect(
      parseImports(
        [
          'export { api } from "../api/client";',
          'export * from "../runtimes/platform";',
          'export * as views from "./runtime";',
          'export type { Runtime } from "./runtime";',
          "export const value = 1;",
          "export { value as other };",
        ].join("\n"),
      ),
    ).toEqual([
      { specifier: "../api/client", typeOnly: false, kind: "static" },
      { specifier: "../runtimes/platform", typeOnly: false, kind: "static" },
      { specifier: "./runtime", typeOnly: false, kind: "static" },
      { specifier: "./runtime", typeOnly: true, kind: "static" },
    ]);
  });

  test("reads side-effect and dynamic imports", () => {
    expect(
      parseImports(
        [
          'import "../api/client";',
          "const lazy = () => import('../runtimes/platform');",
          'const other = await import(\n  "../api/programs"\n);',
        ].join("\n"),
      ),
    ).toEqual([
      { specifier: "../api/client", typeOnly: false, kind: "side-effect" },
      { specifier: "../runtimes/platform", typeOnly: false, kind: "dynamic" },
      { specifier: "../api/programs", typeOnly: false, kind: "dynamic" },
    ]);
  });

  test("ignores comments, strings and other uses of from and import", () => {
    expect(
      parseImports(
        [
          '// import { api } from "../api/client";',
          '/* export * from "../api/client"; */',
          '/**\n * import { api } from "../api/client";\n */',
          'const list = Array.from("abc");',
          'const meta = import.meta.glob("./x");',
          'const text = "see https://example.org/a";',
          'import { real } from "./real";',
        ].join("\n"),
      ),
    ).toEqual([{ specifier: "./real", typeOnly: false, kind: "static" }]);
  });

  test("resolves a specifier against the importing file", () => {
    const file = "/src/player/items/ItemFrame.tsx";

    expect(targetOf("../../api/client.ts", file)).toBe("/src/api/client");
    expect(targetOf("../../api/client", file)).toBe("/src/api/client");
    expect(targetOf("../../runtimes/platform.ts", file)).toBe(
      "/src/runtimes/platform",
    );
    expect(targetOf("./parts", file)).toBe("/src/player/items/parts");
    expect(targetOf("../../api/schema.d.ts", file)).toBe("/src/api/schema");
    expect(targetOf("/src/api/client.ts?raw", file)).toBe("/src/api/client");
    expect(targetOf("react-router", file)).toBe("react-router");
  });
});

describe("the boundary rules", () => {
  test("flag the API client, value imports from src/api/ and src/runtimes/ in the player", () => {
    expect(
      violations({
        "/src/player/A.tsx": 'import { api } from "../api/client.ts";',
        "/src/player/B.tsx": 'import { usePrograms } from "../api/programs";',
        "/src/player/C.tsx": 'import { type Handbook } from "../api/programs";',
        "/src/player/D.tsx":
          'import type { PlatformRuntime } from "../runtimes/platform";',
        "/src/player/E.tsx": 'export * from "../api/programs";',
        "/src/player/F.tsx": 'const m = import("../api/programs");',
        "/src/learner/ModuleStation.tsx":
          'import { usePrograms } from "../api/programs";',
        "/src/learner/HandbookPage.tsx":
          'import type { Client } from "../api/client";',
      }),
    ).toEqual([
      "/src/player/A.tsx: imports the API client (../api/client.ts)",
      "/src/player/B.tsx: imports a value from src/api/ (../api/programs)",
      "/src/player/C.tsx: imports a value from src/api/ (../api/programs)",
      "/src/player/D.tsx: imports from src/runtimes/ (../runtimes/platform)",
      "/src/player/E.tsx: imports a value from src/api/ (../api/programs)",
      "/src/player/F.tsx: imports a value from src/api/ (../api/programs)",
      "/src/learner/ModuleStation.tsx: imports a value from src/api/ (../api/programs)",
      "/src/learner/HandbookPage.tsx: imports the API client (../api/client)",
    ]);
  });

  test("allow type imports from src/api/ and value imports of other learner pages", () => {
    expect(
      violations({
        "/src/player/runtime.ts":
          'import type { components } from "../api/schema";',
        "/src/player/items/X.tsx":
          'export type { Handbook } from "../../api/programs";',
        "/src/learner/GlossaryPage.tsx":
          'import type { Glossary } from "../api/programs";',
        "/src/learner/HandbookPage.tsx":
          'import { useHandbook } from "../api/programs";',
        "/src/learner/ProgramRoute.tsx":
          'import { PlatformRuntime } from "../runtimes/platform";',
      }),
    ).toEqual([]);
  });
});

describe("src/player and src/learner", () => {
  const paths = Object.keys(files);

  test("the glob finds the files of both directories", () => {
    expect(paths.filter((path) => path.startsWith("/src/player/"))).not.toEqual(
      [],
    );
    expect(
      paths.filter((path) => path.startsWith("/src/learner/")),
    ).not.toEqual([]);
    expect(paths).toEqual(expect.arrayContaining(RUNTIME_ONLY_PAGES));
    expect(paths).toContain("/src/player/runtime.ts");
  });

  test("the parser reads the imports of the real files", () => {
    expect(parseImports(files["/src/player/runtime.ts"])).toContainEqual({
      specifier: "../api/schema",
      typeOnly: true,
      kind: "static",
    });
    for (const page of RUNTIME_ONLY_PAGES)
      expect(parseImports(files[page]).length, page).toBeGreaterThan(0);
    // Every line that opens an import statement yields a record, so a
    // multi-line import is not lost.
    for (const [path, source] of Object.entries(files)) {
      const opened = source.match(/^import\s*[\w${*"']/gm)?.length ?? 0;
      const read = parseImports(source).filter(
        (record) => record.kind !== "dynamic",
      ).length;
      expect(read, path).toBeGreaterThanOrEqual(opened);
    }
  });

  test("respect the boundaries of the player and the learner pages", () => {
    expect(violations(files)).toEqual([]);
  });
});

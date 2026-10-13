import { describe, expect, test } from "vitest";
import { parse } from "yaml";
import {
  isKey,
  isLayoutPath,
  lessonCount,
  lessonPath,
  lessonTemplate,
  MODULE_FILES,
  moduleDirs,
  moduleFilePath,
  pathLanguage,
  TOP_FILES,
  yamlString,
} from "./paths";

/**
 * Task 0016a, step 13: the mirror of `Espalier.Workbench.Paths` in the SPA.
 * The name lists hold the names of `@top_files` and `@module_files` of
 * `lib/espalier/catalog/pack/loader.ex`, the layout check admits and
 * rejects the paths of the path tests of step 14, and a new lesson starts
 * with front matter that YAML reads back.
 */

describe("the name lists", () => {
  test("hold the names of the loader", () => {
    expect(TOP_FILES).toEqual([
      "pack.yaml",
      "sources.yaml",
      "glossary.yaml",
      "segments.yaml",
      "stations.yaml",
      "feedback.yaml",
      "qualifications.yaml",
      "formats.yaml",
    ]);
    expect(MODULE_FILES).toEqual([
      "module.yaml",
      "objectives.yaml",
      "rules.yaml",
      "items.yaml",
      "assessment.yaml",
    ]);
  });
});

describe("pathLanguage", () => {
  test("names YAML for .yaml and Markdown for .md", () => {
    expect(pathLanguage("pack.yaml")).toBe("yaml");
    expect(pathLanguage("modules/01-a/items.yaml")).toBe("yaml");
    expect(pathLanguage("modules/01-a/lessons/01-b.md")).toBe("markdown");
    expect(pathLanguage("README.txt")).toBeNull();
  });
});

describe("isLayoutPath", () => {
  test("admits every top file, every module file and a lesson", () => {
    for (const name of TOP_FILES) expect(isLayoutPath(name)).toBe(true);
    for (const name of MODULE_FILES)
      expect(isLayoutPath(`modules/01-basics/${name}`)).toBe(true);
    expect(isLayoutPath("modules/01-basics/lessons/02-sources.md")).toBe(true);
  });

  test.each([
    "../pack.yaml",
    "/pack.yaml",
    "C:pack.yaml",
    "modules\\a\\module.yaml",
    "modules/a/../b/module.yaml",
    "modules/./a/module.yaml",
    "modules//a/module.yaml",
    "pack.yaml\u0000",
    "README.md",
    "modules/a/notes.yaml",
    "modules/A/module.yaml",
    "modules/a/lessons/x.txt",
    "modules/a/lessons/x/y.md",
    "modules/a/lessons/-x.md",
    "modules/a/lessons/.md",
    "",
  ])("rejects %j", (path) => {
    expect(isLayoutPath(path)).toBe(false);
  });

  test("rejects a component of more than 255 bytes", () => {
    const dir = "a".repeat(255);
    const key = "k".repeat(252);
    expect(isLayoutPath(`modules/${dir}/lessons/${key}.md`)).toBe(true);
    expect(isLayoutPath(`modules/${dir}a/module.yaml`)).toBe(false);
    expect(isLayoutPath(`modules/${dir}/lessons/${key}k.md`)).toBe(false);
  });
});

describe("the builders", () => {
  test("build module files and lessons", () => {
    expect(moduleFilePath("01-basics", "items.yaml")).toBe(
      "modules/01-basics/items.yaml",
    );
    expect(lessonPath("01-basics", "02-sources")).toBe(
      "modules/01-basics/lessons/02-sources.md",
    );
    expect(isKey("01-basics")).toBe(true);
    expect(isKey("Basics")).toBe(false);
  });

  test("list the module directories and count their lessons", () => {
    const paths = [
      "pack.yaml",
      "modules/02-checking/module.yaml",
      "modules/01-basics/lessons/01-a.md",
      "modules/01-basics/lessons/02-b.md",
      "modules/01-basics/items.yaml",
    ];
    expect(moduleDirs(paths)).toEqual(["01-basics", "02-checking"]);
    expect(lessonCount(paths, "01-basics")).toBe(2);
    expect(lessonCount(paths, "02-checking")).toBe(0);
  });
});

describe("lessonTemplate", () => {
  test("starts a lesson with front matter and one text block", () => {
    expect(lessonTemplate("Second lesson", 2)).toBe(
      [
        "---",
        "title: Second lesson",
        "position: 2",
        "---",
        "",
        ":::text{provenance=invented}",
        "Replace this text with the content of the lesson.",
        ":::",
        "",
      ].join("\n"),
    );
  });

  test.each([
    "Sources: what counts",
    "true",
    "No",
    "42",
    "# heading",
    'Say "hello"',
    "Prüfen, was zählt",
    "trailing ",
  ])("writes the title %j as a YAML string", (title) => {
    const front = lessonTemplate(title, 3).split("---")[1];
    expect(parse(front)).toEqual({ title, position: 3 });
  });

  test("keeps a plain title plain", () => {
    expect(yamlString("Prüfen, was zählt")).toBe("Prüfen, was zählt");
    expect(yamlString("Sources: what counts")).toBe('"Sources: what counts"');
  });
});

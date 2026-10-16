import { describe, expect, test } from "vitest";
import { parse } from "yaml";
import {
  CAPTIONS_TEMPLATE,
  captionsPath,
  isKey,
  isLayoutPath,
  isMediaPath,
  lessonCount,
  lessonPath,
  lessonTemplate,
  MODULE_FILES,
  moduleDirs,
  moduleFilePath,
  pathLanguage,
  TOP_FILES,
  titleSlug,
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

  test("names plain text for a captions file (task 0018)", () => {
    expect(pathLanguage("media/intro-en.vtt")).toBe("text");
    expect(pathLanguage("media/videos/intro/intro-en.vtt")).toBe("text");
    expect(pathLanguage("media/intro.webm")).toBeNull();
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

  test("admits a captions file below media/ with up to three directories (task 0018)", () => {
    expect(isLayoutPath("media/intro-en.vtt")).toBe(true);
    expect(isLayoutPath("media/videos/intro-en.vtt")).toBe(true);
    expect(isLayoutPath("media/a/b/c/intro-en.vtt")).toBe(true);
  });

  test.each([
    "media/a/b/c/d/intro-en.vtt",
    "media/intro-en.VTT",
    "media/Intro.vtt",
    "media/-intro.vtt",
    "media/.vtt",
    "media/videos/../intro.vtt",
    "media/./intro.vtt",
    "media//intro.vtt",
    "media/intro.webm",
    "media/intro.webp",
    "media/intro en.vtt",
    "media/Über.vtt",
    "media",
    "media/",
    "/media/intro.vtt",
  ])("rejects the media path %j as a file", (path) => {
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

describe("isMediaPath", () => {
  test("admits the delivery extension it names only", () => {
    expect(isMediaPath("media/team-photo.webp", "webp")).toBe(true);
    expect(isMediaPath("media/figures/overview.svg", "svg")).toBe(true);
    expect(isMediaPath("media/a/b/c/clip.webm", "webm")).toBe(true);
    expect(isMediaPath("media/team-photo.webp", "svg")).toBe(false);
    expect(isMediaPath("media/team-photo.png", "webp")).toBe(false);
    expect(isMediaPath("media/a/b/c/d/clip.webm", "webm")).toBe(false);
    expect(isMediaPath("modules/a/clip.webm", "webm")).toBe(false);
  });

  test("keeps the limits of 255 bytes per component and 527 in all", () => {
    const key = "k".repeat(250);
    expect(isMediaPath(`media/${key}.webp`, "webp")).toBe(true);
    expect(isMediaPath(`media/${key}kkkkkk.webp`, "webp")).toBe(false);
    const dir = "d".repeat(255);
    expect(isMediaPath(`media/${dir}/${dir}/x.webp`, "webp")).toBe(true);
    expect(isMediaPath(`media/${dir}/${dir}/${dir}/x.webp`, "webp")).toBe(
      false,
    );
  });
});

describe("captions and slugs", () => {
  test("a new captions file is media/<key>.vtt with the header WEBVTT and an empty line", () => {
    expect(captionsPath("intro-en")).toBe("media/intro-en.vtt");
    expect(CAPTIONS_TEMPLATE).toBe("WEBVTT\n\n");
    expect(isLayoutPath(captionsPath("intro-en"))).toBe(true);
  });

  test.each([
    ["Team photo", "team-photo"],
    ["  Release checks (v2)!  ", "release-checks-v2"],
    ["Prüfung für Straße", "prufung-fur-strasse"],
    ["---", "media"],
    ["", "media"],
    ["a".repeat(120), "a".repeat(80)],
  ])("titleSlug(%j) is %j, a key", (title, slug) => {
    expect(titleSlug(title)).toBe(slug);
    expect(isKey(titleSlug(title))).toBe(true);
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

/**
 * The pack layout of the files of a draft (task 0016a, steps 3 and 13), the
 * mirror of `Espalier.Workbench.Paths`: the language of a path and the
 * paths that the dialog "Add file" builds. The server checks every path
 * again and answers 422 `invalid_path` for a path outside the layout.
 */

/** The language of a file of a draft, as `Paths.language/1` returns it. */
export type FileLanguage = "yaml" | "markdown" | "text";

/**
 * The files at the root of a pack. Keep this list in sync with
 * `@top_files` in `lib/espalier/catalog/pack/loader.ex`
 * (`Loader.top_files/0`), which the path rules of the server admit.
 */
export const TOP_FILES = [
  "pack.yaml",
  "sources.yaml",
  "glossary.yaml",
  "segments.yaml",
  "stations.yaml",
  "feedback.yaml",
  "qualifications.yaml",
  "formats.yaml",
] as const;

/**
 * The YAML files of a module directory. Keep this list in sync with
 * `@module_files` in `lib/espalier/catalog/pack/loader.ex`
 * (`Loader.module_files/0`).
 */
export const MODULE_FILES = [
  "module.yaml",
  "objectives.yaml",
  "rules.yaml",
  "items.yaml",
  "assessment.yaml",
] as const;

/** The largest number of bytes of a path (`Paths.max_bytes/0`). */
export const MAX_PATH_BYTES = 527;

/** The largest number of bytes of a component (`Paths.max_component_bytes/0`). */
export const MAX_COMPONENT_BYTES = 255;

/** The key format of module directories and lesson keys (`Cast.key?/1`). */
const KEY = /^[a-z0-9][a-z0-9-]*$/;

/** True for a string in the key format of module directories and lesson keys. */
export const isKey = (value: string): boolean => KEY.test(value);

/**
 * The language of the file at `path`: `yaml` for `.yaml`, `markdown` for
 * `.md`, and `text` for the captions files `.vtt` of task 0018.
 */
export function pathLanguage(path: string): FileLanguage | null {
  if (path.endsWith(".yaml")) return "yaml";
  if (path.endsWith(".md")) return "markdown";
  if (path.endsWith(".vtt")) return "text";
  return null;
}

/** `modules/<dir>/<name>`: a YAML file of a module directory. */
export const moduleFilePath = (dir: string, name: string): string =>
  `modules/${dir}/${name}`;

/** `modules/<dir>/lessons/<key>.md`: a lesson of a module directory. */
export const lessonPath = (dir: string, key: string): string =>
  `modules/${dir}/lessons/${key}.md`;

const isTopFile = (name: string) =>
  (TOP_FILES as readonly string[]).includes(name);

const isModuleFile = (name: string) =>
  (MODULE_FILES as readonly string[]).includes(name);

/** The most directories between `media/` and the file name (`MediaPath`). */
export const MAX_MEDIA_DIRS = 3;

/** The extensions of the delivery files (`MediaPath.delivery_path/1`). */
export type DeliveryExtension = "webp" | "svg" | "webm" | "vtt";

/** The general limits: at most 527 bytes, at most 255 bytes per component. */
function withinLimits(path: string, parts: readonly string[]): boolean {
  return (
    new TextEncoder().encode(path).length <= MAX_PATH_BYTES &&
    parts.every((part) => part.length <= MAX_COMPONENT_BYTES)
  );
}

/**
 * True for `media/` followed by zero to three directories and
 * `<key>.<ext>`, every directory and the key in the key format, at most 255
 * bytes per component and 527 bytes in all: the mirror of
 * `Espalier.Catalog.Pack.MediaPath.check/1` for one extension (task 0018,
 * steps 9 and 16). A media entry of a draft takes the delivery extension of
 * its asset (`webp`, `svg`, `webm`), and a captions file `vtt`.
 */
export function isMediaPath(path: string, ext: DeliveryExtension): boolean {
  const parts = path.split("/");
  if (!withinLimits(path, parts)) return false;
  if (parts.length < 2 || parts.length > MAX_MEDIA_DIRS + 2) return false;
  if (parts[0] !== "media") return false;
  const name = parts[parts.length - 1];
  const suffix = `.${ext}`;
  return (
    parts.slice(1, -1).every(isKey) &&
    name.endsWith(suffix) &&
    isKey(name.slice(0, -suffix.length))
  );
}

/**
 * True for a path of the pack layout, as `Paths.check/1` decides: a name of
 * `TOP_FILES`, `modules/<dir>/<name>` with a name of `MODULE_FILES`,
 * `modules/<dir>/lessons/<key>.md`, or a captions file
 * `media/<dirs>/<key>.vtt` with up to three directories (task 0018), with
 * `<dir>`, the directories and `<key>` in the key format, at most 255 bytes
 * per component and 527 bytes in all. The layout admits ASCII names only,
 * so a path that passes holds no backslash, NUL, drive letter or empty,
 * `.` or `..` component.
 */
export function isLayoutPath(path: string): boolean {
  const parts = path.split("/");
  if (!withinLimits(path, parts)) return false;
  if (parts.length === 1) return isTopFile(parts[0]);
  if (parts[0] === "media") return isMediaPath(path, "vtt");
  if (parts[0] !== "modules" || !isKey(parts[1])) return false;
  if (parts.length === 3) return isModuleFile(parts[2]);
  return (
    parts.length === 4 &&
    parts[2] === "lessons" &&
    parts[3].endsWith(".md") &&
    isKey(parts[3].slice(0, -3))
  );
}

/** The module directories that the paths name, sorted. */
export function moduleDirs(paths: readonly string[]): string[] {
  const dirs = new Set<string>();
  for (const path of paths) {
    const parts = path.split("/");
    if (parts.length >= 3 && parts[0] === "modules") dirs.add(parts[1]);
  }
  return [...dirs].sort();
}

/** The number of lessons of the module directory `dir` among the paths. */
export function lessonCount(paths: readonly string[], dir: string): number {
  const prefix = `modules/${dir}/lessons/`;
  return paths.filter((path) => path.startsWith(prefix)).length;
}

// Plain scalars that YAML reads as another type than a string.
const NON_STRING = /^(true|false|yes|no|on|off|null|~)$/i;
const PLAIN = /^\p{L}[\p{L}\p{N} ,.'()-]*$/u;

/**
 * A title as a YAML scalar: plain where YAML reads it as a string, and in
 * double quotes otherwise. JSON writes a double-quoted string that YAML
 * reads as the same text.
 */
export function yamlString(value: string): string {
  const plain = PLAIN.test(value) && !NON_STRING.test(value);
  return plain && !value.endsWith(" ") ? value : JSON.stringify(value);
}

/**
 * The content of a new lesson: front matter with `title` and `position`
 * and one `text` block, which the author replaces.
 */
export function lessonTemplate(title: string, position: number): string {
  return [
    "---",
    `title: ${yamlString(title)}`,
    `position: ${position}`,
    "---",
    "",
    ":::text{provenance=invented}",
    "Replace this text with the content of the lesson.",
    ":::",
    "",
  ].join("\n");
}

/** `media/<key>.vtt`: a captions file of the draft (task 0018, step 16). */
export const captionsPath = (key: string): string => `media/${key}.vtt`;

/**
 * The content of a new captions file: the header `WEBVTT` and an empty
 * line, after which the author writes the cues.
 */
export const CAPTIONS_TEMPLATE = "WEBVTT\n\n";

/**
 * A title in the key format: lower-case ASCII letters and digits, the
 * words joined by single hyphens, at most 80 characters; `media` when no
 * letter or digit remains. Letters with diacritics lose them, so "Prüfung"
 * becomes `prufung`.
 */
export function titleSlug(title: string): string {
  const slug = title
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/ß/g, "ss")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/, "");
  return slug === "" ? "media" : slug;
}

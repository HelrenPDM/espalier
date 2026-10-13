/**
 * The pack layout of the files of a draft (task 0016a, steps 3 and 13), the
 * mirror of `Espalier.Workbench.Paths`: the language of a path and the
 * paths that the dialog "Add file" builds. The server checks every path
 * again and answers 422 `invalid_path` for a path outside the layout.
 */

/** The language of a file of a draft, as `Paths.language/1` returns it. */
export type FileLanguage = "yaml" | "markdown";

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

/** The language of the file at `path`: `yaml` for `.yaml`, `markdown` for `.md`. */
export function pathLanguage(path: string): FileLanguage | null {
  if (path.endsWith(".yaml")) return "yaml";
  if (path.endsWith(".md")) return "markdown";
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

/**
 * True for a path of the pack layout, as `Paths.check/1` decides: a name of
 * `TOP_FILES`, `modules/<dir>/<name>` with a name of `MODULE_FILES`, or
 * `modules/<dir>/lessons/<key>.md`, with `<dir>` and `<key>` in the key
 * format, at most 255 bytes per component and 527 bytes in all. The layout
 * admits ASCII names only,
 * so a path that passes holds no backslash, NUL, drive letter or empty,
 * `.` or `..` component.
 */
export function isLayoutPath(path: string): boolean {
  if (new TextEncoder().encode(path).length > MAX_PATH_BYTES) return false;
  const parts = path.split("/");
  if (parts.some((part) => part.length > MAX_COMPONENT_BYTES)) return false;
  if (parts.length === 1) return isTopFile(parts[0]);
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

import i18n, { languages, type Language } from "../i18n";
import { isScormContent, type ScormContent } from "../runtimes/content";
import { Scorm12Runtime } from "../runtimes/scorm12";
import { Scorm2004Runtime } from "../runtimes/scorm2004";
import { findApi, type ApiWindow, type LmsApi } from "./findApi";

/** The name of the content file next to the entry page of the package. */
export const CONTENT_FILE = "content.json";

/**
 * Fetches `content.json` relative to the page and returns it when it has
 * the shape of `ScormContent`. Returns `null` when the request fails, the
 * file is missing or its content is not a module of a package.
 */
export async function loadContent(
  fetchImpl: typeof fetch = fetch,
): Promise<ScormContent | null> {
  try {
    const response = await fetchImpl(CONTENT_FILE);
    if (!response.ok) return null;
    const content: unknown = await response.json();
    return isScormContent(content) ? content : null;
  } catch {
    return null;
  }
}

/**
 * The UI language for the locale of a pack: its primary language subtag
 * when the i18n files hold strings for it, otherwise English.
 */
export function uiLanguage(locale: string): Language {
  const primary = locale.trim().toLowerCase().split(/[-_]/)[0];
  return languages.find((language) => language === primary) ?? "en";
}

/** Switches the UI to the language of the pack (`uiLanguage` of its locale). */
export async function applyPackLanguage(content: ScormContent): Promise<void> {
  await i18n.changeLanguage(uiLanguage(content.program.locale));
}

/** The runtime of the version that the discovery found, not yet started. */
export function createRuntime(
  lms: LmsApi,
  content: ScormContent,
): Scorm12Runtime | Scorm2004Runtime {
  return lms.version === "2004"
    ? new Scorm2004Runtime(content, lms.api)
    : new Scorm12Runtime(content, lms.api);
}

/** The started runtime, or the notice that replaces the player. */
export type StartResult =
  | { kind: "started"; runtime: Scorm12Runtime | Scorm2004Runtime }
  | { kind: "notice"; reason: "noLms" | "startFailed" };

/**
 * Finds the LMS API from `win`, creates the runtime of its version and
 * starts it. Returns the notice `noLms` when no window offers an API and
 * `startFailed` when the start throws, as it does when the LMS refuses
 * the initialization.
 */
export function startRuntime(
  win: ApiWindow,
  content: ScormContent,
): StartResult {
  const lms = findApi(win);
  if (lms === null) return { kind: "notice", reason: "noLms" };
  const runtime = createRuntime(lms, content);
  try {
    runtime.start();
  } catch {
    return { kind: "notice", reason: "startFailed" };
  }
  return { kind: "started", runtime };
}

/**
 * Calls `onRestore` when the browser shows the page again from the
 * back/forward cache (`pageshow` with `persisted`). The runtime ended the
 * LMS session on the `pagehide` before, so the restored page can save
 * nothing. Returns the function that removes the listener.
 */
export function onRestoredFromCache(
  win: Window,
  onRestore: () => void,
): () => void {
  const listener = (event: PageTransitionEvent) => {
    if (event.persisted) onRestore();
  };
  win.addEventListener("pageshow", listener);
  return () => win.removeEventListener("pageshow", listener);
}

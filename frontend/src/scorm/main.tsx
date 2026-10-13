import { StrictMode, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import "../styles/app.css";
import { applyTheme, followSystemTheme } from "../app/theme";
import {
  applyPackLanguage,
  loadContent,
  onRestoredFromCache,
  startRuntime,
} from "./boot";
import { ScormLoading, ScormNotice, ScormPlayer } from "./ScormApp";

// The entry of the SCORM package (task 0016, step 2). It imports neither the
// API client nor the station map `src/learner/stations/`, whose stations call
// the API: the player reaches the LMS through a SCORM runtime only, so the
// bundle names no API route.

// scorm.html holds no inline script, so the theme is applied here, before
// the first render.
applyTheme();
followSystemTheme();

const root = createRoot(document.getElementById("root")!);

function show(node: ReactNode) {
  root.render(<StrictMode>{node}</StrictMode>);
}

/**
 * Loads `content.json`, switches the UI to the language of the pack, finds
 * the LMS API and starts the runtime of its version. Returns the player, or
 * the notice that replaces it. After a successful start, a page that the
 * browser restores from the back/forward cache shows the notice
 * `sessionEnded`, because the runtime ended the LMS session on `pagehide`.
 * A content file that passes `isScormContent` but fails in the mapping of
 * the runtime rejects.
 */
async function boot(): Promise<ReactNode> {
  const content = await loadContent();
  if (content === null) return <ScormNotice reason="contentFailed" />;
  await applyPackLanguage(content);
  document.title = content.module.title;

  const started = startRuntime(window, content);
  if (started.kind === "notice") return <ScormNotice reason={started.reason} />;
  onRestoredFromCache(window, () =>
    show(<ScormNotice reason="sessionEnded" />),
  );
  return <ScormPlayer content={content} runtime={started.runtime} />;
}

show(<ScormLoading />);
void boot().then(show, () => show(<ScormNotice reason="contentFailed" />));

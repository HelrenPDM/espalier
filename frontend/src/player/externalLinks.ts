import { createContext, useContext } from "react";

/**
 * The browsing context in which a link to another document opens:
 * `"_blank"` opens it in a new one, `undefined` in the current one.
 */
export type ExternalLinkTarget = "_blank" | undefined;

/**
 * The target of the links that leave the page: the link of a source title
 * and the links of Markdown text. The SCORM package provides `"_blank"`,
 * because a navigation of the SCO document fires `pagehide`, on which the
 * runtime ends the LMS session. The platform and the admin preview provide
 * nothing, so their links open in the current tab, as in task 0012.
 */
export const ExternalLinkTargetContext =
  createContext<ExternalLinkTarget>(undefined);

export function useExternalLinkTarget(): ExternalLinkTarget {
  return useContext(ExternalLinkTargetContext);
}

/**
 * Whether a link to `href` opens another document over HTTP: `href` is no
 * fragment of the page (`#…`), and its URL, resolved against the base URL
 * of the document, has the protocol `http:` or `https:`. A `mailto:` link
 * starts the mail program and leaves the page in place. An empty `href`
 * gives `false`, although following it reloads the document; `Markdown`
 * renders such a link without `href` when a target is set.
 */
export function leavesPage(href: string | undefined): boolean {
  if (href === undefined || href === "" || href.startsWith("#")) return false;
  try {
    const { protocol } = new URL(href, document.baseURI);
    return protocol === "https:" || protocol === "http:";
  } catch {
    return false;
  }
}

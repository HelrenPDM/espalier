import type { MouseEvent } from "react";

/**
 * Scrolls the element `id` into view and moves focus to it. In-page links
 * of the player (`#lesson-…`, `#objective-…`, `#rule-…`) call it on click
 * instead of changing the URL, so they work under the browser router and
 * under the memory router of the SCORM package alike. An element without
 * `tabIndex`, such as a lesson section, passes focus to its first element
 * with `tabIndex={-1}`, the lesson heading.
 */
export function jumpTo(id: string): void {
  const element = document.getElementById(id);
  if (element === null) return;
  const target = element.hasAttribute("tabindex")
    ? element
    : (element.querySelector<HTMLElement>('[tabindex="-1"]') ?? element);
  target.scrollIntoView?.({ block: "start" });
  target.focus({ preventScroll: true });
}

/** The click handler of an in-page link to the element `id`. */
export function jumpHandler(id: string) {
  return (event: MouseEvent<HTMLAnchorElement>) => {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey)
      return;
    event.preventDefault();
    jumpTo(id);
  };
}

import {
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";

/** The distance the bubble keeps from the edge of the viewport. */
const EDGE = 8;

/**
 * A tooltip for `text` on hover and focus (WCAG 2.2, 1.4.13): it stays open
 * while the pointer rests on the trigger or on the tooltip, and Escape
 * closes it without moving focus or pointer. `children` receives the id of
 * the description, which the trigger names in `aria-describedby`; the
 * visible bubble is hidden from assistive technology, so the text is read
 * once. `lang` marks the language of `text`. The bubble starts at the left
 * edge of the trigger and moves left as far as it would cross the right
 * edge of the viewport, so it never causes horizontal scrolling.
 */
export function Tooltip({
  text,
  lang,
  children,
}: {
  text: string;
  lang?: string;
  children: (describedBy: string) => ReactNode;
}) {
  const id = useId();
  const bubbleRef = useRef<HTMLSpanElement>(null);
  const [hovered, setHovered] = useState(false);
  const [focused, setFocused] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  const open = (hovered || focused) && !dismissed;

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setDismissed(true);
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [open]);

  // Measured before the browser paints the bubble.
  useLayoutEffect(() => {
    const bubble = bubbleRef.current;
    if (!open || bubble === null) return;
    bubble.style.transform = "";
    const rect = bubble.getBoundingClientRect();
    const overflow = rect.right - (document.documentElement.clientWidth - EDGE);
    const shift = Math.min(overflow, rect.left - EDGE);
    if (shift > 0) bubble.style.transform = `translateX(-${shift}px)`;
  }, [open]);

  return (
    <span
      className="relative"
      onMouseEnter={() => {
        setHovered(true);
        setDismissed(false);
      }}
      onMouseLeave={() => setHovered(false)}
      onFocus={() => {
        setFocused(true);
        setDismissed(false);
      }}
      onBlur={() => setFocused(false)}
    >
      {children(id)}
      <span id={id} lang={lang} className="sr-only">
        {text}
      </span>
      {open && (
        // The padding instead of a margin keeps the pointer inside the
        // wrapper on its way to the bubble.
        <span
          ref={bubbleRef}
          aria-hidden="true"
          data-testid="tooltip"
          className="absolute top-full left-0 z-20 block pt-1"
        >
          <span
            lang={lang}
            className="block w-max max-w-[min(18rem,calc(100vw-1rem))] rounded-md bg-gray-900 px-3 py-2 text-left text-sm font-normal whitespace-normal text-white shadow-lg dark:bg-gray-100 dark:text-gray-900"
          >
            {text}
          </span>
        </span>
      )}
    </span>
  );
}

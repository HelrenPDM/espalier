import { useEffect, useId, useState, type ReactNode } from "react";

/**
 * A tooltip for `text` on hover and focus (WCAG 2.2, 1.4.13): it stays open
 * while the pointer rests on the trigger or on the tooltip, and Escape
 * closes it without moving focus or pointer. `children` receives the id of
 * the description, which the trigger names in `aria-describedby`; the
 * visible bubble is hidden from assistive technology, so the text is read
 * once.
 */
export function Tooltip({
  text,
  children,
}: {
  text: string;
  children: (describedBy: string) => ReactNode;
}) {
  const id = useId();
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
      <span id={id} className="sr-only">
        {text}
      </span>
      {open && (
        // The padding instead of a margin keeps the pointer inside the
        // wrapper on its way to the bubble.
        <span
          aria-hidden="true"
          data-testid="tooltip"
          className="absolute top-full left-0 z-20 block pt-1"
        >
          <span className="block w-max max-w-[min(18rem,calc(100vw-2rem))] rounded-md bg-gray-900 px-3 py-2 text-left text-sm font-normal whitespace-normal text-white shadow-lg dark:bg-gray-100 dark:text-gray-900">
            {text}
          </span>
        </span>
      )}
    </span>
  );
}

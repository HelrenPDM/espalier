/**
 * The classes and helpers of the form controls in `forms.tsx`, in a module
 * of their own so that `forms.tsx` exports components only.
 */
export const FOCUS_RING =
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500";

export const BUTTON_CLASSES = {
  primary: `rounded-md bg-accent-600 px-4 py-2 text-sm font-semibold text-white hover:bg-accent-700 disabled:cursor-not-allowed disabled:opacity-50 ${FOCUS_RING}`,
  secondary: `rounded-md border border-gray-500 bg-white px-4 py-2 text-sm font-semibold text-gray-900 hover:bg-gray-100 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-900 dark:text-gray-100 dark:hover:bg-gray-800 ${FOCUS_RING}`,
  danger: `rounded-md border border-red-700 bg-white px-4 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-red-400 dark:bg-gray-900 dark:text-red-300 dark:hover:bg-gray-800 ${FOCUS_RING}`,
  link: `rounded-md font-medium text-accent-700 underline underline-offset-4 hover:text-accent-600 disabled:cursor-not-allowed disabled:opacity-50 dark:text-accent-100 dark:hover:text-accent-50 ${FOCUS_RING}`,
} as const;

export type ButtonVariant = keyof typeof BUTTON_CLASSES;

/** The classes of a button, also for a `Link` that looks like one. */
export function buttonClasses(variant: ButtonVariant = "primary"): string {
  return BUTTON_CLASSES[variant];
}

export const linkClasses = BUTTON_CLASSES.link;

/**
 * An entry of a navigation bar or sidebar: the main navigation of the
 * header and the sections of the admin area. The entry with
 * `aria-current="page"` carries the accent.
 */
export const navLinkClasses = `block rounded-md px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 aria-[current=page]:bg-accent-50 aria-[current=page]:text-accent-700 dark:text-gray-300 dark:hover:bg-gray-800 dark:aria-[current=page]:bg-accent-700 dark:aria-[current=page]:text-white ${FOCUS_RING}`;

/** Code points after NFC normalization, as the length check of 0004 step 14 counts. */
export function passwordLength(value: string): number {
  return [...value.normalize("NFC")].length;
}

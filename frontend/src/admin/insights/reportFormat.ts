import type { ReportCell } from "../../api/reports";

/** The properties of every report section. */
export interface SectionProps {
  /** The slug of the program. */
  slug: string;
  /**
   * The locale of the program in the list of published programs, or
   * `undefined` for a program that the list lacks, such as an archived one.
   * Pack text carries it as `lang` (see `packLang`).
   */
  lang: string | undefined;
}

/**
 * The language of the pack text of a report: the locale of the program in
 * the list of published programs, and otherwise the locale that every
 * report carries.
 */
export function packLang(
  lang: string | undefined,
  report: { locale: string },
): string {
  return lang ?? report.locale;
}

/**
 * The widths of a bar in steps of five percent. Tailwind generates only the
 * classes it finds literally in the source, so the list names every class,
 * and `barWidth` picks one of them.
 */
export const BAR_WIDTHS = [
  "w-0",
  "w-1/20",
  "w-2/20",
  "w-3/20",
  "w-4/20",
  "w-5/20",
  "w-6/20",
  "w-7/20",
  "w-8/20",
  "w-9/20",
  "w-10/20",
  "w-11/20",
  "w-12/20",
  "w-13/20",
  "w-14/20",
  "w-15/20",
  "w-16/20",
  "w-17/20",
  "w-18/20",
  "w-19/20",
  "w-full",
] as const;

/**
 * The width class for `fraction` from 0 to 1, rounded to the nearest step.
 * A value outside that range, or one that is not a number, is clamped.
 */
export function barWidth(fraction: number): (typeof BAR_WIDTHS)[number] {
  const clamped = Number.isFinite(fraction)
    ? Math.min(Math.max(fraction, 0), 1)
    : 0;
  return BAR_WIDTHS[Math.round(clamped * (BAR_WIDTHS.length - 1))];
}

/** The cell with its count, or `null` for a suppressed cell. */
export function shown(
  cell: ReportCell,
): { count: number; value: number } | null {
  return "suppressed" in cell ? null : cell;
}

/** The largest count among `cells`; suppressed cells count as nothing. */
export function largestCount(cells: Iterable<ReportCell>): number {
  let largest = 0;
  for (const cell of cells) {
    const visible = shown(cell);
    if (visible !== null && visible.count > largest) largest = visible.count;
  }
  return largest;
}

/** A month of a report (`YYYY-MM-DD`, the first day) as month and year. */
export function formatMonth(value: string, language: string): string {
  const date = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(language, {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  }).format(date);
}

/** A share from 0 to 1 as a whole percentage. */
export function formatShare(value: number, language: string): string {
  return new Intl.NumberFormat(language, {
    style: "percent",
    maximumFractionDigits: 0,
  }).format(value);
}

/** A count with the digit grouping of `language`. */
export function formatCount(value: number, language: string): string {
  return new Intl.NumberFormat(language).format(value);
}

const BORDER = "border-b border-gray-200 dark:border-gray-700";
const ROW_HEADER = `${BORDER} px-3 py-2 align-top text-gray-900 dark:text-gray-100`;

/** The classes of the report tables. */
export const TABLE_CLASSES = {
  table: "min-w-full border-collapse text-left text-sm",
  columnHeader: `${BORDER} bg-gray-50 px-3 py-2 align-bottom font-semibold text-gray-900 dark:bg-gray-800 dark:text-gray-100`,
  rowHeader: `${ROW_HEADER} font-medium`,
  /** A row header below a group header, such as an answer of a question. */
  subRowHeader: `${ROW_HEADER} font-normal`,
  cell: `${BORDER} px-3 py-2 align-top text-gray-800 dark:text-gray-200`,
} as const;

import { useTranslation } from "react-i18next";
import type { ReportCell } from "../../api/reports";
import {
  barWidth,
  formatCount,
  formatMonth,
  formatShare,
  shown,
  TABLE_CLASSES,
} from "./reportFormat";

/**
 * A bar of plain elements (task 0014, step 9): a track at the full width of
 * the cell and a fill whose width class `barWidth` picks from `fraction`.
 * The number of the cell carries the information, so the bar is hidden
 * from assistive technology.
 */
export function Bar({ fraction }: { fraction: number }) {
  return (
    <div
      aria-hidden="true"
      data-bar={barWidth(fraction)}
      className="mt-1 h-1.5 w-full min-w-16 overflow-hidden rounded-full bg-gray-200 dark:bg-gray-700"
    >
      <div
        className={`h-full rounded-full bg-accent-600 dark:bg-accent-500 ${barWidth(fraction)}`}
      />
    </div>
  );
}

/** A column header per month of a report, in the order of `months`. */
export function MonthHeaders({ months }: { months: readonly string[] }) {
  const { i18n } = useTranslation();
  return months.map((month) => (
    <th key={month} scope="col" className={TABLE_CLASSES.columnHeader}>
      {formatMonth(month, i18n.language)}
    </th>
  ));
}

/** An org unit, or a note for the row of the answers without one. */
export function OrgUnit({ value }: { value: string | null }) {
  const { t } = useTranslation();
  if (value !== null) return <>{value}</>;
  return (
    <span className="font-normal text-gray-600 italic dark:text-gray-400">
      {t("reports.noOrgUnit")}
    </span>
  );
}

/** The text of a suppressed cell: "fewer than N" with the threshold `size`. */
export function Suppressed({ size }: { size: number }) {
  const { t } = useTranslation();
  return (
    <span className="text-gray-600 italic dark:text-gray-400">
      {t("reports.suppressed", { size })}
    </span>
  );
}

/**
 * A cell of a count report: the count and a bar relative to `largest`, the
 * largest count of the table, or the text of a suppressed cell.
 */
export function CountCell({
  cell,
  largest,
  size,
}: {
  cell: ReportCell;
  largest: number;
  size: number;
}) {
  const { i18n } = useTranslation();
  const visible = shown(cell);
  return (
    <td className={TABLE_CLASSES.cell}>
      {visible === null ? (
        <Suppressed size={size} />
      ) : (
        <>
          <span className="tabular-nums">
            {formatCount(visible.count, i18n.language)}
          </span>
          <Bar fraction={largest > 0 ? visible.count / largest : 0} />
        </>
      )}
    </td>
  );
}

/**
 * A cell of the item and competence reports: the share correct with a bar
 * of that width and the number of attempts, or the text of a suppressed
 * cell.
 */
export function ShareCell({ cell, size }: { cell: ReportCell; size: number }) {
  const { t, i18n } = useTranslation();
  const visible = shown(cell);
  return (
    <td className={TABLE_CLASSES.cell}>
      {visible === null ? (
        <Suppressed size={size} />
      ) : (
        <>
          <span className="font-medium tabular-nums">
            {formatShare(visible.value, i18n.language)}
          </span>
          <span className="block text-xs text-gray-600 dark:text-gray-400">
            {t("reports.attempts", { count: visible.count })}
          </span>
          <Bar fraction={visible.value} />
        </>
      )}
    </td>
  );
}

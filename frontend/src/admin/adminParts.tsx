import { useId, type ButtonHTMLAttributes, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Button } from "../app/forms";
import { FOCUS_RING } from "../app/formStyles";
import { TABLE_CLASSES } from "./insights/reportFormat";

/**
 * The parts that the users, roles, API clients, webhooks and audit pages
 * of the admin area share (task 0015): a table in a region that scrolls
 * sideways, the paging of a list, a labelled checkbox and the action
 * buttons of a table row. The tables use the classes of the reports page.
 */

/**
 * A table named by the heading `labelledBy`, inside a region that scrolls
 * sideways and takes the focus, so a keyboard user can scroll a wide
 * table. The region carries the name of the heading, so the section
 * around it stays unnamed, as on the reports page.
 */
export function TableFrame({
  labelledBy,
  describedBy,
  children,
}: {
  labelledBy: string;
  describedBy?: string;
  children: ReactNode;
}) {
  return (
    <div
      role="region"
      aria-labelledby={labelledBy}
      tabIndex={0}
      className={`overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700 ${FOCUS_RING}`}
    >
      <table
        aria-labelledby={labelledBy}
        aria-describedby={describedBy}
        className={TABLE_CLASSES.table}
      >
        {children}
      </table>
    </div>
  );
}

/**
 * "Previous page" and "Next page" with the current page between them, in a
 * navigation landmark named `label`. `pages` is the number of pages when
 * the list names its total.
 */
export function Pager({
  label,
  page,
  pages,
  hasNext,
  onPage,
}: {
  label: string;
  page: number;
  pages?: number;
  hasNext: boolean;
  onPage: (page: number) => void;
}) {
  const { t } = useTranslation();
  return (
    <nav aria-label={label} className="mt-4 flex flex-wrap items-center gap-4">
      <Button
        variant="secondary"
        disabled={page <= 1}
        onClick={() => onPage(page - 1)}
      >
        {t("admin.common.previousPage")}
      </Button>
      <p className="text-sm text-gray-700 dark:text-gray-300">
        {pages === undefined
          ? t("admin.common.page", { page })
          : t("admin.common.pageOf", { page, pages })}
      </p>
      <Button
        variant="secondary"
        disabled={!hasNext}
        onClick={() => onPage(page + 1)}
      >
        {t("admin.common.nextPage")}
      </Button>
    </nav>
  );
}

/** A checkbox with its label to the right. */
export function CheckboxField({
  label,
  checked,
  onChange,
  name,
  value,
}: {
  label: ReactNode;
  checked: boolean;
  onChange: (checked: boolean) => void;
  name?: string;
  value?: string;
}) {
  const id = useId();
  return (
    <div className="flex items-center gap-2">
      <input
        id={id}
        type="checkbox"
        name={name}
        value={value}
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
        className={`size-4 rounded border-gray-500 ${FOCUS_RING}`}
      />
      <label htmlFor={id} className="text-sm text-gray-900 dark:text-gray-100">
        {label}
      </label>
    </div>
  );
}

const ROW_ACTION_CLASSES = {
  default: `rounded-md text-left text-sm font-medium text-accent-700 underline underline-offset-4 hover:text-accent-600 disabled:cursor-not-allowed disabled:opacity-50 dark:text-accent-100 dark:hover:text-accent-50 ${FOCUS_RING}`,
  danger: `rounded-md text-left text-sm font-medium text-red-700 underline underline-offset-4 hover:text-red-600 disabled:cursor-not-allowed disabled:opacity-50 dark:text-red-300 dark:hover:text-red-200 ${FOCUS_RING}`,
} as const;

/**
 * An action in a table row, such as "Disable". `subject` names the row,
 * such as the person, for assistive technology, so that every button of
 * the table has a name of its own; an `aria-label` that starts with the
 * visible text does the same.
 */
export function RowAction({
  children,
  subject,
  danger = false,
  ...props
}: Omit<ButtonHTMLAttributes<HTMLButtonElement>, "type" | "className"> & {
  subject?: string;
  danger?: boolean;
}) {
  return (
    <button
      type="button"
      className={ROW_ACTION_CLASSES[danger ? "danger" : "default"]}
      {...props}
    >
      {children}
      {subject !== undefined && (
        <>
          {" "}
          <span className="sr-only">{subject}</span>
        </>
      )}
    </button>
  );
}

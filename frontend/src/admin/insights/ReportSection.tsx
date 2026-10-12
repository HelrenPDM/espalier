import type { UseQueryResult } from "@tanstack/react-query";
import { useId, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { FOCUS_RING } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { ApiError } from "../../api/errors";
import { TABLE_CLASSES } from "./reportFormat";

/**
 * The frame of one report section: the heading, a description, and the
 * loading, error and empty states of its query. With data, it renders the
 * table of the section, named by the heading and described by the
 * description, inside a region that scrolls sideways and takes the focus,
 * so a keyboard user can scroll a wide table. `children` returns the head
 * and the body of the table; `after` renders below the table.
 */
export function ReportSection<T>({
  title,
  description,
  query,
  isEmpty,
  empty,
  children,
  after,
}: {
  title: string;
  description: string;
  query: UseQueryResult<T>;
  isEmpty: (data: T) => boolean;
  empty: string;
  children: (data: T) => ReactNode;
  after?: (data: T) => ReactNode;
}) {
  const { t } = useTranslation();
  const headingId = useId();
  const descriptionId = useId();

  let body: ReactNode;
  if (query.isPending) {
    body = <LoadingStatus text={t("reports.loading")} />;
  } else if (query.isError) {
    body = (
      <p role="alert" className="text-gray-700 dark:text-gray-300">
        {query.error instanceof ApiError && query.error.status === 404
          ? t("reports.notFound")
          : t("reports.loadFailed")}
      </p>
    );
  } else if (isEmpty(query.data)) {
    body = <p className="text-gray-700 dark:text-gray-300">{empty}</p>;
  } else {
    body = (
      <>
        <div
          role="region"
          aria-labelledby={headingId}
          tabIndex={0}
          className={`overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700 ${FOCUS_RING}`}
        >
          <table
            aria-labelledby={headingId}
            aria-describedby={descriptionId}
            className={TABLE_CLASSES.table}
          >
            {children(query.data)}
          </table>
        </div>
        {after?.(query.data)}
      </>
    );
  }

  return (
    <section className="mt-10">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {title}
      </h2>
      <p
        id={descriptionId}
        className="mt-1 mb-4 text-sm text-gray-700 dark:text-gray-300"
      >
        {description}
      </p>
      {body}
    </section>
  );
}

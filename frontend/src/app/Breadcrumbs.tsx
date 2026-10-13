import { ChevronRightIcon } from "@heroicons/react/20/solid";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { linkClasses } from "./formStyles";

export interface BreadcrumbItem {
  label: string;
  /** The target of the link; the last item renders as text without one. */
  to?: string;
  /**
   * The language of `label` when it is pack text, such as a program or
   * station title in the language of the program.
   */
  lang?: string;
}

/**
 * The trail from a section to the current page: every item but the last is
 * a link, and the last one is text with `aria-current="page"`. The
 * separators are decorative. The trail does not print.
 */
export function Breadcrumbs({
  items,
  className = "",
}: {
  items: readonly BreadcrumbItem[];
  /** Further classes of the `<nav>`, such as a margin. */
  className?: string;
}) {
  const { t } = useTranslation();
  const last = items.length - 1;

  return (
    <nav
      aria-label={t("layout.breadcrumb")}
      className={`no-print text-sm ${className}`}
    >
      <ol className="flex flex-wrap items-center gap-x-1 gap-y-1">
        {items.map((item, index) => (
          <li key={index} className="flex min-w-0 items-center gap-x-1">
            {index > 0 && (
              <ChevronRightIcon
                aria-hidden="true"
                className="size-4 shrink-0 text-gray-500 dark:text-gray-400"
              />
            )}
            {index < last && item.to !== undefined ? (
              <Link
                to={item.to}
                lang={item.lang}
                className={`break-words ${linkClasses}`}
              >
                {item.label}
              </Link>
            ) : (
              <span
                lang={item.lang}
                aria-current={index === last ? "page" : undefined}
                className="break-words text-gray-700 dark:text-gray-300"
              >
                {item.label}
              </span>
            )}
          </li>
        ))}
      </ol>
    </nav>
  );
}

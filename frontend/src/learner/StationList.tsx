import { CheckIcon } from "@heroicons/react/20/solid";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { FOCUS_RING } from "../app/formStyles";
import { useContentLang } from "../player/contentLang";
import { sortedStations } from "../player/program";
import type { ProgramView, ResumeState } from "../player/runtime";
import { useProgramBase } from "../player/programBase";

/** `children` in a navigation landmark named `label`, or alone for `null`. */
function Landmark({
  label,
  children,
}: {
  label: string | null;
  children: ReactNode;
}) {
  return label === null ? children : <nav aria-label={label}>{children}</nav>;
}

/**
 * The step list of a program: every station with its position, a mark for
 * the visited ones and the current one as `aria-current="step"`. It is a
 * navigation landmark of its own, unless `labelledBy` names the element
 * that labels the list inside a navigation that holds it.
 */
export function StationList({
  program,
  state,
  current = null,
  labelledBy,
}: {
  program: ProgramView;
  state: ResumeState;
  current?: number | null;
  labelledBy?: string;
}) {
  const { t } = useTranslation();
  const programBase = useProgramBase();
  const lang = useContentLang();
  const stations = sortedStations(program);
  return (
    <Landmark label={labelledBy === undefined ? t("station.listLabel") : null}>
      <ol aria-labelledby={labelledBy} className="space-y-1">
        {stations.map((station, index) => {
          const visited = state.visitedStations.includes(station.position);
          const isCurrent = station.position === current;
          return (
            <li key={station.position}>
              <Link
                to={`${programBase}/${program.slug}/stations/${station.position}`}
                aria-current={isCurrent ? "step" : undefined}
                className={`flex min-h-6 items-start gap-2 rounded-md px-2 py-1.5 text-sm hover:bg-gray-100 dark:hover:bg-gray-800 ${
                  isCurrent
                    ? "bg-gray-100 font-semibold text-gray-900 dark:bg-gray-800 dark:text-gray-100"
                    : "text-gray-800 dark:text-gray-200"
                } ${FOCUS_RING}`}
              >
                <span className="w-5 shrink-0 text-right tabular-nums">
                  {index + 1}.
                </span>
                <span lang={lang} className="min-w-0 flex-1 break-words">
                  {station.title}
                </span>
                {visited && (
                  <span className="inline-flex shrink-0 items-center gap-0.5 text-xs text-gray-700 dark:text-gray-300">
                    <CheckIcon aria-hidden="true" className="size-4" />
                    {t("station.visited")}
                  </span>
                )}
              </Link>
            </li>
          );
        })}
      </ol>
    </Landmark>
  );
}

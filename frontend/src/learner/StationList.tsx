import { CheckIcon } from "@heroicons/react/20/solid";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { FOCUS_RING } from "../app/formStyles";
import { useContentLang } from "../player/contentLang";
import { sortedStations } from "../player/program";
import type { ProgramView, ResumeState } from "../player/runtime";

/**
 * The step list of a program: every station with its position, a mark for
 * the visited ones and the current one as `aria-current="step"`.
 */
export function StationList({
  program,
  state,
  current = null,
}: {
  program: ProgramView;
  state: ResumeState;
  current?: number | null;
}) {
  const { t } = useTranslation();
  const lang = useContentLang();
  const stations = sortedStations(program);
  return (
    <nav aria-label={t("station.listLabel")}>
      <ol className="space-y-1">
        {stations.map((station, index) => {
          const visited = state.visitedStations.includes(station.position);
          const isCurrent = station.position === current;
          return (
            <li key={station.position}>
              <Link
                to={`/programs/${program.slug}/stations/${station.position}`}
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
    </nav>
  );
}

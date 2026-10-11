import {
  CheckCircleIcon,
  MinusCircleIcon,
  PencilSquareIcon,
} from "@heroicons/react/20/solid";
import { useEffect, useId, useRef } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { linkClasses } from "../app/formStyles";
import {
  AREAS,
  areaKey,
  depthKey,
  STATUSES,
  statusKey,
} from "../player/objectives/labels";
import { objectiveStatus, statusCounts } from "../player/objectives/status";
import type {
  ModuleView,
  ObjectiveStatus,
  ProgramView,
  ResumeState,
} from "../player/runtime";

const STATUS_ICONS = {
  evidenced: CheckCircleIcon,
  practised: PencilSquareIcon,
  open: MinusCircleIcon,
} satisfies Record<ObjectiveStatus, unknown>;

/**
 * The objectives of a completed module with their status (README section
 * 7, rule 15), grouped by area in the order of `AREAS`. A sentence gives
 * the number per status, a legend explains the statuses, and an objective
 * that a companion format can show names that format. The status appears
 * as text next to an icon, so it never depends on color alone. The summary
 * shows no percentage, no progress bar and no comparison with other
 * people.
 */
export function CompletionSummary({
  module,
  program,
  state,
  focusOnMount = false,
}: {
  module: ModuleView;
  program: ProgramView;
  state: ResumeState;
  /** Moves focus to the heading when the summary appears after a completion. */
  focusOnMount?: boolean;
}) {
  const { t } = useTranslation();
  const headingId = useId();
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    if (focusOnMount) headingRef.current?.focus();
  }, [focusOnMount]);

  const counts = statusCounts(module.objectives, program, state);
  const formatStation = program.stations.find(
    (station) => station.kind === "companion_formats",
  );
  const formatTitle = (id: string) =>
    program.companion_formats.find((format) => format.id === id)?.title;

  return (
    <section
      aria-labelledby={headingId}
      className="rounded-lg border border-gray-300 p-4 dark:border-gray-600"
    >
      <h2
        id={headingId}
        ref={headingRef}
        tabIndex={-1}
        className="text-xl font-semibold tracking-tight focus:outline-none"
      >
        {t("completion.title")}
      </h2>
      {module.objectives.length > 0 && (
        <>
          <p className="mt-2">
            {t("completion.counts", {
              evidenced: t("completion.countEvidenced", {
                count: counts.evidenced,
              }),
              practised: t("completion.countPractised", {
                count: counts.practised,
              }),
              open: t("completion.countOpen", { count: counts.open }),
            })}
          </p>
          <dl className="mt-3 space-y-1 text-sm text-gray-700 dark:text-gray-300">
            {STATUSES.map((status) => {
              const Icon = STATUS_ICONS[status];
              return (
                <div key={status} className="flex flex-wrap gap-x-1">
                  <dt className="inline-flex items-center gap-1 font-semibold">
                    <Icon aria-hidden="true" className="size-4 shrink-0" />
                    {t(statusKey(status))}:
                  </dt>
                  <dd>{t(`completion.legend.${status}`)}</dd>
                </div>
              );
            })}
          </dl>
          {AREAS.map((area) => {
            const objectives = module.objectives.filter(
              (objective) => objective.area === area,
            );
            if (objectives.length === 0) return null;
            return (
              <div key={area} className="mt-4">
                <h3 className="font-semibold">{t(areaKey(area))}</h3>
                <ul className="mt-2 space-y-3">
                  {objectives.map((objective) => {
                    const status = objectiveStatus(objective, program, state);
                    const Icon = STATUS_ICONS[status];
                    const formats =
                      status === "evidenced"
                        ? []
                        : objective.evidence.flatMap((entry) => {
                            const title =
                              entry.kind === "format"
                                ? formatTitle(entry.id)
                                : undefined;
                            return title === undefined
                              ? []
                              : [{ id: entry.id, title }];
                          });
                    return (
                      <li
                        key={objective.key}
                        data-objective-key={objective.key}
                      >
                        <p>{objective.statement}</p>
                        <p className="mt-1 flex flex-wrap items-center gap-x-3 text-sm">
                          <span className="text-gray-700 dark:text-gray-300">
                            {t("objectives.depthLine", {
                              depth: t(depthKey(objective.depth)),
                            })}
                          </span>
                          <span
                            className="inline-flex items-center gap-1 font-semibold"
                            data-status={status}
                          >
                            <Icon
                              aria-hidden="true"
                              className="size-4 shrink-0"
                            />
                            {t(statusKey(status))}
                          </span>
                        </p>
                        {formats.map((format) => (
                          <p
                            key={format.id}
                            className="mt-1 text-sm text-gray-700 dark:text-gray-300"
                          >
                            {t("completion.formatNote", {
                              format: format.title,
                            })}
                            {formatStation && (
                              <>
                                {" "}
                                <Link
                                  to={`/programs/${program.slug}/stations/${formatStation.position}`}
                                  className={linkClasses}
                                >
                                  {t("completion.formatLink", {
                                    station: formatStation.title,
                                  })}
                                </Link>
                              </>
                            )}
                          </p>
                        ))}
                      </li>
                    );
                  })}
                </ul>
              </div>
            );
          })}
        </>
      )}
    </section>
  );
}

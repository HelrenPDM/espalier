import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { FOCUS_RING } from "../../app/formStyles";
import { jumpHandler } from "../jump";
import { useContentLang } from "../contentLang";
import { moduleStation } from "../program";
import type { ObjectiveView, ProgramView } from "../runtime";
import { Tooltip } from "../Tooltip";
import { areaKey, depthKey } from "./labels";
import { useProgramBase } from "../programBase";

interface ChipTarget {
  objective: ObjectiveView;
  moduleId: string;
}

const CHIP_CLASSES = `inline-flex min-h-6 min-w-6 items-center rounded-full border border-gray-400 bg-white px-2.5 py-0.5 text-sm text-gray-800 hover:border-accent-600 hover:text-accent-700 dark:border-gray-500 dark:bg-gray-900 dark:text-gray-100 dark:hover:border-accent-100 dark:hover:text-accent-100 ${FOCUS_RING}`;

/**
 * The objectives an item serves, as chips below its stem. A chip shows the
 * area and the depth; the statement is its accessible description and
 * appears in a tooltip. A chip of the current module moves focus to the
 * objective in the panel, a chip of another module links to the station of
 * that module. A key that names no objective of the program renders
 * nothing, and an item without such keys renders no list.
 */
export function ObjectiveChips({
  objectiveKeys,
  program,
  moduleId,
}: {
  objectiveKeys: string[];
  program: ProgramView;
  moduleId: string;
}) {
  const { t } = useTranslation();
  const programBase = useProgramBase();
  const lang = useContentLang();
  const targets = objectiveKeys.flatMap((key): ChipTarget[] => {
    for (const module of program.modules) {
      const objective = module.objectives.find((entry) => entry.key === key);
      if (objective) return [{ objective, moduleId: module.id }];
    }
    return [];
  });
  if (targets.length === 0) return null;

  return (
    <ul
      aria-label={t("objectives.chipsLabel")}
      className="mt-2 flex flex-wrap gap-2"
    >
      {targets.map(({ objective, moduleId: target }) => {
        const text = t("objectives.chip", {
          area: t(areaKey(objective.area)),
          depth: t(depthKey(objective.depth)),
        });
        const station = moduleStation(program, target);
        const chip = (describedBy: string): ReactNode => {
          if (target === moduleId)
            return (
              <a
                href={`#objective-${objective.key}`}
                onClick={jumpHandler(`objective-${objective.key}`)}
                aria-describedby={describedBy}
                className={CHIP_CLASSES}
              >
                {text}
              </a>
            );
          if (station === undefined)
            return (
              <span
                tabIndex={0}
                aria-describedby={describedBy}
                className={CHIP_CLASSES}
              >
                {text}
              </span>
            );
          return (
            <Link
              to={`${programBase}/${program.slug}/stations/${station.position}#objective-${objective.key}`}
              aria-describedby={describedBy}
              className={CHIP_CLASSES}
            >
              {text}
            </Link>
          );
        };
        return (
          <li key={objective.key}>
            <Tooltip text={objective.statement} lang={lang}>
              {chip}
            </Tooltip>
          </li>
        );
      })}
    </ul>
  );
}

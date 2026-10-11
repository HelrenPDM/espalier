import { useId } from "react";
import { useTranslation } from "react-i18next";
import { linkClasses } from "../../app/formStyles";
import { jumpHandler } from "../jump";
import { useContentLang } from "../contentLang";
import type { ModuleView } from "../runtime";
import { AREAS, areaKey, depthKey } from "./labels";

/**
 * The learning objectives of the topic at the top of a module station
 * (README section 7, rule 15), grouped by the four competence areas in the
 * order of `AREAS`. An area without an objective of the module gets no
 * group, and a module without objectives renders no panel. Each entry shows
 * statement, depth, domain and the lessons that teach it; the panel shows
 * no status.
 */
export function ObjectivesPanel({ module }: { module: ModuleView }) {
  const { t } = useTranslation();
  const headingId = useId();
  const lang = useContentLang();
  if (module.objectives.length === 0) return null;

  const lessonTitle = (id: string) =>
    module.lessons.find((lesson) => lesson.id === id)?.title;

  return (
    <section
      aria-labelledby={headingId}
      className="rounded-lg border border-gray-200 p-4 dark:border-gray-700"
    >
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("objectives.panelTitle")}
      </h2>
      {AREAS.map((area) => {
        const objectives = module.objectives.filter(
          (objective) => objective.area === area,
        );
        if (objectives.length === 0) return null;
        return (
          <div key={area} className="mt-4">
            <h3 className="font-semibold">{t(areaKey(area))}</h3>
            <ul className="mt-2 space-y-3">
              {objectives.map((objective) => (
                <li
                  key={objective.key}
                  id={`objective-${objective.key}`}
                  tabIndex={-1}
                  className="rounded-md focus:outline-2 focus:outline-offset-2 focus:outline-accent-500"
                >
                  <p lang={lang}>{objective.statement}</p>
                  <p className="mt-1 text-sm text-gray-700 dark:text-gray-300">
                    {t("objectives.depthLine", {
                      depth: t(depthKey(objective.depth)),
                    })}
                    {objective.domain !== null && (
                      <>
                        {" "}
                        {t("objectives.domain")}{" "}
                        <span lang={lang}>{objective.domain}</span>.
                      </>
                    )}
                  </p>
                  {objective.lesson_ids.length > 0 && (
                    <p className="mt-1 text-sm">
                      {t("objectives.taughtIn")}{" "}
                      {objective.lesson_ids.map((id, index) => (
                        <span key={id}>
                          {index > 0 && ", "}
                          <a
                            href={`#lesson-${id}`}
                            lang={lang}
                            onClick={jumpHandler(`lesson-${id}`)}
                            className={linkClasses}
                          >
                            {lessonTitle(id) ?? id}
                          </a>
                        </span>
                      ))}
                    </p>
                  )}
                </li>
              ))}
            </ul>
          </div>
        );
      })}
    </section>
  );
}

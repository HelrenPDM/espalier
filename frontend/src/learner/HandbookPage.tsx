import { PrinterIcon } from "@heroicons/react/20/solid";
import { useTranslation } from "react-i18next";
import { LoadingStatus } from "../app/LoadingStatus";
import { buttonClasses } from "../app/formStyles";
import { useHandbook } from "../api/programs";
import { formatDay } from "../player/format";
import { Markdown } from "../player/Markdown";
import { useContentLang } from "../player/contentLang";
import { useCurrentPlayer } from "../player/usePlayer";
import { BackToProgram } from "./BackToProgram";
import { useProgramChrome } from "./programChrome";

/**
 * `/programs/:slug/handbook`: every rule with statement and action, grouped
 * by module, and one section per policy placeholder (README section 7,
 * rule 10) with the current version of the organization's policy, or a
 * note that the organization has not published it yet (task 0013, step
 * 21). Rules and titles carry the language of the program; the policy
 * text carries no `lang` and inherits the language of the document. It
 * prints on A4 without the navigation; every module after the first starts
 * a new page. Outside the program shell it links back to the program page.
 */
export function HandbookPage() {
  const { t, i18n } = useTranslation();
  const { program } = useCurrentPlayer();
  const lang = useContentLang();
  const handbook = useHandbook(program.slug);
  const chrome = useProgramChrome();

  return (
    <article className="max-w-3xl">
      {!chrome && (
        <p className="no-print mb-4 text-sm">
          <BackToProgram />
        </p>
      )}
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            {t("handbook.title")}
          </h1>
          <p lang={lang} className="mt-1 text-gray-700 dark:text-gray-300">
            {program.title}
          </p>
        </div>
        <button
          type="button"
          onClick={() => window.print()}
          className={`no-print inline-flex items-center gap-2 ${buttonClasses("secondary")}`}
        >
          <PrinterIcon aria-hidden="true" className="size-4" />
          {t("handbook.print")}
        </button>
      </div>
      {handbook.isPending ? (
        <div className="mt-6">
          <LoadingStatus text={t("handbook.loading")} />
        </div>
      ) : handbook.isError ? (
        <p role="alert" className="mt-6">
          {t("handbook.loadFailed")}
        </p>
      ) : (
        <>
          {handbook.data.modules.map((module) => (
            <section
              key={module.id}
              aria-labelledby={`handbook-module-${module.id}`}
              className="handbook-module mt-8"
            >
              <h2
                id={`handbook-module-${module.id}`}
                className="text-xl font-semibold tracking-tight"
              >
                {t("handbook.module", { number: module.number })}{" "}
                <span lang={lang}>{module.title}</span>
              </h2>
              <ol className="mt-3 space-y-4">
                {module.rules.map((rule) => (
                  <li key={rule.number} className="break-inside-avoid">
                    <p className="font-semibold">
                      {t("rules.number", { number: rule.number })}
                    </p>
                    <Markdown className="prose-p:my-0">
                      {rule.statement}
                    </Markdown>
                    <p className="mt-2 text-sm font-medium text-gray-700 dark:text-gray-300">
                      {t("rules.action")}
                    </p>
                    <Markdown className="prose-p:my-0">{rule.action}</Markdown>
                  </li>
                ))}
              </ol>
            </section>
          ))}
          {handbook.data.placeholders.length > 0 && (
            <section aria-labelledby="handbook-placeholders" className="mt-8">
              <h2
                id="handbook-placeholders"
                className="text-xl font-semibold tracking-tight"
              >
                {t("handbook.placeholders")}
              </h2>
              {handbook.data.placeholders.map(({ key, policy }) => (
                <section
                  key={key}
                  aria-labelledby={`handbook-placeholder-${key}`}
                  className={`mt-4 rounded-md border p-4 ${
                    policy === null
                      ? "border-dashed border-gray-400 dark:border-gray-500"
                      : "border-gray-300 dark:border-gray-600"
                  }`}
                >
                  <h3
                    id={`handbook-placeholder-${key}`}
                    className="font-semibold"
                  >
                    {key}
                  </h3>
                  {policy === null ? (
                    <p className="mt-1 text-gray-700 dark:text-gray-300">
                      {t("handbook.policyMissing")}
                    </p>
                  ) : (
                    <>
                      <Markdown lang={null} className="mt-2">
                        {policy.body}
                      </Markdown>
                      <p className="mt-2 text-sm text-gray-700 dark:text-gray-300">
                        {t("policies.version", {
                          number: policy.number,
                          date: formatDay(policy.effective_from, i18n.language),
                        })}
                      </p>
                    </>
                  )}
                </section>
              ))}
            </section>
          )}
        </>
      )}
    </article>
  );
}

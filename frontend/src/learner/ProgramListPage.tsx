import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { LoadingStatus } from "../app/LoadingStatus";
import { linkClasses } from "../app/formStyles";
import { usePrograms } from "../api/programs";

/** The name of a language tag in the UI language, or the tag itself. */
function languageName(tag: string, language: string): string {
  try {
    return (
      new Intl.DisplayNames([language], { type: "language" }).of(tag) ?? tag
    );
  } catch {
    return tag;
  }
}

/** `/`: the published programs with title and language. */
export function ProgramListPage() {
  const { t, i18n } = useTranslation();
  const programs = usePrograms();

  return (
    <section className="max-w-3xl">
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("programs.title")}
      </h1>
      {programs.isPending ? (
        <div className="mt-4">
          <LoadingStatus text={t("programs.loading")} />
        </div>
      ) : programs.isError ? (
        <p role="alert" className="mt-4 text-gray-700 dark:text-gray-300">
          {t("programs.loadFailed")}
        </p>
      ) : programs.data.length === 0 ? (
        <p className="mt-4 text-gray-700 dark:text-gray-300">
          {t("programs.empty")}
        </p>
      ) : (
        <ul className="mt-6 space-y-4">
          {programs.data.map((program) => (
            <li
              key={program.slug}
              className="rounded-lg border border-gray-200 p-4 dark:border-gray-700"
            >
              <Link
                to={`/programs/${program.slug}`}
                lang={program.locale}
                className={`text-lg ${linkClasses}`}
              >
                {program.title}
              </Link>
              <p className="mt-1 text-sm text-gray-700 dark:text-gray-300">
                {t("programs.language", {
                  language: languageName(program.locale, i18n.language),
                })}
              </p>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

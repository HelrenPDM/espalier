import { useEffect } from "react";
import { useTranslation } from "react-i18next";
import { Link, useLocation } from "react-router";
import { linkClasses } from "../app/formStyles";
import { jumpTo } from "../player/jump";
import { useCurrentPlayer } from "../player/usePlayer";

/**
 * `/programs/:slug/glossary`: the glossary of the program in alphabetical
 * order, with an anchor per slug that the glossary terms link to.
 */
export function GlossaryPage() {
  const { t } = useTranslation();
  const { hash } = useLocation();
  const { program } = useCurrentPlayer();
  const collator = new Intl.Collator(program.locale);
  const terms = [...program.glossary].sort((a, b) =>
    collator.compare(a.label, b.label),
  );

  useEffect(() => {
    if (hash.length > 1) jumpTo(hash.slice(1));
  }, [hash]);

  return (
    <section className="max-w-3xl">
      <p className="no-print text-sm">
        <Link to={`/programs/${program.slug}`} className={linkClasses}>
          {t("program.back", { title: program.title })}
        </Link>
      </p>
      <h1 className="mt-4 text-2xl font-semibold tracking-tight">
        {t("glossary.title")}
      </h1>
      {terms.length === 0 ? (
        <p className="mt-4">{t("glossary.empty")}</p>
      ) : (
        <dl className="mt-6 space-y-4">
          {terms.map((term) => (
            <div key={term.slug}>
              <dt
                id={term.slug}
                tabIndex={-1}
                className="rounded-md font-semibold focus:outline-2 focus:outline-offset-2 focus:outline-accent-500"
              >
                {term.label}
              </dt>
              <dd className="mt-1 text-gray-700 dark:text-gray-300">
                {term.short_text}
              </dd>
            </div>
          ))}
        </dl>
      )}
    </section>
  );
}

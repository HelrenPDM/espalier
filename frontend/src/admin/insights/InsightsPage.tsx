import { useId } from "react";
import { useTranslation } from "react-i18next";
import { useSearchParams } from "react-router";
import { LoadingStatus } from "../../app/LoadingStatus";
import { ApiError } from "../../api/errors";
import { usePrograms, type ProgramSummary } from "../../api/programs";
import { useSelfAssessmentReport } from "../../api/reports";
import { CompetenceSection } from "./CompetenceSection";
import { CredentialSection } from "./CredentialSection";
import { FeedbackSection } from "./FeedbackSection";
import { FormatSection } from "./FormatSection";
import { ItemSection } from "./ItemSection";
import { SelfAssessmentSection } from "./SelfAssessmentSection";
import type { SectionProps } from "./reportFormat";

/**
 * The six report sections of one program. A program that does not exist
 * answers 404 on every report; the first report decides, so the page says
 * so once instead of in every section. The section reads the same cached
 * query, so this check sends no request of its own.
 */
function Reports({ slug, lang }: SectionProps) {
  const { t } = useTranslation();
  const first = useSelfAssessmentReport(slug);
  if (first.error instanceof ApiError && first.error.status === 404)
    return (
      <p role="alert" className="mt-8 text-gray-700 dark:text-gray-300">
        {t("reports.notFound")}
      </p>
    );
  return (
    <>
      <SelfAssessmentSection slug={slug} lang={lang} />
      <ItemSection slug={slug} lang={lang} />
      <CompetenceSection slug={slug} lang={lang} />
      <FormatSection slug={slug} lang={lang} />
      <FeedbackSection slug={slug} lang={lang} />
      <CredentialSection slug={slug} lang={lang} />
    </>
  );
}

/**
 * The program picker over the published programs. A slug of the URL that
 * the list lacks, such as that of an archived program, stays selectable,
 * because the reports read a program in any status; its language comes
 * from the locale of the self-assessment report, which `Reports` loads.
 * The picker only reads that report from the cache and sends no request
 * of its own.
 */
function ProgramPicker({
  programs,
  slug,
  onChange,
}: {
  programs: ProgramSummary[];
  slug: string;
  onChange: (slug: string) => void;
}) {
  const { t } = useTranslation();
  const id = useId();
  const report = useSelfAssessmentReport(slug, { enabled: false });
  const listed = programs.some((program) => program.slug === slug);
  const reportLang = report.data?.locale;
  const lang =
    programs.find((program) => program.slug === slug)?.locale ?? reportLang;

  return (
    <div className="mt-6">
      <label
        htmlFor={id}
        className="block text-sm font-medium text-gray-900 dark:text-gray-100"
      >
        {t("reports.program")}
      </label>
      <select
        id={id}
        lang={lang}
        value={slug}
        onChange={(event) => onChange(event.target.value)}
        className="mt-1 block w-full max-w-md rounded-md border border-gray-500 bg-white px-3 py-2 text-sm text-gray-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500 dark:bg-gray-900 dark:text-gray-100"
      >
        {!listed && (
          <option value={slug} lang={reportLang}>
            {slug}
          </option>
        )}
        {programs.map((program) => (
          <option key={program.slug} value={program.slug} lang={program.locale}>
            {program.title}
          </option>
        ))}
      </select>
    </div>
  );
}

/**
 * `/admin/insights` (task 0014, step 9): the reports of a program for the
 * role `analyst`, one table per report. The program comes from the query
 * `?program=SLUG`, and without one from the first published program;
 * choosing another program writes its slug into the URL. Every report
 * counts anonymous rows or credentials, and a cell whose count lies below
 * the threshold of the server renders as "fewer than N".
 */
export function InsightsPage() {
  const { t } = useTranslation();
  const programs = usePrograms();
  const [searchParams, setSearchParams] = useSearchParams();
  const requested = searchParams.get("program");
  const slug = requested ?? programs.data?.[0]?.slug ?? null;
  // The list names the locale of a published program only; the sections
  // fall back to the locale of their report (`packLang`).
  const lang = programs.data?.find((program) => program.slug === slug)?.locale;

  let picker;
  if (programs.isPending) {
    picker = (
      <div className="mt-6">
        <LoadingStatus text={t("reports.programsLoading")} />
      </div>
    );
  } else if (programs.isError) {
    picker = (
      <p role="alert" className="mt-6 text-gray-700 dark:text-gray-300">
        {t("reports.programsFailed")}
      </p>
    );
  } else if (slug === null) {
    picker = (
      <p className="mt-6 text-gray-700 dark:text-gray-300">
        {t("reports.noPrograms")}
      </p>
    );
  } else {
    picker = (
      <ProgramPicker
        programs={programs.data}
        slug={slug}
        onChange={(next) => setSearchParams({ program: next })}
      />
    );
  }

  return (
    <section>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("reports.title")}
      </h1>
      <p className="mt-2 max-w-3xl text-gray-700 dark:text-gray-300">
        {t("reports.intro")}
      </p>
      {picker}
      {slug !== null && <Reports slug={slug} lang={lang} />}
    </section>
  );
}

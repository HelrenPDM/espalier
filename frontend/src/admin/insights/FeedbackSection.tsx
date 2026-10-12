import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import {
  useFeedbackReport,
  type FeedbackReport,
  type ReportCell,
} from "../../api/reports";
import { CountCell } from "./cells";
import { ReportSection } from "./ReportSection";
import {
  largestCount,
  packLang,
  TABLE_CLASSES,
  type SectionProps,
} from "./reportFormat";

type Question = FeedbackReport["questions"][number];

interface AnswerRow {
  key: string;
  label: ReactNode;
  cell: ReportCell;
}

/**
 * The rows of a question: one per option or scale value, and for a
 * free-text question one row with the number of its answers, whose cell is
 * suppressed while the answers stay hidden.
 */
function answerRows(
  question: Question,
  lang: string,
  freeTextLabel: string,
): AnswerRow[] {
  const rows: AnswerRow[] = question.choices.map((choice) => ({
    key: choice.key,
    label:
      choice.label === null ? (
        <span className="tabular-nums">{choice.key}</span>
      ) : (
        <span lang={lang}>{choice.label}</span>
      ),
    cell: choice.cell,
  }));
  const freeText = question.free_text;
  if (freeText !== null)
    rows.push({
      key: "free_text",
      label: freeTextLabel,
      cell:
        "suppressed" in freeText
          ? freeText
          : { count: freeText.count, value: freeText.count },
    });
  return rows;
}

/**
 * The feedback report: one group of rows per question of the feedback
 * station with the number of answers per option or scale value, and below
 * the table the free-text answers of each question that has reached the
 * threshold, in the random order of the server. The learners answer the
 * questions of the pack, so their answers carry the language of the
 * program.
 */
export function FeedbackSection({ slug, lang }: SectionProps) {
  const { t } = useTranslation();
  const query = useFeedbackReport(slug);
  const freeTextLabel = t("reports.feedback.freeText");

  return (
    <ReportSection
      title={t("reports.feedback.title")}
      description={t("reports.feedback.description")}
      query={query}
      isEmpty={(report) => report.questions.length === 0}
      empty={t("reports.feedback.empty")}
      after={(report) => {
        const listed = report.questions.flatMap((question) =>
          question.free_text !== null && "answers" in question.free_text
            ? [{ question, answers: question.free_text.answers }]
            : [],
        );
        if (listed.length === 0) return null;
        const textLang = packLang(lang, report);
        return (
          <div className="mt-6">
            <h3 className="text-lg font-semibold">
              {t("reports.feedback.freeTextTitle")}
            </h3>
            <p className="mt-1 text-sm text-gray-700 dark:text-gray-300">
              {t("reports.feedback.freeTextOrder")}
            </p>
            {listed.map(({ question, answers }) => (
              <div key={question.key} className="mt-4">
                <h4 lang={textLang} className="font-medium">
                  {question.label}
                </h4>
                <ul className="mt-2 space-y-2">
                  {answers.map((answer, index) => (
                    <li
                      // The answers have no identity of their own, and two
                      // people can write the same text.
                      key={index}
                      lang={textLang}
                      className="rounded-md border border-gray-200 px-3 py-2 text-sm whitespace-pre-line dark:border-gray-700"
                    >
                      {answer}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        );
      }}
    >
      {(report) => {
        const textLang = packLang(lang, report);
        const questions = report.questions.map((question) => ({
          question,
          rows: answerRows(question, textLang, freeTextLabel),
        }));
        const largest = largestCount(
          questions.flatMap(({ rows }) => rows.map((row) => row.cell)),
        );
        return (
          <>
            <thead>
              <tr>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("reports.feedback.question")}
                </th>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("reports.feedback.answer")}
                </th>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("reports.feedback.count")}
                </th>
              </tr>
            </thead>
            {questions.map(({ question, rows }) => (
              <tbody key={question.key}>
                {rows.map((row, index) => (
                  <tr key={row.key}>
                    {index === 0 && (
                      <th
                        scope="rowgroup"
                        rowSpan={rows.length}
                        className={`${TABLE_CLASSES.rowHeader} min-w-48`}
                      >
                        <span lang={textLang}>{question.label}</span>
                      </th>
                    )}
                    <th scope="row" className={TABLE_CLASSES.subRowHeader}>
                      {row.label}
                    </th>
                    <CountCell
                      cell={row.cell}
                      largest={largest}
                      size={report.min_group_size}
                    />
                  </tr>
                ))}
              </tbody>
            ))}
          </>
        );
      }}
    </ReportSection>
  );
}

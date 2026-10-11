import { useId, useRef, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { buttonClasses } from "../app/formStyles";
import { answerComplete } from "../player/items/answers";
import { useContentLang } from "../player/contentLang";
import { ItemByKind } from "../player/items/ItemByKind";
import type {
  Answer,
  AttemptResult,
  Exam,
  ExamOutcome,
  ModuleView,
} from "../player/runtime";
import { useCurrentPlayer } from "../player/usePlayer";

/**
 * An exam (README section 7, rule 5): every item in one form, submitted
 * through `Runtime.submitAssessment` once each item has an answer. The
 * result names the outcome with its reason and shows the feedback per
 * item, never a percentage, a rank or a comparison with other people. "New
 * attempt" clears the answers. The outcome goes to `examOutcomes`, which
 * keeps `passed` once an attempt has passed.
 */
export function ExamSection({
  exam,
  module,
}: {
  exam: Exam;
  module: ModuleView;
}) {
  const { t } = useTranslation();
  const { runtime, state, update } = useCurrentPlayer();
  const headingId = useId();
  const lang = useContentLang();
  const resultRef = useRef<HTMLDivElement>(null);
  const [answers, setAnswers] = useState<Record<string, Answer>>({});
  const [result, setResult] = useState<AttemptResult | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [failed, setFailed] = useState(false);

  const complete = exam.items.every((item) =>
    answerComplete(item, answers[item.id]),
  );
  const recorded: ExamOutcome | undefined = Object.hasOwn(
    state.examOutcomes,
    exam.id,
  )
    ? state.examOutcomes[exam.id]
    : undefined;

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!complete || submitting || result !== null) return;
    setSubmitting(true);
    setFailed(false);
    try {
      const attempt = await runtime.submitAssessment(exam.id, answers);
      setResult(attempt);
      update((current) => {
        const kept =
          current.examOutcomes[exam.id] === "passed"
            ? "passed"
            : attempt.outcome;
        if (
          Object.hasOwn(current.examOutcomes, exam.id) &&
          current.examOutcomes[exam.id] === kept
        )
          return current;
        return {
          ...current,
          examOutcomes: { ...current.examOutcomes, [exam.id]: kept },
        };
      });
      requestAnimationFrame(() => resultRef.current?.focus());
    } catch {
      setFailed(true);
    } finally {
      setSubmitting(false);
    }
  };

  const newAttempt = () => {
    setAnswers({});
    setResult(null);
    setFailed(false);
  };

  const correct =
    result?.results.filter((entry) => entry.correct === true).length ?? 0;

  return (
    <section
      aria-labelledby={headingId}
      className="rounded-lg border border-gray-300 p-4 dark:border-gray-600"
    >
      <h2
        id={headingId}
        lang={lang}
        className="text-xl font-semibold tracking-tight"
      >
        {exam.title}
      </h2>
      <p className="mt-2 text-sm text-gray-700 dark:text-gray-300">
        {t("exam.rule", { count: exam.max_wrong })}
        {exam.counts_for_credential && ` ${t("exam.countsForCredential")}`}
      </p>
      {result === null && recorded !== undefined && (
        <p className="mt-2 text-sm font-medium">
          {recorded === "passed"
            ? t("exam.alreadyPassed")
            : t("exam.lastFailed")}
        </p>
      )}

      <form onSubmit={(event) => void submit(event)} noValidate>
        <div className="mt-4 space-y-4">
          {exam.items.map((item) => (
            <ItemByKind
              key={item.id}
              item={item}
              moduleId={module.id}
              mode="exam"
              value={answers[item.id]}
              onChange={(value) =>
                setAnswers((current) => {
                  const next = { ...current };
                  if (value === undefined) delete next[item.id];
                  else next[item.id] = value;
                  return next;
                })
              }
              feedback={
                result?.results.find((entry) => entry.item_id === item.id) ??
                null
              }
              disabled={submitting || result !== null}
            />
          ))}
        </div>
        <div className="mt-4 flex flex-wrap gap-2">
          {result === null ? (
            <button
              type="submit"
              disabled={!complete || submitting}
              className={buttonClasses("primary")}
            >
              {submitting ? t("exam.submitting") : t("exam.submit")}
            </button>
          ) : (
            <button
              type="button"
              onClick={newAttempt}
              className={buttonClasses("secondary")}
            >
              {t("exam.newAttempt")}
            </button>
          )}
        </div>
      </form>

      <div
        ref={resultRef}
        role="status"
        tabIndex={-1}
        className="rounded-md focus:outline-2 focus:outline-offset-2 focus:outline-accent-500 [&:not(:empty)]:mt-4"
      >
        {result !== null && (
          <p className="font-semibold" data-outcome={result.outcome}>
            {result.outcome === "passed"
              ? t("exam.outcome.passed", {
                  correct,
                  total: result.results.length,
                })
              : result.outcome === "failed_core"
                ? t("exam.outcome.failedCore")
                : t("exam.outcome.failedErrors", {
                    wrong: result.wrong_count,
                    max: exam.max_wrong,
                  })}
          </p>
        )}
        {failed && (
          <p className="text-sm text-red-800 dark:text-red-300">
            {t("exam.failed")}
          </p>
        )}
      </div>
    </section>
  );
}

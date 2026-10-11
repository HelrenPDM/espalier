import { InformationCircleIcon } from "@heroicons/react/20/solid";
import { useId, type FormEvent, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { buttonClasses, linkClasses } from "../../app/formStyles";
import { jumpHandler } from "../jump";
import { useContentLang } from "../contentLang";
import { ObjectiveChips } from "../objectives/ObjectiveChips";
import { ProvenanceBadge } from "../ProvenanceBadge";
import type { Answer, ItemFeedback, ItemView } from "../runtime";
import { useCurrentPlayer } from "../usePlayer";
import { answerComplete } from "./answers";
import { FeedbackMark } from "./parts";

/** The props of every item component. */
export interface ItemProps {
  item: ItemView;
  /** The module of the station, which decides how the chips link. */
  moduleId: string;
  value: Answer | undefined;
  onChange: (value: Answer | undefined) => void;
  feedback: ItemFeedback | null;
  /**
   * `practice`: the frame holds its own form, submit button and status
   * region. `exam`: the frame sits in the form of the exam, which submits
   * every item at once.
   */
  mode: "practice" | "exam";
  /** Disables the inputs, for example while the exam is sent. */
  disabled?: boolean;
  onSubmit?: () => void;
  submitting?: boolean;
  /** Clears the answer and the feedback of a practice item. */
  onRetry?: () => void;
  /** The text of a failed submission. */
  error?: string | null;
  /** More content of the status region, such as the opened lessons. */
  notice?: ReactNode;
}

/** What an item component passes to its editor. */
export interface EditorContext {
  /** The inputs take no change: during and after a submission. */
  locked: boolean;
}

/**
 * The shared frame of the items (task 0012 step 8): the stem, the objective
 * chips, the provenance badge, the editor of the item kind, the submit
 * button and the feedback area. After a submission the area holds the
 * result, the referenced rules (links to `rule-<number>` in the rules
 * recap) and `notice`. In a practice item the area is a status region.
 */
export function ItemFrame({
  item,
  moduleId,
  value,
  feedback,
  mode,
  disabled = false,
  onSubmit,
  submitting = false,
  onRetry,
  error = null,
  notice,
  submitLabel,
  editor,
  after,
}: ItemProps & {
  submitLabel?: string;
  editor: (context: EditorContext) => ReactNode;
  /** Content below the form, such as the log of a checklist drill. */
  after?: ReactNode;
}) {
  const { t } = useTranslation();
  const { program } = useCurrentPlayer();
  const lang = useContentLang();
  const stemId = useId();
  const locked = disabled || submitting || feedback !== null;
  const complete = answerComplete(item, value);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (complete && !locked) onSubmit?.();
  };

  const result =
    feedback === null ? null : (
      <>
        {feedback.correct === null ? (
          <p className="inline-flex items-center gap-1 font-medium">
            <InformationCircleIcon aria-hidden="true" className="size-5" />
            {t("items.feedback.thanks")}
          </p>
        ) : (
          <p className="font-medium">
            <FeedbackMark correct={feedback.correct}>
              {feedback.correct
                ? t("items.feedback.correct")
                : t("items.feedback.wrong")}
            </FeedbackMark>
          </p>
        )}
        {feedback.rules.length > 0 && (
          <div className="mt-2 text-sm">
            <p>{t("items.rules")}</p>
            <ul className="mt-1 space-y-1">
              {feedback.rules.map((rule) => (
                <li key={rule.id}>
                  <a
                    href={`#rule-${rule.number}`}
                    onClick={jumpHandler(`rule-${rule.number}`)}
                    className={linkClasses}
                  >
                    {t("items.ruleLink", { number: rule.number })}{" "}
                    <span lang={lang}>{rule.statement}</span>
                  </a>
                </li>
              ))}
            </ul>
          </div>
        )}
      </>
    );

  const body = (
    <>
      <div className="mt-4">{editor({ locked })}</div>
      {mode === "practice" && (
        <div className="mt-4 flex flex-wrap gap-2">
          {feedback === null ? (
            <button
              type="submit"
              disabled={!complete || locked}
              className={buttonClasses("primary")}
            >
              {submitting
                ? t("items.submitting")
                : (submitLabel ?? t("items.submit"))}
            </button>
          ) : (
            onRetry && (
              <button
                type="button"
                onClick={onRetry}
                className={buttonClasses("secondary")}
              >
                {t("items.retry")}
              </button>
            )
          )}
        </div>
      )}
    </>
  );

  return (
    <div
      role="group"
      aria-labelledby={stemId}
      data-item-key={item.key}
      className="rounded-lg border border-gray-200 p-4 dark:border-gray-700"
    >
      <div className="flex flex-wrap items-start justify-between gap-2">
        <p id={stemId} lang={lang} className="min-w-0 flex-1 font-medium">
          {item.stem}
        </p>
        <ProvenanceBadge provenance={item.provenance} />
      </div>
      <ObjectiveChips
        objectiveKeys={item.objective_keys}
        program={program}
        moduleId={moduleId}
      />
      {mode === "practice" ? (
        <form onSubmit={submit} noValidate>
          {body}
        </form>
      ) : (
        body
      )}
      {mode === "practice" ? (
        // The region exists before the first answer, so the feedback is
        // announced.
        <div role="status" className="[&:not(:empty)]:mt-3">
          {result}
          {notice}
          {error && (
            <p className="text-sm text-red-800 dark:text-red-300">{error}</p>
          )}
        </div>
      ) : (
        result !== null && <div className="mt-3">{result}</div>
      )}
      {after}
    </div>
  );
}

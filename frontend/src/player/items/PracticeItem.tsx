import { useState } from "react";
import { useTranslation } from "react-i18next";
import { linkClasses } from "../../app/formStyles";
import { jumpHandler } from "../jump";
import { useContentLang } from "../contentLang";
import type { Answer, ItemFeedback, ItemView, Lesson } from "../runtime";
import { useRuntime } from "../RuntimeContext";
import { useTestNote } from "../testNotes";
import { ItemByKind } from "./ItemByKind";

/** The seconds of `Retry-After` of a 429 answer, when the error carries them. */
function rateLimited(error: unknown): number | null {
  if (typeof error !== "object" || error === null) return null;
  const { status, retryAfter } = error as {
    status?: unknown;
    retryAfter?: unknown;
  };
  if (status !== 429) return null;
  return typeof retryAfter === "number" ? retryAfter : 60;
}

/**
 * A practice item of a lesson: it submits through `Runtime.submitItem`,
 * shows the feedback and passes it to `onAnswered`, which records the item
 * and returns the lessons whose explanations it opened. The status region
 * of the item names those lessons. Each answer adds `item_answered` with
 * its correctness to the test session notes, and `explanation_revealed`
 * when it opened explanations.
 */
export function PracticeItem({
  item,
  moduleId,
  onAnswered,
}: {
  item: ItemView;
  moduleId: string;
  onAnswered: (item: ItemView, feedback: ItemFeedback) => Lesson[];
}) {
  const { t } = useTranslation();
  const runtime = useRuntime();
  const note = useTestNote();
  const lang = useContentLang();
  const [value, setValue] = useState<Answer | undefined>();
  const [feedback, setFeedback] = useState<ItemFeedback | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [revealed, setRevealed] = useState<Lesson[]>([]);

  const submit = async () => {
    if (value === undefined) return;
    setSubmitting(true);
    setError(null);
    try {
      const result = await runtime.submitItem(item.id, value);
      setFeedback(result);
      const lessons = onAnswered(item, result);
      setRevealed(lessons);
      note({ event: "item_answered", item: item.id, correct: result.correct });
      if (lessons.length > 0)
        note({ event: "explanation_revealed", item: item.id });
    } catch (failure) {
      const seconds = rateLimited(failure);
      setError(
        seconds === null
          ? t("items.submitFailed")
          : t("errors.tooManyAttempts", {
              minutes: Math.max(1, Math.ceil(seconds / 60)),
            }),
      );
    } finally {
      setSubmitting(false);
    }
  };

  const retry = () => {
    setValue(undefined);
    setFeedback(null);
    setRevealed([]);
    setError(null);
  };

  return (
    <ItemByKind
      item={item}
      moduleId={moduleId}
      mode="practice"
      value={value}
      onChange={setValue}
      feedback={feedback}
      submitting={submitting}
      onSubmit={() => void submit()}
      onRetry={retry}
      error={error}
      notice={
        revealed.length > 0 && (
          <ul className="mt-2 space-y-1 text-sm">
            {revealed.map((lesson) => (
              <li key={lesson.id}>
                {t("items.revealed")}{" "}
                <a
                  href={`#lesson-${lesson.id}`}
                  lang={lang}
                  onClick={jumpHandler(`lesson-${lesson.id}`)}
                  className={linkClasses}
                >
                  {lesson.title}
                </a>
              </li>
            ))}
          </ul>
        )
      }
    />
  );
}

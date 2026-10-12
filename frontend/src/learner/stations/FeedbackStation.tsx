import { Description, Label, Radio, RadioGroup } from "@headlessui/react";
import { useId, useRef, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { AlertRegion } from "../../app/forms";
import { buttonClasses, FOCUS_RING } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import {
  useParticipation,
  useSubmitFeedback,
  type FeedbackAnswers,
} from "../../api/insights";
import { useSession } from "../../auth/SessionProvider";
import { useContentLang } from "../../player/contentLang";
import { Markdown } from "../../player/Markdown";
import type { Station } from "../../player/runtime";
import { useCurrentPlayer } from "../../player/usePlayer";
import { useSaveErrorText } from "./saveError";

type Question = Station["questions"][number];
type Answer = string | number;

/** The most characters of a free-text answer, as the server accepts them. */
const FREE_TEXT_LENGTH = 2000;

const SCALE = [1, 2, 3, 4, 5] as const;

const RADIO_CLASSES = `group flex min-h-6 cursor-pointer items-center gap-2 rounded-md px-2 py-1 ${FOCUS_RING}`;
const RADIO_MARK =
  "size-4 shrink-0 rounded-full border border-gray-500 group-data-checked:border-4 group-data-checked:border-accent-600 dark:border-gray-400 dark:group-data-checked:border-accent-100";

/**
 * A `single_choice` question as a radio group, named by its label (pack
 * text). Headless UI 2.2.10 names the group from its own `Label`.
 */
function SingleChoice({
  question,
  value,
  onChange,
}: {
  question: Question;
  value: Answer | undefined;
  onChange: (value: string) => void;
}) {
  const lang = useContentLang();
  return (
    <RadioGroup
      value={typeof value === "string" ? value : null}
      onChange={(key: string | null) => {
        if (key !== null) onChange(key);
      }}
      data-question={question.key}
    >
      <Label lang={lang} className="font-semibold">
        {question.label}
      </Label>
      <div className="mt-2 space-y-1">
        {question.options.map((option) => (
          <Radio key={option.key} value={option.key} className={RADIO_CLASSES}>
            <span aria-hidden="true" className={RADIO_MARK} />
            <span lang={lang}>{option.label}</span>
          </Radio>
        ))}
      </div>
    </RadioGroup>
  );
}

/** A `scale` question as a radio group of the values 1 to 5. */
function Scale({
  question,
  value,
  onChange,
}: {
  question: Question;
  value: Answer | undefined;
  onChange: (value: number) => void;
}) {
  const { t } = useTranslation();
  const lang = useContentLang();
  return (
    <RadioGroup
      value={typeof value === "number" ? value : null}
      onChange={(scale: number | null) => {
        if (scale !== null) onChange(scale);
      }}
      data-question={question.key}
    >
      <Label lang={lang} className="font-semibold">
        {question.label}
      </Label>
      <Description
        as="p"
        className="mt-1 text-sm text-gray-700 dark:text-gray-300"
      >
        {t("feedbackStation.scaleHint")}
      </Description>
      <div className="mt-2 flex flex-wrap gap-2">
        {SCALE.map((scale) => (
          <Radio
            key={scale}
            value={scale}
            className={`flex min-h-6 min-w-10 cursor-pointer items-center justify-center rounded-md border border-gray-500 px-3 py-1 text-sm font-medium text-gray-900 data-checked:border-accent-600 data-checked:bg-accent-600 data-checked:text-white dark:text-gray-100 dark:data-checked:border-accent-100 dark:data-checked:bg-accent-100 dark:data-checked:text-gray-900 ${FOCUS_RING}`}
          >
            {scale}
          </Radio>
        ))}
      </div>
    </RadioGroup>
  );
}

/** A `free_text` question as a text area of at most 2,000 characters. */
function FreeText({
  question,
  value,
  onChange,
}: {
  question: Question;
  value: Answer | undefined;
  onChange: (value: string) => void;
}) {
  const { t } = useTranslation();
  const lang = useContentLang();
  const id = useId();
  const hintId = `${id}-hint`;
  return (
    <div data-question={question.key}>
      <label htmlFor={id} lang={lang} className="block font-semibold">
        {question.label}
      </label>
      <p id={hintId} className="mt-1 text-sm text-gray-700 dark:text-gray-300">
        {t("feedbackStation.freeTextHint")}
      </p>
      <textarea
        id={id}
        rows={4}
        maxLength={FREE_TEXT_LENGTH}
        value={typeof value === "string" ? value : ""}
        onChange={(event) => onChange(event.target.value)}
        aria-describedby={hintId}
        className={`mt-2 block w-full rounded-md border border-gray-500 bg-white px-3 py-2 text-gray-900 dark:bg-gray-900 dark:text-gray-100 ${FOCUS_RING}`}
      />
    </div>
  );
}

/**
 * The answers to send: the answered questions only, with free text
 * trimmed and left out when it is empty.
 */
function answersToSend(
  questions: Question[],
  answers: ReadonlyMap<string, Answer>,
): FeedbackAnswers {
  const entries: [string, Answer][] = [];
  for (const question of questions) {
    const answer = answers.get(question.key);
    if (answer === undefined) continue;
    if (question.kind === "free_text") {
      const text = typeof answer === "string" ? answer.trim() : "";
      if (text !== "") entries.push([question.key, text]);
    } else {
      entries.push([question.key, answer]);
    }
  }
  return Object.fromEntries(entries);
}

/**
 * The feedback station (task 0014, step 7): the station intro and its
 * questions, single choice and the scale from 1 to 5 as radio groups and
 * free text as a text area. Free-text questions appear only while
 * `flags.feedbackFreeText` (`FEEDBACK_FREE_TEXT`) is true. The learner
 * sends the answered questions once; afterwards, and on a later visit
 * whose participation says the feedback was sent, the station thanks the
 * learner instead of showing the form. When the server answers
 * `already_recorded` because feedback was sent before, for instance from
 * another tab while the participation was stale or failed to load, the
 * station says that the feedback was already sent and does not claim that
 * this submission was recorded.
 */
export function FeedbackStation({ station }: { station: Station }) {
  const { t } = useTranslation();
  const { program } = useCurrentPlayer();
  const { flags } = useSession();
  const participation = useParticipation(program.slug);
  const submit = useSubmitFeedback(program.slug);
  const saveErrorText = useSaveErrorText();
  const thanksRef = useRef<HTMLParagraphElement>(null);
  const [answers, setAnswers] = useState<ReadonlyMap<string, Answer>>(
    () => new Map(),
  );
  const [sending, setSending] = useState(false);
  // The outcome of this visit's submission: recorded now, or recorded
  // before according to the server.
  const [sent, setSent] = useState<"recorded" | "already" | null>(null);
  const [failure, setFailure] = useState<unknown>(null);

  const questions = station.questions.filter(
    (question) => question.kind !== "free_text" || flags.feedbackFreeText,
  );
  const toSend = answersToSend(questions, answers);
  const answered = Object.keys(toSend).length;

  const answer = (key: string, value: Answer) =>
    setAnswers((current) => new Map(current).set(key, value));

  const send = async (event: FormEvent) => {
    event.preventDefault();
    if (answered === 0 || sending) return;
    setSending(true);
    setFailure(null);
    try {
      const result = await submit.mutateAsync(toSend);
      setSent(result.already_recorded ? "already" : "recorded");
      requestAnimationFrame(() => thanksRef.current?.focus());
    } catch (error) {
      setFailure(error);
    } finally {
      setSending(false);
    }
  };

  // While the answers are sent, the updated participation already says
  // "sent"; the form stays until the outcome of this submission is known.
  const done =
    sent !== null || (!sending && participation.data?.feedback === true);

  return (
    <div className="space-y-6">
      {station.intro && <Markdown>{station.intro}</Markdown>}
      {participation.isPending ? (
        <LoadingStatus text={t("feedbackStation.loading")} />
      ) : done ? (
        <p
          ref={thanksRef}
          tabIndex={-1}
          data-feedback="sent"
          className="rounded-md font-medium focus:outline-2 focus:outline-offset-2 focus:outline-accent-500"
        >
          {sent === "recorded"
            ? t("feedbackStation.thanks")
            : t("feedbackStation.alreadySent")}
        </p>
      ) : questions.length === 0 ? (
        <p className="text-gray-700 dark:text-gray-300">
          {t("feedbackStation.none")}
        </p>
      ) : (
        <form onSubmit={(event) => void send(event)} noValidate>
          <p className="text-sm text-gray-700 dark:text-gray-300">
            {t("feedbackStation.anonymous")}
          </p>
          {participation.isError && (
            <p role="alert" className="mt-2 text-gray-700 dark:text-gray-300">
              {t("feedbackStation.loadFailed")}
            </p>
          )}
          <div className="mt-6 space-y-6">
            {questions.map((question) => {
              const value = answers.get(question.key);
              switch (question.kind) {
                case "single_choice":
                  return (
                    <SingleChoice
                      key={question.key}
                      question={question}
                      value={value}
                      onChange={(key) => answer(question.key, key)}
                    />
                  );
                case "scale":
                  return (
                    <Scale
                      key={question.key}
                      question={question}
                      value={value}
                      onChange={(scale) => answer(question.key, scale)}
                    />
                  );
                case "free_text":
                  return (
                    <FreeText
                      key={question.key}
                      question={question}
                      value={value}
                      onChange={(text) => answer(question.key, text)}
                    />
                  );
              }
            })}
          </div>
          <p className="mt-6 text-sm text-gray-700 dark:text-gray-300">
            {t("feedbackStation.optional")}
          </p>
          <div className="mt-2 space-y-2">
            <button
              type="submit"
              disabled={answered === 0 || sending}
              className={buttonClasses("primary")}
            >
              {sending
                ? t("feedbackStation.submitting")
                : t("feedbackStation.submit")}
            </button>
            <AlertRegion>
              {failure !== null &&
                saveErrorText(failure, t("feedbackStation.submitFailed"))}
            </AlertRegion>
          </div>
        </form>
      )}
    </div>
  );
}

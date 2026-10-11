import { Field, Label, Radio, RadioGroup } from "@headlessui/react";
import { useTranslation } from "react-i18next";
import { FOCUS_RING } from "../../app/formStyles";
import type { ItemFeedback, ItemView } from "../runtime";
import { feedbackFor } from "./answers";
import { FeedbackMark, FeedbackText } from "./parts";

/**
 * The mark and the feedback of an option after a submission: the correct
 * options and a chosen wrong option carry a mark, and every option shows
 * its feedback.
 */
function OptionFeedback({
  feedback,
  optionKey,
}: {
  feedback: ItemFeedback | null;
  optionKey: string;
}) {
  const { t } = useTranslation();
  const entry = feedbackFor(feedback, optionKey);
  if (entry === undefined) return null;
  return (
    <div className="mt-1">
      {entry.correct ? (
        <FeedbackMark correct>{t("items.option.correct")}</FeedbackMark>
      ) : (
        entry.selected && (
          <FeedbackMark correct={false}>
            {t("items.option.chosenWrong")}
          </FeedbackMark>
        )
      )}
      <FeedbackText text={entry.feedback} />
    </div>
  );
}

/**
 * One choice among the options, with Headless UI `RadioGroup`, for a single
 * choice and for a poll; the stem names the group. A poll has no correct option, so it shows no
 * marks.
 */
export function RadioOptions({
  item,
  selected,
  onSelect,
  feedback,
  locked,
  withFeedback,
}: {
  item: ItemView;
  selected: string | undefined;
  onSelect: (key: string) => void;
  feedback: ItemFeedback | null;
  locked: boolean;
  withFeedback: boolean;
}) {
  return (
    <RadioGroup
      value={selected ?? null}
      onChange={(key: string | null) => {
        if (key !== null) onSelect(key);
      }}
      disabled={locked}
      // Headless UI 2.2.10 sets `aria-labelledby` of the group from its own
      // labels and drops a given one, so the stem names the group through
      // `aria-label`.
      aria-label={item.stem}
      className="space-y-2"
    >
      {item.options.map((option) => (
        <Field key={option.key} disabled={locked}>
          <div className="flex items-start gap-3">
            <Radio
              value={option.key}
              className={`group mt-0.5 flex size-5 shrink-0 cursor-pointer items-center justify-center rounded-full border-2 border-gray-500 bg-white data-checked:border-accent-600 data-disabled:cursor-not-allowed dark:border-gray-400 dark:bg-gray-900 dark:data-checked:border-accent-100 ${FOCUS_RING}`}
            >
              <span className="invisible size-2.5 rounded-full bg-accent-600 group-data-checked:visible dark:bg-accent-100" />
            </Radio>
            <div className="min-w-0">
              <Label className="cursor-pointer data-disabled:cursor-default">
                {option.label}
              </Label>
              {withFeedback && (
                <OptionFeedback feedback={feedback} optionKey={option.key} />
              )}
            </div>
          </div>
        </Field>
      ))}
    </RadioGroup>
  );
}

/** Several choices among the options, with checkboxes. */
export function CheckboxOptions({
  item,
  selected,
  onToggle,
  feedback,
  locked,
}: {
  item: ItemView;
  selected: string[];
  onToggle: (key: string, checked: boolean) => void;
  feedback: ItemFeedback | null;
  locked: boolean;
}) {
  return (
    <ul className="space-y-2">
      {item.options.map((option) => {
        const id = `${item.id}-${option.key}`;
        return (
          <li key={option.key} className="flex items-start gap-3">
            <input
              id={id}
              type="checkbox"
              checked={selected.includes(option.key)}
              disabled={locked}
              onChange={(event) => onToggle(option.key, event.target.checked)}
              className={`mt-1 size-4 shrink-0 accent-accent-600 ${FOCUS_RING}`}
            />
            <div className="min-w-0">
              <label htmlFor={id}>{option.label}</label>
              <OptionFeedback feedback={feedback} optionKey={option.key} />
            </div>
          </li>
        );
      })}
    </ul>
  );
}

import { useTranslation } from "react-i18next";
import { FOCUS_RING } from "../../app/formStyles";
import { feedbackFor } from "./answers";
import { ItemFrame, type ItemProps } from "./ItemFrame";
import { FeedbackMark, FeedbackText } from "./parts";

export const SELECT_CLASSES = `mt-1 block w-full min-w-0 rounded-md border border-gray-500 bg-white px-3 py-2 text-sm text-gray-900 disabled:cursor-not-allowed disabled:opacity-70 dark:bg-gray-900 dark:text-gray-100 ${FOCUS_RING}`;

/**
 * One select per slot and a live preview that assembles the chosen lines in
 * slot order; after the submission each slot shows its feedback.
 */
export function SlotBuilderItem(props: ItemProps) {
  const { t } = useTranslation();
  const { item, value, onChange, feedback } = props;
  const slots = value?.slots ?? {};
  const lines = item.slots.flatMap((slot) => {
    const option = slot.options.find((entry) => entry.key === slots[slot.key]);
    return option === undefined ? [] : [option.label];
  });

  return (
    <ItemFrame
      {...props}
      editor={({ locked }) => (
        <div className="space-y-4">
          {item.slots.map((slot) => {
            const id = `${item.id}-slot-${slot.key}`;
            const entry = feedbackFor(feedback, slot.key);
            return (
              <div key={slot.key}>
                <label htmlFor={id} className="text-sm font-medium">
                  {slot.label}
                </label>
                <select
                  id={id}
                  value={slots[slot.key] ?? ""}
                  disabled={locked}
                  onChange={(event) => {
                    const next = { ...slots };
                    if (event.target.value === "") delete next[slot.key];
                    else next[slot.key] = event.target.value;
                    onChange(
                      Object.keys(next).length > 0
                        ? { slots: next }
                        : undefined,
                    );
                  }}
                  className={SELECT_CLASSES}
                >
                  <option value="">{t("items.choose")}</option>
                  {slot.options.map((option) => (
                    <option key={option.key} value={option.key}>
                      {option.label}
                    </option>
                  ))}
                </select>
                {entry && (
                  <div className="mt-1">
                    <FeedbackMark correct={entry.correct}>
                      {entry.correct
                        ? t("items.slot.correct")
                        : t("items.slot.wrong")}
                    </FeedbackMark>
                    <FeedbackText text={entry.feedback} />
                  </div>
                )}
              </div>
            );
          })}
          <div>
            <p className="text-sm font-medium">{t("items.slot.preview")}</p>
            <div className="mt-1 rounded-md border border-gray-200 bg-gray-50 px-3 py-2 text-sm dark:border-gray-700 dark:bg-gray-900">
              {lines.length === 0 ? (
                <p className="text-gray-700 dark:text-gray-300">
                  {t("items.slot.previewEmpty")}
                </p>
              ) : (
                lines.map((line, index) => (
                  <p key={index} className="break-words">
                    {line}
                  </p>
                ))
              )}
            </div>
          </div>
        </div>
      )}
    />
  );
}

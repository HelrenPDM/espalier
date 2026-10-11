import { useTranslation } from "react-i18next";
import { feedbackFor } from "./answers";
import { useContentLang } from "../contentLang";
import { ItemFrame, type ItemProps } from "./ItemFrame";
import { FeedbackMark, FeedbackText } from "./parts";
import { SELECT_CLASSES } from "./SlotBuilderItem";

/** One category select per case; after the submission each case shows its feedback. */
export function ClassificationItem(props: ItemProps) {
  const { t } = useTranslation();
  const { item, value, onChange, feedback } = props;
  const lang = useContentLang();
  const cases = value?.cases ?? {};
  const categoryLabel = (key: string | null | undefined) =>
    item.categories.find((category) => category.key === key)?.label;

  return (
    <ItemFrame
      {...props}
      editor={({ locked }) => (
        <ul className="space-y-4">
          {item.cases.map((entry) => {
            const id = `${item.id}-case-${entry.key}`;
            const result = feedbackFor(feedback, entry.key);
            const expected = categoryLabel(result?.expected);
            return (
              <li key={entry.key}>
                <label htmlFor={id} lang={lang} className="block text-sm">
                  {entry.text}
                </label>
                <select
                  id={id}
                  lang={lang}
                  value={cases[entry.key] ?? ""}
                  disabled={locked}
                  onChange={(event) => {
                    const next = { ...cases };
                    if (event.target.value === "") delete next[entry.key];
                    else next[entry.key] = event.target.value;
                    onChange(
                      Object.keys(next).length > 0
                        ? { cases: next }
                        : undefined,
                    );
                  }}
                  className={SELECT_CLASSES}
                >
                  <option value="">{t("items.choose")}</option>
                  {item.categories.map((category) => (
                    <option key={category.key} value={category.key}>
                      {category.label}
                    </option>
                  ))}
                </select>
                {result && (
                  <div className="mt-1">
                    <FeedbackMark correct={result.correct}>
                      {result.correct ? (
                        t("items.case.correct")
                      ) : expected ? (
                        <>
                          {t("items.case.expected")}{" "}
                          <span lang={lang}>{expected}</span>
                        </>
                      ) : (
                        t("items.case.wrong")
                      )}
                    </FeedbackMark>
                    <FeedbackText text={result.feedback} />
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      )}
    />
  );
}

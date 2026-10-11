import { useTranslation } from "react-i18next";
import { RadioOptions } from "./ChoiceOptions";
import { ItemFrame, type ItemProps } from "./ItemFrame";

/**
 * Options without correctness; after the submission the frame shows a
 * thank-you text.
 */
export function PollItem(props: ItemProps) {
  const { t } = useTranslation();
  const { item, value, onChange, feedback } = props;
  return (
    <ItemFrame
      {...props}
      submitLabel={t("items.poll.submit")}
      editor={({ locked }) => (
        <RadioOptions
          item={item}
          selected={value?.options?.[0]}
          onSelect={(key) => onChange({ options: [key] })}
          feedback={feedback}
          locked={locked}
          withFeedback={false}
        />
      )}
    />
  );
}

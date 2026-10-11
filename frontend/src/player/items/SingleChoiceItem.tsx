import { RadioOptions } from "./ChoiceOptions";
import { ItemFrame, type ItemProps } from "./ItemFrame";

/** One correct option, chosen with Headless UI `RadioGroup`. */
export function SingleChoiceItem(props: ItemProps) {
  const { item, value, onChange, feedback } = props;
  return (
    <ItemFrame
      {...props}
      editor={({ locked }) => (
        <RadioOptions
          item={item}
          selected={value?.options?.[0]}
          onSelect={(key) => onChange({ options: [key] })}
          feedback={feedback}
          locked={locked}
          withFeedback
        />
      )}
    />
  );
}

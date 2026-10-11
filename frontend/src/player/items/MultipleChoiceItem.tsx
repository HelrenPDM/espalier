import { CheckboxOptions } from "./ChoiceOptions";
import { ItemFrame, type ItemProps } from "./ItemFrame";

/** Every correct option, chosen with checkboxes. */
export function MultipleChoiceItem(props: ItemProps) {
  const { item, value, onChange, feedback } = props;
  const selected = value?.options ?? [];
  return (
    <ItemFrame
      {...props}
      editor={({ locked }) => (
        <CheckboxOptions
          item={item}
          selected={selected}
          onToggle={(key, checked) => {
            const options = checked
              ? [...selected.filter((entry) => entry !== key), key]
              : selected.filter((entry) => entry !== key);
            onChange(options.length > 0 ? { options } : undefined);
          }}
          feedback={feedback}
          locked={locked}
        />
      )}
    />
  );
}

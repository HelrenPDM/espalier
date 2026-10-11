import { ChecklistDrillItem } from "./ChecklistDrillItem";
import { ClassificationItem } from "./ClassificationItem";
import type { ItemProps } from "./ItemFrame";
import { MultipleChoiceItem } from "./MultipleChoiceItem";
import { PollItem } from "./PollItem";
import { SingleChoiceItem } from "./SingleChoiceItem";
import { SlotBuilderItem } from "./SlotBuilderItem";

/** Renders an item by its kind. */
export function ItemByKind(props: ItemProps) {
  switch (props.item.kind) {
    case "single_choice":
      return <SingleChoiceItem {...props} />;
    case "multiple_choice":
      return <MultipleChoiceItem {...props} />;
    case "slot_builder":
      return <SlotBuilderItem {...props} />;
    case "classification":
      return <ClassificationItem {...props} />;
    case "checklist_drill":
      return <ChecklistDrillItem {...props} />;
    case "poll":
      return <PollItem {...props} />;
  }
}

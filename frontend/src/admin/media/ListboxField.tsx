import {
  Description,
  Field,
  Label,
  Listbox,
  ListboxButton,
  ListboxOption,
  ListboxOptions,
} from "@headlessui/react";
import { ChevronUpDownIcon } from "@heroicons/react/20/solid";
import type { ReactNode } from "react";
import { FOCUS_RING } from "../../app/formStyles";

/** An option of `ListboxField`: its value, its text and an optional line below. */
export interface ListboxChoice {
  value: string;
  label: string;
  detail?: ReactNode;
}

/**
 * A choice from a list in a Headless UI `Listbox` (README section 9) with a
 * visible label and an error connected to the button. The options render
 * below the button inside the form, so a dialog around it keeps the focus.
 * Labels render as text.
 */
export function ListboxField({
  label,
  placeholder,
  choices,
  value,
  onChange,
  error = null,
}: {
  label: string;
  /** The text of the button while nothing is chosen. */
  placeholder: string;
  choices: readonly ListboxChoice[];
  value: string | null;
  onChange: (value: string) => void;
  error?: string | null;
}) {
  const selected = choices.find((choice) => choice.value === value) ?? null;
  return (
    <Field className="relative">
      <Label className="block text-sm font-medium text-gray-900 dark:text-gray-100">
        {label}
      </Label>
      <Listbox
        value={value}
        onChange={(next: string | null) => {
          if (next !== null) onChange(next);
        }}
      >
        {/* A button takes no aria-invalid (ARIA 1.2); the error is its
            description through the Field, and the border marks it. */}
        <ListboxButton
          className={`mt-1 flex w-full items-center justify-between gap-2 rounded-md border bg-white px-3 py-2 text-left text-sm text-gray-900 dark:bg-gray-900 dark:text-gray-100 ${
            error === null
              ? "border-gray-500"
              : "border-red-700 dark:border-red-400"
          } ${FOCUS_RING}`}
        >
          <span className="min-w-0 truncate">
            {selected === null ? placeholder : selected.label}
          </span>
          <ChevronUpDownIcon aria-hidden="true" className="size-5 shrink-0" />
        </ListboxButton>
        <ListboxOptions
          modal={false}
          className="absolute z-10 mt-1 max-h-60 w-full overflow-auto rounded-md border border-gray-200 bg-white py-1 text-sm shadow-lg focus:outline-none dark:border-gray-700 dark:bg-gray-900"
        >
          {choices.map((choice) => (
            <ListboxOption
              key={choice.value}
              value={choice.value}
              className="cursor-default px-3 py-2 break-words text-gray-900 data-focus:bg-accent-50 data-selected:font-semibold dark:text-gray-100 dark:data-focus:bg-accent-700"
            >
              <span className="block">{choice.label}</span>
              {choice.detail !== undefined && (
                <span className="block text-xs font-normal text-gray-700 dark:text-gray-300">
                  {choice.detail}
                </span>
              )}
            </ListboxOption>
          ))}
        </ListboxOptions>
      </Listbox>
      {error !== null && (
        <Description className="mt-1 text-sm text-red-700 dark:text-red-300">
          {error}
        </Description>
      )}
    </Field>
  );
}

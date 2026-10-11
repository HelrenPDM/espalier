import {
  Disclosure,
  DisclosureButton,
  DisclosurePanel,
} from "@headlessui/react";
import { ChevronDownIcon } from "@heroicons/react/20/solid";
import { useEffect, useRef } from "react";
import { useTranslation } from "react-i18next";
import { FOCUS_RING } from "../../app/formStyles";
import { Citations } from "../Citations";
import { Markdown } from "../Markdown";
import { ProvenanceBadge } from "../ProvenanceBadge";
import type { Block } from "../runtime";

/** Calls `onChange` when `open` changes after the first render. */
function OpenWatcher({
  open,
  onChange,
}: {
  open: boolean;
  onChange: (open: boolean) => void;
}) {
  const last = useRef(open);
  useEffect(() => {
    if (last.current === open) return;
    last.current = open;
    onChange(open);
  }, [open, onChange]);
  return null;
}

/**
 * A collapsible explanation (README section 7, rule 2) with Headless UI
 * `Disclosure`. Headless UI 2.2.10 offers `defaultOpen` and no controlled
 * `open`, so the lesson gives the block a `key` that changes with each
 * reveal and each path change, and the new start state applies.
 */
export function ExplanationBlock({
  block,
  defaultOpen,
  onToggle,
}: {
  block: Block;
  defaultOpen: boolean;
  onToggle: (open: boolean) => void;
}) {
  const { t } = useTranslation();
  return (
    <Disclosure
      as="div"
      defaultOpen={defaultOpen}
      data-block-kind={block.kind}
      className="rounded-md border border-gray-300 bg-gray-50 dark:border-gray-700 dark:bg-gray-900"
    >
      {({ open }) => (
        <>
          <OpenWatcher open={open} onChange={onToggle} />
          <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-2">
            <DisclosureButton
              className={`flex min-h-6 items-center gap-1 rounded-md text-sm font-semibold text-gray-900 hover:text-accent-700 dark:text-gray-100 dark:hover:text-accent-100 ${FOCUS_RING}`}
            >
              <ChevronDownIcon
                aria-hidden="true"
                className={`size-5 transition-transform ${open ? "rotate-180" : ""}`}
              />
              {t("blocks.explanation")}
            </DisclosureButton>
            <ProvenanceBadge provenance={block.provenance} />
          </div>
          <DisclosurePanel className="px-4 pb-4">
            <Markdown>{block.body}</Markdown>
            <Citations citations={block.citations} />
          </DisclosurePanel>
        </>
      )}
    </Disclosure>
  );
}

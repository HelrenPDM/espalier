import { Description, Label, Radio, RadioGroup } from "@headlessui/react";
import { useTranslation } from "react-i18next";
import { FOCUS_RING } from "../app/formStyles";
import type { Path } from "./runtime";
import { useCurrentPlayer } from "./usePlayer";

const PATHS: Path[] = ["short", "full"];

/**
 * The current path with a switch between short and full and a short
 * explanation of the difference (README section 7, rules 1 and 2).
 * Switching passes the new path through `saveState`, so the switch works
 * with every runtime; `PlatformRuntime` then marks the choice as manual.
 */
export function PathSwitch() {
  const { t } = useTranslation();
  const { state, update } = useCurrentPlayer();

  return (
    <div className="rounded-lg border border-gray-200 p-4 dark:border-gray-700">
      {/* Headless UI 2.2.10 names and describes the group from its own
          Label and Description and drops given ARIA ids. */}
      <RadioGroup
        value={state.path}
        onChange={(path: Path) =>
          update((current) =>
            current.path === path ? current : { ...current, path },
          )
        }
      >
        <div className="flex flex-wrap items-center gap-2">
          <Label className="mr-2 font-semibold">{t("path.label")}</Label>
          {PATHS.map((path) => (
            <Radio
              key={path}
              value={path}
              className={`min-h-6 cursor-pointer rounded-full border border-gray-500 px-3 py-1 text-sm font-medium text-gray-900 data-checked:border-accent-600 data-checked:bg-accent-600 data-checked:text-white dark:text-gray-100 dark:data-checked:border-accent-100 dark:data-checked:bg-accent-100 dark:data-checked:text-gray-900 ${FOCUS_RING}`}
            >
              {t(`path.${path}`)}
            </Radio>
          ))}
        </div>
        <Description
          as="p"
          className="mt-2 text-sm text-gray-700 dark:text-gray-300"
        >
          {t("path.explanation")}
        </Description>
      </RadioGroup>
    </div>
  );
}

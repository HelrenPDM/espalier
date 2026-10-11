import {
  ComputerDesktopIcon,
  MoonIcon,
  SunIcon,
} from "@heroicons/react/24/outline";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
  applyTheme,
  nextTheme,
  readTheme,
  storeTheme,
  type ThemeSetting,
} from "./theme";

const ICONS = {
  system: ComputerDesktopIcon,
  light: SunIcon,
  dark: MoonIcon,
} as const;

/** Cycles the theme setting through system, light and dark. */
export function ThemeToggle() {
  const { t } = useTranslation();
  const [setting, setSetting] = useState<ThemeSetting>(readTheme);
  const Icon = ICONS[setting];
  const label = t("theme.toggle", { value: t(`theme.${setting}`) });

  const cycle = () => {
    const next = nextTheme(setting);
    storeTheme(next);
    applyTheme(next);
    setSetting(next);
  };

  return (
    <button
      type="button"
      onClick={cycle}
      title={label}
      className="rounded-md p-2 text-gray-700 hover:bg-gray-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500 dark:text-gray-200 dark:hover:bg-gray-800"
    >
      <Icon aria-hidden="true" className="size-5" />
      <span className="sr-only">{label}</span>
    </button>
  );
}

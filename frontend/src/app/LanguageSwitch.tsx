import { useId } from "react";
import { useTranslation } from "react-i18next";
import { languages, type Language } from "../i18n";

// Each language appears under its own name, so a reader finds it in either
// UI language.
const NAMES: Record<Language, string> = { en: "English", de: "Deutsch" };

export function LanguageSwitch() {
  const { t, i18n } = useTranslation();
  const id = useId();
  const current =
    languages.find((language) => language === i18n.resolvedLanguage) ?? "en";

  return (
    <div>
      <label htmlFor={id} className="sr-only">
        {t("layout.language")}
      </label>
      <select
        id={id}
        value={current}
        onChange={(event) => void i18n.changeLanguage(event.target.value)}
        className="rounded-md border border-gray-500 bg-white px-2 py-1.5 text-sm text-gray-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500 dark:bg-gray-900 dark:text-gray-100"
      >
        {languages.map((language) => (
          <option key={language} value={language} lang={language}>
            {NAMES[language]}
          </option>
        ))}
      </select>
    </div>
  );
}

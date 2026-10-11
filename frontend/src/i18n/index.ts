import i18n from "i18next";
import LanguageDetector from "i18next-browser-languagedetector";
import { initReactI18next } from "react-i18next";
import de from "./de.json";
import en from "./en.json";

export const languages = ["en", "de"] as const;
export type Language = (typeof languages)[number];

// The detector reads the language from localStorage (key `i18nextLng`, its
// default) and then from the browser, and stores a choice under that key.
void i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: { en: { translation: en }, de: { translation: de } },
    supportedLngs: languages,
    fallbackLng: "en",
    detection: {
      order: ["localStorage", "navigator"],
      caches: ["localStorage"],
    },
    // React escapes every value it renders.
    interpolation: { escapeValue: false },
    initAsync: false,
  });

const setDocumentLanguage = () => {
  document.documentElement.lang = i18n.resolvedLanguage ?? "en";
};
setDocumentLanguage();
i18n.on("languageChanged", setDocumentLanguage);

export default i18n;

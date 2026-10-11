import "i18next";
import type en from "./en.json";

// Typed keys: t() accepts only the keys of en.json.
declare module "i18next" {
  interface CustomTypeOptions {
    resources: { translation: typeof en };
  }
}

import { expect } from "vitest";
import { axe } from "vitest-axe";
import i18n from "../i18n";

/**
 * Runs axe three times on `container` (task 0011 step 17): in light mode,
 * with the `dark` class on `<html>`, and in German. It switches back to
 * light mode and English afterwards. A dialog renders in a portal, so its
 * tests pass `document.body`.
 */
export async function expectNoAxeViolations(container: Element) {
  const root = document.documentElement;
  try {
    root.classList.remove("dark");
    expect(await axe(container)).toHaveNoViolations();
    root.classList.add("dark");
    expect(await axe(container)).toHaveNoViolations();
    root.classList.remove("dark");
    await i18n.changeLanguage("de");
    expect(await axe(container)).toHaveNoViolations();
  } finally {
    root.classList.remove("dark");
    await i18n.changeLanguage("en");
  }
}

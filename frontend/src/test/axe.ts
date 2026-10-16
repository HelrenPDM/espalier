import { expect } from "vitest";
import { axe } from "vitest-axe";
import i18n from "../i18n";

/** The run options of axe-core. */
type RunOptions = NonNullable<Parameters<typeof axe>[1]>;

/**
 * Runs axe three times on `container` (task 0011 step 17): in light mode,
 * with the `dark` class on `<html>`, and in German. It switches back to
 * light mode and English afterwards. A dialog renders in a portal, so its
 * tests pass `document.body`. `options` go to every run; a test with an
 * `<iframe>` of another origin passes `{ iframes: false }`, because jsdom
 * loads no frame for axe to enter, and axe still checks the frame element.
 */
export async function expectNoAxeViolations(
  container: Element,
  options: RunOptions = {},
) {
  const root = document.documentElement;
  try {
    root.classList.remove("dark");
    expect(await axe(container, options)).toHaveNoViolations();
    root.classList.add("dark");
    expect(await axe(container, options)).toHaveNoViolations();
    root.classList.remove("dark");
    await i18n.changeLanguage("de");
    expect(await axe(container, options)).toHaveNoViolations();
  } finally {
    root.classList.remove("dark");
    await i18n.changeLanguage("en");
  }
}

import { AxeBuilder } from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { signInAsDemo } from "./support/demo.ts";

const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

test("a signed-out visit to a guarded page lands on /sign-in with return_to", async ({
  page,
}) => {
  await page.goto("/programs/demo");

  await expect(page).toHaveURL("/sign-in?return_to=%2Fprograms%2Fdemo");
});

test("a demo session shows the program list, the display name and the demo banner", async ({
  page,
}) => {
  await signInAsDemo(page, 1);
  await page.goto("/");

  await expect(
    page.getByRole("heading", { level: 1, name: "Programs" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Test person 1" }),
  ).toBeVisible();
  await expect(
    page.getByText(
      "Demo mode: every account here is a pseudonymous test account.",
    ),
  ).toBeVisible();
});

test("sign-out in the user menu leads to /sign-in and ends the session", async ({
  page,
}) => {
  await signInAsDemo(page, 1);
  await page.goto("/");

  await page.getByRole("button", { name: "Test person 1" }).click();
  await page.getByRole("menuitem", { name: "Sign out" }).click();
  await expect(page).toHaveURL("/sign-in");

  await page.goto("/");
  await expect(page).toHaveURL("/sign-in?return_to=%2F");
});

test("the shell has no axe violations in light and dark mode", async ({
  page,
}) => {
  for (const colorScheme of ["light", "dark"] as const) {
    await page.context().clearCookies();
    await page.emulateMedia({ colorScheme });

    await page.goto("/sign-in");
    await expect(
      page.getByRole("heading", { level: 1, name: "Sign in" }),
    ).toBeVisible();
    const html = page.locator("html");
    if (colorScheme === "dark") await expect(html).toContainClass("dark");
    else await expect(html).not.toContainClass("dark");
    const signedOut = await new AxeBuilder({ page })
      .withTags(WCAG_TAGS)
      .analyze();
    expect(signedOut.violations, `/sign-in in ${colorScheme} mode`).toEqual([]);

    await signInAsDemo(page, 2);
    await page.goto("/");
    await expect(
      page.getByRole("heading", { level: 1, name: "Programs" }),
    ).toBeVisible();
    const signedIn = await new AxeBuilder({ page })
      .withTags(WCAG_TAGS)
      .analyze();
    expect(signedIn.violations, `/ in ${colorScheme} mode`).toEqual([]);
  }
});

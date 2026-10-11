import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import {
  confirmCodesSaved,
  createPasskeyAndDownloadCodes,
  readSession,
  signOutThroughMenu,
} from "../support/account.ts";
import { addAuthenticator } from "../support/authenticator.ts";
import { devPost, openSettledPage } from "../support/dev.ts";

// The invented lldap user of `make services-seed` (task 0007).
const DORA = new URL(
  "../../../dev/lldap/bootstrap/user-configs/dora.json",
  import.meta.url,
);

test(
  "a directory sign-in enrolls a passkey and then passes the second factor",
  { tag: "@ldap" },
  async ({ page }) => {
    // The provider check and the reset run on a page without the
    // conditional passkey request of /sign-in (`openSettledPage`).
    await openSettledPage(page);
    const { providers } = await readSession(page);
    const provider = providers.find((entry) => entry.type === "ldap");
    test.skip(provider === undefined, "no LDAP provider configured");
    const { password, displayName } = JSON.parse(
      await readFile(DORA, "utf8"),
    ) as { password: string; displayName: string };

    await addAuthenticator(page);
    expect(
      await devPost(page, "reset", { provider_keys: [provider!.key] }),
    ).toBe(204);

    const signIn = async () => {
      await page.goto("/sign-in");
      const form = page.getByRole("form", { name: provider!.label });
      await form.getByLabel("User name").fill("dora");
      await form.getByLabel("Password", { exact: true }).fill(password);
      const answer = page.waitForResponse(
        (response) =>
          new URL(response.url()).pathname ===
          `/api/auth/ldap/${provider!.key}`,
      );
      await form
        .getByRole("button", { name: `Sign in with ${provider!.label}` })
        .click();
      return (await (await answer).json()) as { next: string };
    };

    expect(await signIn()).toEqual({ next: "enroll_second_factor" });
    await expect(page).toHaveURL(/\/enroll$/);
    await createPasskeyAndDownloadCodes(page);
    await confirmCodesSaved(page);
    await signOutThroughMenu(page, displayName);

    expect(await signIn()).toEqual({ next: "second_factor" });
    await page.getByRole("button", { name: "Use a passkey" }).click();
    await expect(page).toHaveURL(/\/$/);
  },
);

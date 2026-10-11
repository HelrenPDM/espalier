import { expect, test } from "@playwright/test";
import {
  confirmCodesSaved,
  createPasskeyAndDownloadCodes,
  e2eAddress,
  enrollWithPasskey,
  linkPattern,
  openMailLink,
} from "../support/account.ts";
import { addAuthenticator } from "../support/authenticator.ts";
import { findInMail } from "../support/mailpit.ts";
import { blockConditionalRequest } from "../support/passkey.ts";

// Recovery with a link sent by e-mail and a saved recovery code (README
// section 6.6) leads to re-enrollment and offers to end the other sessions.
test("a recovery re-enrolls a passkey and ends the session of the first context", async ({
  browser,
  page,
  request,
  baseURL,
}) => {
  const email = e2eAddress();
  await addAuthenticator(page);
  const codes = await enrollWithPasskey(page, request, baseURL!, email);

  const second = await browser.newContext({ baseURL });
  const recovering = await second.newPage();
  const recover = async (code: string) => {
    await recovering.goto("/recover");
    await recovering.getByLabel("E-mail address").fill(email);
    await recovering
      .getByRole("button", { name: "Send the recovery link" })
      .click();
    await expect(
      recovering.getByText(
        "If the address belongs to an account, we have sent a link to it.",
      ),
    ).toBeVisible();
    const link = await findInMail(
      request,
      email,
      linkPattern(baseURL!, "recover"),
    );
    await openMailLink(recovering, link);
    await recovering.getByLabel("Recovery code").fill(code);
    await recovering.getByRole("button", { name: "Recover access" }).click();
  };

  await recover(codes[0]);
  await expect(recovering).toHaveURL(/\/enroll$/);
  await expect(
    recovering.getByRole("heading", {
      level: 1,
      name: "Set up a new sign-in method",
    }),
  ).toBeVisible();

  await addAuthenticator(recovering);
  const fresh = await createPasskeyAndDownloadCodes(recovering);
  expect(fresh).toHaveLength(10);
  await confirmCodesSaved(recovering);
  await expect(
    recovering.getByRole("heading", { name: "End your other sessions?" }),
  ).toBeVisible();
  await recovering
    .getByRole("button", { name: "End all other sessions" })
    .click();
  await expect(recovering).toHaveURL(/\/account\/security$/);

  await blockConditionalRequest(page);
  await page.goto("/account/security");
  await expect(page).toHaveURL(/\/sign-in/);

  // The recovery replaced every code, so an old code fails with a new link.
  await recovering.context().clearCookies();
  await recover(codes[1]);
  await expect(
    recovering.getByText(
      "The recovery code did not match, or the link has expired.",
    ),
  ).toBeVisible();
  await second.close();
});

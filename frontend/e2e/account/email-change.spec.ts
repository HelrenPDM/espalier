import { expect, test } from "@playwright/test";
import {
  e2eAddress,
  enrollWithPasskey,
  linkPattern,
  openMailLink,
} from "../support/account.ts";
import { addAuthenticator } from "../support/authenticator.ts";
import { findInMail } from "../support/mailpit.ts";

// The confirmation link of an e-mail change goes to the new address and
// carries its token in the fragment (README sections 6.4 and 6.12).
test("an e-mail change takes effect through the link sent to the new address", async ({
  page,
  request,
  baseURL,
}) => {
  const email = e2eAddress();
  const next = email.replace("@", "-new@");
  await addAuthenticator(page);
  await enrollWithPasskey(page, request, baseURL!, email);

  await page.goto("/account/security");
  const section = page.getByRole("region", { name: "E-mail address" });
  await section.getByLabel("New e-mail address").fill(next);
  await section.getByRole("button", { name: "Change the address" }).click();
  await expect(
    section.getByText(
      "We have sent a confirmation link to the new address. The address changes when you open it.",
    ),
  ).toBeVisible();

  const link = await findInMail(
    request,
    next,
    linkPattern(baseURL!, "account/email/confirm"),
  );
  await openMailLink(page, link);
  await expect(
    page.getByRole("heading", {
      level: 1,
      name: "Confirm the new e-mail address",
    }),
  ).toBeVisible();
  await expect(page).toHaveURL(/\/account\/email\/confirm$/);
  expect(new URL(page.url()).hash).toBe("");

  await page.getByRole("button", { name: "Confirm new address" }).click();
  await expect(
    page.getByText("Your e-mail address was changed."),
  ).toBeVisible();

  await page.goto("/account/security");
  await expect(
    page.getByRole("region", { name: "E-mail address" }).getByText(next),
  ).toBeVisible();
});

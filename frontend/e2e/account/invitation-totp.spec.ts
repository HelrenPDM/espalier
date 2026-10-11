import { expect, test } from "@playwright/test";
import {
  acceptInvitation,
  confirmCodesSaved,
  e2eAddress,
  invitedName,
  signOutThroughMenu,
} from "../support/account.ts";
import { totpFromUri, waitForNextStep } from "../support/totp.ts";

// An invited local account without a password sets a password first, then
// the authenticator app (task 0011 step 9, 0005 step 15).
const PASSWORD = "violet lantern harbor 4821";

test("an invitee enrolls a password with the authenticator app and signs in with both", async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(120_000);
  const email = e2eAddress();
  await acceptInvitation(page, request, baseURL!, email);

  await page.getByRole("button", { name: "Use an authenticator app" }).click();
  await expect(
    page.getByRole("heading", { level: 1, name: "Choose a password" }),
  ).toBeVisible();
  await page.getByLabel("New password").fill(PASSWORD);
  const setup = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === "/api/me/totp" &&
      response.request().method() === "POST" &&
      response.status() === 200,
  );
  await page.getByRole("button", { name: "Save the password" }).click();
  const { otpauth_uri: uri } = (await (await setup).json()) as {
    otpauth_uri: string;
  };
  const totp = totpFromUri(uri);

  await page.getByLabel("Six-digit code from the app").fill(totp.generate());
  await page.getByRole("button", { name: "Confirm the code" }).click();
  await expect(
    page.getByRole("heading", { name: "Save your recovery codes" }),
  ).toBeVisible();
  await confirmCodesSaved(page);
  await expect(page).toHaveURL(/\/$/);
  await signOutThroughMenu(page, invitedName(email));
  await expect(page).toHaveURL(/\/sign-in$/);

  const form = page.getByRole("form", {
    name: "Sign in with e-mail and password",
  });
  await form.getByLabel("E-mail address").fill(email);
  await form.getByLabel("Password", { exact: true }).fill(PASSWORD);
  await page.getByRole("button", { name: "Continue with password" }).click();
  await expect(
    page.getByRole("heading", { name: "Confirm your sign-in" }),
  ).toBeVisible();

  const code = totp.generate();
  const wrong = `${(Number(code[0]) + 1) % 10}${code.slice(1)}`;
  await page.getByLabel("Six-digit code").fill(wrong);
  await page.getByRole("button", { name: "Confirm", exact: true }).click();
  await expect(
    page.getByText("Sign-in failed. Check your details and try again."),
  ).toBeVisible();

  await waitForNextStep();
  await page.getByLabel("Six-digit code").fill(totp.generate());
  await page.getByRole("button", { name: "Confirm", exact: true }).click();
  await expect(page).toHaveURL(/\/$/);
});

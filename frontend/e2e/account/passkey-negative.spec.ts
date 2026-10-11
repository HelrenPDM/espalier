import { expect, test } from "@playwright/test";
import {
  e2eAddress,
  enrollWithPasskey,
  invitedName,
  readSession,
  signOutThroughMenu,
} from "../support/account.ts";
import { addAuthenticator } from "../support/authenticator.ts";
import { blockConditionalRequest } from "../support/passkey.ts";

// A passkey without user verification never signs in (README section 6.6,
// `user_verification: "required"`).
test("a passkey assertion without user verification shows an error and opens no session", async ({
  page,
  request,
  baseURL,
}) => {
  const email = e2eAddress();
  const { cdp, authenticatorId } = await addAuthenticator(page);
  await enrollWithPasskey(page, request, baseURL!, email);
  await signOutThroughMenu(page, invitedName(email));
  await expect(page).toHaveURL(/\/sign-in$/);

  await blockConditionalRequest(page);
  await page.goto("/sign-in");
  const passkeyButton = page.getByRole("button", {
    name: "Sign in with a passkey",
  });
  const alert = page.getByRole("alert").filter({ hasText: /\S/ });

  await cdp.send("WebAuthn.setUserVerified", {
    authenticatorId,
    isUserVerified: false,
  });
  await passkeyButton.click();
  await expect(alert).toBeVisible();
  expect((await readSession(page)).user).toBeNull();

  await cdp.send("WebAuthn.setUserVerified", {
    authenticatorId,
    isUserVerified: true,
  });
  await cdp.send("WebAuthn.setResponseOverrideBits", {
    authenticatorId,
    isBadUV: true,
  });
  await passkeyButton.click();
  await expect(
    page.getByText("Sign-in failed. Check your details and try again."),
  ).toBeVisible();
  expect((await readSession(page)).user).toBeNull();
});

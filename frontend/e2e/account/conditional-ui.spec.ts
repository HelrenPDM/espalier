import { expect, test, type Request } from "@playwright/test";
import {
  e2eAddress,
  enrollWithPasskey,
  invitedName,
  readSession,
  signOutThroughMenu,
} from "../support/account.ts";
import { addAuthenticator } from "../support/authenticator.ts";
import { blockConditionalRequest } from "../support/passkey.ts";

const isPost = (request: Request, path: string) =>
  request.method() === "POST" && new URL(request.url()).pathname === path;

// Conditional UI waits until the person picks a passkey (ASVS 7.6.2).
test("conditional UI opens no session without a pick, the passkey button does", async ({
  page,
  request,
  baseURL,
}) => {
  const email = e2eAddress();
  const { cdp, authenticatorId } = await addAuthenticator(page);
  await enrollWithPasskey(page, request, baseURL!, email);
  await signOutThroughMenu(page, invitedName(email));
  await expect(page).toHaveURL(/\/sign-in$/);

  await cdp.send("WebAuthn.setAutomaticPresenceSimulation", {
    authenticatorId,
    enabled: false,
  });
  const options: unknown[] = [];
  const signIns: Request[] = [];
  page.on("request", (sent) => {
    if (isPost(sent, "/api/auth/passkey/options"))
      options.push(sent.postDataJSON());
    if (isPost(sent, "/api/auth/passkey")) signIns.push(sent);
  });

  await page.reload();
  await expect.poll(() => options.length).toBe(1);
  expect(options).toEqual([{ purpose: "sign_in" }]);
  await page.waitForTimeout(5_000);
  expect(signIns).toHaveLength(0);
  expect((await readSession(page)).user).toBeNull();

  await page.goto("about:blank");
  await cdp.send("WebAuthn.setAutomaticPresenceSimulation", {
    authenticatorId,
    enabled: true,
  });
  await blockConditionalRequest(page);
  signIns.length = 0;
  await page.goto("/sign-in");
  await page.getByRole("button", { name: "Sign in with a passkey" }).click();

  await expect(page).toHaveURL(/\/$/);
  expect(signIns).toHaveLength(1);
});

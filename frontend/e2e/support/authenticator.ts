import type { Page } from "@playwright/test";

type Overrides = {
  isUserVerified?: boolean;
  automaticPresenceSimulation?: boolean;
  defaultBackupEligibility?: boolean;
  defaultBackupState?: boolean;
};

/**
 * Adds a CDP virtual authenticator (Chromium only) to the page: a CTAP 2.1
 * platform authenticator with resident keys and user verification. The
 * CDP defaults of `hasResidentKey`, `hasUserVerification` and
 * `isUserVerified` are false, so the helper sets all three.
 */
export async function addAuthenticator(page: Page, overrides: Overrides = {}) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("WebAuthn.enable", { enableUI: false });
  const { authenticatorId } = await cdp.send(
    "WebAuthn.addVirtualAuthenticator",
    {
      options: {
        protocol: "ctap2",
        ctap2Version: "ctap2_1",
        transport: "internal",
        hasResidentKey: true,
        hasUserVerification: true,
        isUserVerified: true,
        automaticPresenceSimulation: true,
        ...overrides,
      },
    },
  );
  return { cdp, authenticatorId };
}

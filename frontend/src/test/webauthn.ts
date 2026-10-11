import {
  WebAuthnAbortService,
  browserSupportsWebAuthnAutofill,
  startAuthentication,
  startRegistration,
} from "@simplewebauthn/browser";
import { vi } from "vitest";

/**
 * The mocks of `@simplewebauthn/browser`. A test file declares
 * `vi.mock("@simplewebauthn/browser")` (hoisted by Vitest) and reads the
 * mocked functions here.
 */
export const webauthn = {
  startAuthentication: vi.mocked(startAuthentication),
  startRegistration: vi.mocked(startRegistration),
  browserSupportsWebAuthnAutofill: vi.mocked(browserSupportsWebAuthnAutofill),
  cancelCeremony: vi.mocked(WebAuthnAbortService.cancelCeremony),
};

/** An assertion as `startAuthentication` returns it. */
export const assertion = {
  id: "Y3JlZGVudGlhbC0x",
  rawId: "Y3JlZGVudGlhbC0x",
  type: "public-key" as const,
  response: {
    clientDataJSON: "Y2xpZW50LWRhdGE",
    authenticatorData: "YXV0aC1kYXRh",
    signature: "c2lnbmF0dXJl",
    userHandle: "dXNlci1oYW5kbGU",
  },
  clientExtensionResults: {},
  authenticatorAttachment: "platform" as const,
};

/** A registration as `startRegistration` returns it. */
export const registration = {
  id: "Y3JlZGVudGlhbC0y",
  rawId: "Y3JlZGVudGlhbC0y",
  type: "public-key" as const,
  response: {
    clientDataJSON: "Y2xpZW50LWRhdGE",
    attestationObject: "YXR0ZXN0YXRpb24",
    transports: ["internal"],
  },
  clientExtensionResults: {},
  authenticatorAttachment: "platform" as const,
};

/** Request options as `POST /api/auth/passkey/options` answers them. */
export const requestOptions = {
  challenge: "Y2hhbGxlbmdl",
  timeout: 300000,
  rpId: "localhost",
  userVerification: "required",
};

/** Creation options as `POST /api/me/passkeys/options` answers them. */
export const creationOptions = {
  rp: { id: "localhost", name: "Espalier" },
  user: { id: "dXNlci1oYW5kbGU", name: "ada@example.test", displayName: "Ada" },
  challenge: "Y2hhbGxlbmdl",
  pubKeyCredParams: [{ type: "public-key", alg: -7 }],
  timeout: 300000,
  excludeCredentials: [],
  authenticatorSelection: {
    residentKey: "required",
    userVerification: "required",
  },
  attestation: "none",
};

/** An error as `@simplewebauthn/browser` raises it. */
export function webauthnError(name: string, code: string) {
  return Object.assign(new Error(name), { name, code });
}

/** Resets the mocks to their defaults: autofill supported, every ceremony pending. */
export function resetWebAuthnMocks() {
  webauthn.startAuthentication.mockReset();
  webauthn.startRegistration.mockReset();
  webauthn.browserSupportsWebAuthnAutofill.mockReset();
  webauthn.cancelCeremony.mockReset();
  webauthn.browserSupportsWebAuthnAutofill.mockResolvedValue(true);
  webauthn.startAuthentication.mockImplementation(() => new Promise(() => {}));
  webauthn.startRegistration.mockImplementation(() => new Promise(() => {}));
}

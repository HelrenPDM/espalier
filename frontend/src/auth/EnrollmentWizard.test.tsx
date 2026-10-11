import { act, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { PasskeyRegistrationResult } from "../api/account";
import { sessionQueryKey, type Session } from "../api/session";
import { expectNoAxeViolations } from "../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type RecordedRequest,
  type StubResponses,
} from "../test/render";
import { signedInPayload } from "../test/session";
import {
  creationOptions,
  registration,
  resetWebAuthnMocks,
  webauthn,
  webauthnError,
} from "../test/webauthn";
import { EnrollmentWizard } from "./EnrollmentWizard";
import { rememberReturnTo, takeReturnTo } from "./returnTo";

vi.mock("@simplewebauthn/browser");

/** 15 code points as typed, 14 after NFC (the length test value of 0004 step 45). */
const NFD = "Lernpfad Café!";
const GUIDANCE =
  "Use at least 15 characters. A passphrase of several unrelated words reaches that length. Avoid well-known phrases, the name of this service and your own name or e-mail address.";
const REJECTED =
  "The new password was not accepted. The reason is shown below the field.";
const PANEL_TITLE = "Save your recovery codes";

/** Ten codes in the display form of 0005 step 11. */
const CODES = [
  "ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ",
  "BCDE-FGHI-JKLM-NOPQ-RSTU-VWXY-Z2",
  "CDEF-GHIJ-KLMN-OPQR-STUV-WXYZ-23",
  "DEFG-HIJK-LMNO-PQRS-TUVW-XYZ2-34",
  "EFGH-IJKL-MNOP-QRST-UVWX-YZ23-45",
  "FGHI-JKLM-NOPQ-RSTU-VWXY-Z234-56",
  "GHIJ-KLMN-OPQR-STUV-WXYZ-2345-67",
  "HIJK-LMNO-PQRS-TUVW-XYZ2-3456-7A",
  "IJKL-MNOP-QRST-UVWX-YZ23-4567-AB",
  "JKLM-NOPQ-RSTU-VWXY-Z234-567A-BC",
];

const SECRET = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP";
const GROUPED_SECRET = "JBSW Y3DP EHPK 3PXP JBSW Y3DP EHPK 3PXP";
const enrollment = {
  otpauth_uri: `otpauth://totp/Espalier:ada%40example.test?secret=${SECRET}&issuer=Espalier`,
  qr_svg_data_url: "data:image/svg+xml;base64,PHN2Zy8+",
  secret_base32: SECRET,
};

const defaultNickname = () =>
  `Passkey of ${new Intl.DateTimeFormat("en", { dateStyle: "medium" }).format(new Date())}`;

const passkeyResult = (
  overrides: Partial<PasskeyRegistrationResult> = {},
): PasskeyRegistrationResult => ({
  passkey: {
    id: "0b6f5c1e-7a2d-4c3b-9e8f-1a2b3c4d5e6f",
    nickname: defaultNickname(),
    backed_up: false,
    backup_eligible: true,
    inserted_at: "2026-10-11T10:00:00Z",
    last_used_at: null,
    transports: ["internal"],
  },
  other_sessions: 0,
  recovery_codes: CODES,
  session: signedInPayload("mfa"),
  ...overrides,
});

/** The answers of the passkey path that completes the enrollment. */
const passkeyResponses = (
  result: PasskeyRegistrationResult = passkeyResult(),
): StubResponses => ({
  "POST /api/me/passkeys/options": { status: 200, body: creationOptions },
  "POST /api/me/passkeys": { status: 200, body: result },
  "GET /api/session": { status: 200, body: signedInPayload("mfa") },
});

/** The answers of the app path for an account without a password. */
const passwordFirstResponses = (extra: StubResponses = {}): StubResponses => ({
  "POST /api/me/totp": [
    { status: 409, body: { error: "password_required" } },
    { status: 200, body: enrollment },
  ],
  "PUT /api/me/password": {
    status: 200,
    body: signedInPayload("enrollment", { csrf_token: "csrf-2" }),
  },
  "GET /api/session": {
    status: 200,
    body: signedInPayload("enrollment", { csrf_token: "csrf-2" }),
  },
  ...extra,
});

const renderWizard = (
  options: Parameters<typeof renderWithProviders>[1] = {},
) =>
  renderWithProviders(<EnrollmentWizard />, {
    route: "/enroll",
    session: signedInPayload("enrollment"),
    ...options,
  });

type User = ReturnType<typeof renderWizard>["user"];

async function createPasskey(user: User) {
  await user.click(screen.getByRole("button", { name: "Create a passkey" }));
  await screen.findByRole("heading", { name: "Create a passkey" });
  await user.click(screen.getByRole("button", { name: "Create the passkey" }));
}

async function openPasswordScreen(user: User) {
  await user.click(
    screen.getByRole("button", { name: "Use an authenticator app" }),
  );
  return screen.findByRole("heading", { name: "Choose a password" });
}

async function saveCodes(user: User) {
  await user.click(
    await screen.findByRole("checkbox", { name: "I have saved these codes" }),
  );
  await user.click(screen.getByRole("button", { name: "Continue" }));
}

/** The ids in `aria-describedby` of `element`. */
const describedBy = (element: HTMLElement) =>
  (element.getAttribute("aria-describedby") ?? "").split(/\s+/).filter(Boolean);

const indexOf = (
  requests: RecordedRequest[],
  method: string,
  path: string,
  from = 0,
) =>
  requests.findIndex(
    (request, index) =>
      index >= from && request.method === method && request.path === path,
  );

beforeEach(() => {
  resetWebAuthnMocks();
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  takeReturnTo();
});

describe("the first screen", () => {
  test("offers the passkey first and the authenticator app second", async () => {
    renderWizard();

    const heading = await screen.findByRole("heading", {
      name: "Set up your sign-in",
    });
    await waitFor(() => expect(heading).toHaveFocus());
    expect(
      screen.getAllByRole("button").map((button) => button.textContent),
    ).toEqual(["Create a passkey", "Use an authenticator app"]);
  });

  test("a session of strength mfa without codes on screen goes to /sign-in", async () => {
    const { location } = renderWizard({ session: signedInPayload("mfa") });

    await waitFor(() => expect(location()).toBe("/sign-in"));
  });

  test("the first screen has no axe violations in light, dark and German", async () => {
    const { container } = renderWizard();
    await screen.findByRole("heading", { name: "Set up your sign-in" });

    await expectNoAxeViolations(container);
  });
});

describe("the passkey path", () => {
  test("sends the credential with the prefilled nickname and never uses auto-register", async () => {
    webauthn.startRegistration.mockResolvedValue(registration);
    const { requests, user } = renderWizard({ responses: passkeyResponses() });

    await user.click(screen.getByRole("button", { name: "Create a passkey" }));
    const nickname = await screen.findByLabelText("Name of the passkey");
    expect(nickname).toHaveValue(defaultNickname());
    expect(nickname).toHaveAttribute("maxlength", "60");
    await user.click(
      screen.getByRole("button", { name: "Create the passkey" }),
    );

    expect(
      await screen.findByRole("heading", { name: PANEL_TITLE }),
    ).toBeInTheDocument();
    expect(webauthn.startRegistration.mock.calls).toStrictEqual([
      [{ optionsJSON: creationOptions }],
    ]);
    expect(
      Object.keys(webauthn.startRegistration.mock.calls[0][0]),
    ).toStrictEqual(["optionsJSON"]);
    expect(
      requestsTo(requests, "POST", "/api/me/passkeys/options"),
    ).toHaveLength(1);
    expect(
      requestsTo(requests, "POST", "/api/me/passkeys").map(
        (request) => request.body,
      ),
    ).toStrictEqual([
      { credential: registration, nickname: defaultNickname() },
    ]);
  });

  test("a passkey the authenticator already holds shows passkeyExists", async () => {
    webauthn.startRegistration.mockRejectedValue(
      webauthnError(
        "InvalidStateError",
        "ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED",
      ),
    );
    const { requests, user } = renderWizard({ responses: passkeyResponses() });

    await createPasskey(user);

    await waitFor(() =>
      expect(screen.getByRole("alert")).toHaveTextContent(
        "This device or security key already holds a passkey for your account.",
      ),
    );
    expect(requestsTo(requests, "POST", "/api/me/passkeys")).toEqual([]);
    expect(
      screen.getByRole("heading", { name: "Create a passkey" }),
    ).toBeInTheDocument();
  });

  test("a 422 registration_failed shows registrationFailed", async () => {
    webauthn.startRegistration.mockResolvedValue(registration);
    const { user } = renderWizard({
      responses: {
        ...passkeyResponses(),
        "POST /api/me/passkeys": {
          status: 422,
          body: { error: "registration_failed" },
        },
      },
    });

    await createPasskey(user);

    await waitFor(() =>
      expect(screen.getByRole("alert")).toHaveTextContent(
        "The passkey could not be created. Please try again.",
      ),
    );
    expect(
      screen.queryByRole("heading", { name: PANEL_TITLE }),
    ).not.toBeInTheDocument();
  });

  test("the codes panel stays after the session strength changes to mfa", async () => {
    webauthn.startRegistration.mockResolvedValue(registration);
    const { location, queryClient, requests, user } = renderWizard({
      responses: passkeyResponses(),
    });

    await createPasskey(user);

    expect(
      await screen.findByRole("heading", { name: PANEL_TITLE }),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(
        queryClient.getQueryData<Session>(sessionQueryKey)?.sessionStrength,
      ).toBe("mfa"),
    );
    expect(
      indexOf(
        requests,
        "GET",
        "/api/session",
        indexOf(requests, "POST", "/api/me/passkeys"),
      ),
    ).toBeGreaterThan(0);
    // Give the wizard time to render with the new session.
    await act(() => new Promise((resolve) => setTimeout(resolve, 50)));

    expect(location()).toBe("/enroll");
    expect(
      screen.getByRole("heading", { name: PANEL_TITLE }),
    ).toBeInTheDocument();
    expect(
      screen.getAllByRole("listitem").map((item) => item.textContent),
    ).toEqual(CODES);
  });

  test("after Continue with other sessions the prompt to end them appears", async () => {
    webauthn.startRegistration.mockResolvedValue(registration);
    const { location, user } = renderWizard({
      responses: passkeyResponses(passkeyResult({ other_sessions: 2 })),
    });

    await createPasskey(user);
    await saveCodes(user);

    expect(
      await screen.findByRole("heading", { name: "End your other sessions?" }),
    ).toBeInTheDocument();
    for (const code of CODES)
      expect(document.body.textContent).not.toContain(code);
    expect(location()).toBe("/enroll");

    await user.click(
      screen.getByRole("button", { name: "Keep the other sessions" }),
    );

    await waitFor(() => expect(location()).toBe("/"));
  });

  test("a recovery session ends on /account/security", async () => {
    webauthn.startRegistration.mockResolvedValue(registration);
    rememberReturnTo("/programs/demo");
    const { location, user } = renderWizard({
      session: signedInPayload("recovery"),
      responses: passkeyResponses(),
    });
    expect(
      await screen.findByRole("heading", {
        name: "Set up a new sign-in method",
      }),
    ).toBeInTheDocument();

    await createPasskey(user);
    await saveCodes(user);

    await waitFor(() => expect(location()).toBe("/account/security"));
  });

  test("an enrollment session ends on the remembered return path", async () => {
    webauthn.startRegistration.mockResolvedValue(registration);
    rememberReturnTo("/programs/demo");
    const { location, user } = renderWizard({ responses: passkeyResponses() });

    await createPasskey(user);
    await saveCodes(user);

    await waitFor(() => expect(location()).toBe("/programs/demo"));
    expect(takeReturnTo()).toBeNull();
  });

  test("an enrollment session without a remembered path ends on /", async () => {
    webauthn.startRegistration.mockResolvedValue(registration);
    const { location, user } = renderWizard({ responses: passkeyResponses() });

    await createPasskey(user);
    await saveCodes(user);

    await waitFor(() => expect(location()).toBe("/"));
  });
});

describe("the authenticator-app path", () => {
  test("409 password_required opens the password screen, then the setup repeats", async () => {
    const { requests, user } = renderWizard({
      responses: passwordFirstResponses(),
    });

    const heading = await openPasswordScreen(user);
    await waitFor(() => expect(heading).toHaveFocus());
    const input = screen.getByLabelText("New password");
    expect(input).toHaveAttribute("type", "password");
    expect(input).toHaveAttribute("autocomplete", "new-password");
    expect(input).not.toHaveAttribute("maxlength");
    expect(
      screen.getByRole("button", { name: "Show password" }),
    ).toHaveAttribute("aria-pressed", "false");
    expect(screen.queryByLabelText("Current password")).not.toBeInTheDocument();
    expect(requestsTo(requests, "POST", "/api/me/totp")).toHaveLength(1);

    await user.type(input, "a long enough passphrase");
    await user.click(screen.getByRole("button", { name: "Save the password" }));

    expect(
      await screen.findByRole("heading", {
        name: "Set up the authenticator app",
      }),
    ).toBeInTheDocument();
    expect(await screen.findByText(GROUPED_SECRET)).toBeInTheDocument();
    const setups = requestsTo(requests, "POST", "/api/me/totp");
    expect(setups).toHaveLength(2);
    expect(
      requestsTo(requests, "PUT", "/api/me/password").map(
        (request) => request.body,
      ),
    ).toStrictEqual([{ password: "a long enough passphrase" }]);

    // The refetch after the PUT puts the new CSRF token into the cache
    // before the setup repeats.
    const put = indexOf(requests, "PUT", "/api/me/password");
    const refetch = indexOf(requests, "GET", "/api/session", put);
    const repeat = indexOf(requests, "POST", "/api/me/totp", put);
    expect(put).toBeGreaterThan(0);
    expect(refetch).toBeGreaterThan(put);
    expect(repeat).toBeGreaterThan(refetch);
    expect(setups[0].headers.get("x-csrf-token")).toBe("csrf-1");
    expect(setups[1].headers.get("x-csrf-token")).toBe("csrf-2");
  });

  test.each([
    [
      "common",
      "This password is on a list of commonly used passwords. Choose a different one.",
    ],
    [
      "breached",
      "This password appears in known data breaches. Choose a different one.",
    ],
  ])(
    "a 422 validation_failed with %s shows its field error next to the guidance",
    async (code, message) => {
      const { requests, user } = renderWizard({
        responses: passwordFirstResponses({
          "PUT /api/me/password": {
            status: 422,
            body: { error: "validation_failed", fields: { password: [code] } },
          },
        }),
      });

      await openPasswordScreen(user);
      await user.type(
        screen.getByLabelText("New password"),
        "a long enough passphrase",
      );
      await user.click(
        screen.getByRole("button", { name: "Save the password" }),
      );

      const field = await screen.findByText(message);
      const input = screen.getByLabelText("New password");
      expect(input).toHaveAttribute("aria-invalid", "true");
      const errorId = field.closest("[id]")?.id;
      const guidanceId = screen.getByText(GUIDANCE).id;
      expect(errorId).toBeTruthy();
      expect(guidanceId).toBeTruthy();
      expect(describedBy(input)).toEqual(
        expect.arrayContaining([guidanceId, errorId]),
      );
      expect(input).toHaveAccessibleDescription(
        expect.stringContaining(message),
      );
      expect(screen.getByRole("alert")).toHaveTextContent(REJECTED);
      expect(
        screen.getByRole("heading", { name: "Choose a password" }),
      ).toBeInTheDocument();
      expect(requestsTo(requests, "POST", "/api/me/totp")).toHaveLength(1);
    },
  );

  test("the counter shows 14 for the NFD string, and the PUT carries it as typed", async () => {
    const { requests, user } = renderWizard({
      responses: passwordFirstResponses(),
    });
    expect(NFD).toHaveLength(15);
    expect(NFD.normalize("NFC")).toHaveLength(14);

    await openPasswordScreen(user);
    const input = screen.getByLabelText("New password");
    await user.type(input, NFD);

    expect(input).toHaveValue(NFD);
    expect(screen.getByText("14 characters (15 to 128)")).toBeInTheDocument();
    expect(input).toHaveAccessibleDescription(
      expect.stringContaining("14 characters (15 to 128)"),
    );

    await user.click(screen.getByRole("button", { name: "Save the password" }));

    await waitFor(() =>
      expect(requestsTo(requests, "PUT", "/api/me/password")).toHaveLength(1),
    );
    const [put] = requestsTo(requests, "PUT", "/api/me/password");
    expect(put.body).toStrictEqual({ password: NFD });
    expect(put.body).not.toHaveProperty("current_password");
    const sent = (put.body as { password: string }).password;
    expect(sent).toBe(NFD);
    expect(sent).not.toBe(NFD.normalize("NFC"));
    expect(new TextEncoder().encode(sent)).toEqual(
      new TextEncoder().encode(NFD),
    );
    expect(await screen.findByText(GROUPED_SECRET)).toBeInTheDocument();
  });

  test("the confirmed code completes the enrollment with the codes panel", async () => {
    const { requests, user } = renderWizard({
      responses: {
        "POST /api/me/totp": { status: 200, body: enrollment },
        "POST /api/me/totp/confirm": {
          status: 200,
          body: {
            other_sessions: 0,
            recovery_codes: CODES,
            session: signedInPayload("mfa"),
            totp: { enabled: true, enabled_at: "2026-10-11T10:00:00Z" },
          },
        },
        "GET /api/session": { status: 200, body: signedInPayload("mfa") },
      },
    });

    await user.click(
      screen.getByRole("button", { name: "Use an authenticator app" }),
    );
    await user.type(
      await screen.findByLabelText("Six-digit code from the app"),
      "123456",
    );
    await user.click(screen.getByRole("button", { name: "Confirm the code" }));

    expect(
      await screen.findByRole("heading", { name: PANEL_TITLE }),
    ).toBeInTheDocument();
    expect(screen.queryByText(GROUPED_SECRET)).not.toBeInTheDocument();
    expect(
      requestsTo(requests, "POST", "/api/me/totp/confirm").map(
        (request) => request.body,
      ),
    ).toStrictEqual([{ code: "123456" }]);
  });

  test("the password screen with a field error has no axe violations in light, dark and German", async () => {
    const { container, user } = renderWizard({
      responses: passwordFirstResponses({
        "PUT /api/me/password": {
          status: 422,
          body: {
            error: "validation_failed",
            fields: { password: ["breached"] },
          },
        },
      }),
    });

    await openPasswordScreen(user);
    await user.type(
      screen.getByLabelText("New password"),
      "a long enough passphrase",
    );
    await user.click(screen.getByRole("button", { name: "Save the password" }));
    await screen.findByText(
      "This password appears in known data breaches. Choose a different one.",
    );

    await expectNoAxeViolations(container);
  });
});

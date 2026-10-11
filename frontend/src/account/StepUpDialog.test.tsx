import { act, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  securityQueryKey,
  type PasskeyView,
  type SecuritySummary,
} from "../api/account";
import {
  sessionQueryKey,
  type Session,
  type SessionPayload,
} from "../api/session";
import { requestStepUp } from "../api/stepUp";
import { expectNoAxeViolations } from "../test/axe";
import {
  renderWithProviders,
  requestsTo,
  stubLocationAssign,
  type StubResponses,
} from "../test/render";
import { signedInPayload } from "../test/session";
import {
  assertion,
  requestOptions,
  resetWebAuthnMocks,
  webauthn,
  webauthnError,
} from "../test/webauthn";
import { takeReturnTo } from "../auth/returnTo";

vi.mock("@simplewebauthn/browser");

const TITLE = "Confirm it is you";
const ROUTE = "/account/security";
const INTENTS = "/api/auth/oidc/entra/intents";
const OPTIONS = "/api/auth/passkey/options";
const REAUTH = "/api/me/reauth";

const entra = {
  key: "entra",
  type: "entra" as const,
  kind: "redirect" as const,
  label: "Entra ID",
  start_url: "/auth/oidc/entra",
};

const laptop: PasskeyView = {
  id: "0b9f3c1e-6a2d-4c8e-9f1a-2b3c4d5e6f70",
  nickname: "Laptop",
  inserted_at: "2026-09-01T08:00:00Z",
  last_used_at: "2026-10-10T09:30:00Z",
  backed_up: true,
  backup_eligible: true,
  transports: ["internal"],
};

const totpEnabled = { enabled: true, enabled_at: "2026-09-03T08:00:00Z" };

const security = (
  overrides: Partial<SecuritySummary> = {},
): SecuritySummary => ({
  admin_passkey_required: false,
  linked_providers: [],
  passkeys: [],
  password_set: true,
  recent_auth_until: null,
  recovery_codes: { generated_at: "2026-09-01T08:00:00Z", remaining: 10 },
  totp: { enabled: false, enabled_at: null },
  ...overrides,
});

const RECENT_AUTH_UNTIL = "2026-10-11T11:10:00Z";

/** The session after the step-up: a new CSRF token and the open window. */
const renewed = signedInPayload("mfa", {
  csrf_token: "csrf-2",
  session: { recent_auth_until: RECENT_AUTH_UNTIL },
});
const reauthSession = { ...renewed, recent_auth_until: RECENT_AUTH_UNTIL };

/** A session of an Entra sign-in whose provider confirmed a second factor. */
const federated = signedInPayload("mfa", {
  providers: [entra],
  session: { auth_methods: ["oidc", "idp_mfa"], provider_key: "entra" },
});

beforeEach(() => {
  resetWebAuthnMocks();
});

afterEach(() => {
  vi.unstubAllGlobals();
  takeReturnTo();
});

function renderPage(
  summary: SecuritySummary,
  {
    session = signedInPayload("mfa"),
    responses = {},
  }: { session?: SessionPayload; responses?: StubResponses } = {},
) {
  return renderWithProviders(<p>page</p>, {
    route: ROUTE,
    session,
    responses: {
      "GET /api/me/security": { status: 200, body: summary },
      "GET /api/session": { status: 200, body: renewed },
      ...responses,
    },
  });
}

/** Asks for a step-up as the API client does and returns the open dialog. */
async function openStepUp() {
  await screen.findByText("page");
  let result: Promise<boolean> = Promise.resolve(false);
  await act(async () => {
    result = requestStepUp();
  });
  const dialog = await screen.findByRole("dialog", { name: TITLE });
  return { result, dialog };
}

/** Records whether `promise` has settled. */
function track(promise: Promise<boolean>) {
  const state: { settled: boolean; value?: boolean } = { settled: false };
  void promise.then((value) => {
    state.settled = true;
    state.value = value;
  });
  return state;
}

describe("a session without a local factor whose provider confirmed a second factor", () => {
  test("posts the step_up intent before window.location.assign and remembers the current path", async () => {
    const assign = stubLocationAssign();
    const { requests, user } = renderPage(
      security({ linked_providers: ["entra"] }),
      {
        session: federated,
        responses: {
          [`POST ${INTENTS}`]: {
            status: 201,
            body: { url: "/auth/oidc/entra?intent=intent-1" },
          },
        },
      },
    );
    let intentsAtAssign = -1;
    let returnToAtAssign: string | null = null;
    assign.mockImplementation(() => {
      intentsAtAssign = requestsTo(requests, "POST", INTENTS).length;
      returnToAtAssign = takeReturnTo();
    });
    const { result, dialog } = await openStepUp();

    const button = await within(dialog).findByRole("button", {
      name: "Continue with Entra ID",
    });
    expect(
      within(dialog).queryByRole("button", { name: "Use a passkey" }),
    ).toBeNull();
    expect(within(dialog).queryByRole("textbox")).toBeNull();
    await user.click(button);

    await waitFor(() =>
      expect(assign).toHaveBeenCalledWith("/auth/oidc/entra?intent=intent-1"),
    );
    expect(assign).toHaveBeenCalledTimes(1);
    expect(intentsAtAssign).toBe(1);
    expect(requestsTo(requests, "POST", INTENTS).map((r) => r.body)).toEqual([
      { purpose: "step_up" },
    ]);
    expect(returnToAtAssign).toBe(ROUTE);
    await expect(result).resolves.toBe(false);
    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );
    expect(requestsTo(requests, "POST", REAUTH)).toHaveLength(0);
  });

  test("a 422 step_up_not_available shows errors.generic in the alert region of the dialog", async () => {
    const assign = stubLocationAssign();
    const { user } = renderPage(security({ linked_providers: ["entra"] }), {
      session: federated,
      responses: {
        [`POST ${INTENTS}`]: {
          status: 422,
          body: { error: "step_up_not_available" },
        },
      },
    });
    const { result, dialog } = await openStepUp();
    const state = track(result);

    await user.click(
      await within(dialog).findByRole("button", {
        name: "Continue with Entra ID",
      }),
    );

    await waitFor(() =>
      expect(within(dialog).getByRole("alert")).toHaveTextContent(
        "Something went wrong. Please try again.",
      ),
    );
    expect(assign).not.toHaveBeenCalled();
    expect(takeReturnTo()).toBeNull();
    expect(screen.getByRole("dialog", { name: TITLE })).toBeInTheDocument();
    expect(state.settled).toBe(false);
  });

  test("without idp_mfa the dialog offers no method", async () => {
    renderPage(security({ linked_providers: ["entra"] }), {
      session: signedInPayload("mfa", {
        providers: [entra],
        session: { auth_methods: ["oidc"], provider_key: "entra" },
      }),
    });
    const { dialog } = await openStepUp();

    expect(
      await within(dialog).findByText(
        "This session has no second factor for the confirmation.",
      ),
    ).toBeInTheDocument();
    expect(
      within(dialog).queryByRole("button", { name: "Continue with Entra ID" }),
    ).toBeNull();
  });
});

describe("a passkey", () => {
  test('"Use a passkey" posts reauth options and then the assertion, refetches the session and resolves true', async () => {
    webauthn.startAuthentication.mockResolvedValue(assertion);
    const { requests, user, queryClient } = renderPage(
      security({ passkeys: [laptop] }),
      {
        responses: {
          [`POST ${OPTIONS}`]: { status: 200, body: requestOptions },
          [`POST ${REAUTH}`]: { status: 200, body: reauthSession },
        },
      },
    );
    const { result, dialog } = await openStepUp();
    let sessionGetsAtResolve = -1;
    void result.then(() => {
      sessionGetsAtResolve = requestsTo(requests, "GET", "/api/session").length;
    });

    await user.click(
      await within(dialog).findByRole("button", { name: "Use a passkey" }),
    );

    await expect(result).resolves.toBe(true);
    expect(sessionGetsAtResolve).toBe(1);
    expect(requestsTo(requests, "POST", OPTIONS).map((r) => r.body)).toEqual([
      { purpose: "reauth" },
    ]);
    expect(webauthn.startAuthentication).toHaveBeenCalledWith({
      optionsJSON: requestOptions,
    });
    expect(requestsTo(requests, "POST", REAUTH).map((r) => r.body)).toEqual([
      { passkey: assertion },
    ]);
    expect(
      requests
        .filter((r) => r.path !== "/api/me/security")
        .map((r) => `${r.method} ${r.path}`),
    ).toEqual([`POST ${OPTIONS}`, `POST ${REAUTH}`, "GET /api/session"]);
    expect(queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken).toBe(
      "csrf-2",
    );
    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );
  });

  test("a closed passkey dialog shows its message and keeps the dialog open", async () => {
    webauthn.startAuthentication.mockRejectedValue(
      webauthnError("NotAllowedError", "ERROR_PASSTHROUGH_SEE_CAUSE_PROPERTY"),
    );
    const { requests, user } = renderPage(security({ passkeys: [laptop] }), {
      responses: { [`POST ${OPTIONS}`]: { status: 200, body: requestOptions } },
    });
    const { result, dialog } = await openStepUp();
    const state = track(result);

    await user.click(
      await within(dialog).findByRole("button", { name: "Use a passkey" }),
    );

    await waitFor(() =>
      expect(within(dialog).getByRole("alert")).toHaveTextContent(
        "The passkey request was closed or timed out. Try again or choose another way to sign in.",
      ),
    );
    expect(requestsTo(requests, "POST", REAUTH)).toHaveLength(0);
    expect(state.settled).toBe(false);
  });
});

describe("the authenticator app", () => {
  test("posts { totp } and resolves true", async () => {
    const { requests, user } = renderPage(security({ totp: totpEnabled }), {
      responses: { [`POST ${REAUTH}`]: { status: 200, body: reauthSession } },
    });
    const { result, dialog } = await openStepUp();

    await user.type(
      await within(dialog).findByLabelText(
        "Six-digit code of the authenticator app",
      ),
      "123456",
    );
    await user.click(
      within(dialog).getByRole("button", { name: "Confirm with the code" }),
    );

    await expect(result).resolves.toBe(true);
    expect(requestsTo(requests, "POST", REAUTH).map((r) => r.body)).toEqual([
      { totp: "123456" },
    ]);
    expect(
      requestsTo(requests, "POST", REAUTH)[0].headers.get("x-csrf-token"),
    ).toBe("csrf-1");
    expect(requestsTo(requests, "GET", "/api/session")).toHaveLength(1);
  });

  test("a 401 shows auth.errors.stepUpFailed and keeps the dialog open", async () => {
    const { requests, user } = renderPage(security({ totp: totpEnabled }), {
      responses: {
        [`POST ${REAUTH}`]: {
          status: 401,
          body: { error: "authentication_failed" },
        },
      },
    });
    const { result, dialog } = await openStepUp();
    const state = track(result);

    await user.type(
      await within(dialog).findByLabelText(
        "Six-digit code of the authenticator app",
      ),
      "000000",
    );
    await user.click(
      within(dialog).getByRole("button", { name: "Confirm with the code" }),
    );

    await waitFor(() =>
      expect(within(dialog).getByRole("alert")).toHaveTextContent(
        "The confirmation failed. Please try again.",
      ),
    );
    expect(screen.getByRole("dialog", { name: TITLE })).toBeInTheDocument();
    expect(requestsTo(requests, "POST", REAUTH)).toHaveLength(1);
    expect(state.settled).toBe(false);

    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));
    await expect(result).resolves.toBe(false);
  });
});

describe("the dialog", () => {
  test('"Cancel" and Escape close it and resolve false', async () => {
    const { requests, user } = renderPage(security({ totp: totpEnabled }));

    const first = await openStepUp();
    await user.click(
      await within(first.dialog).findByRole("button", { name: "Cancel" }),
    );
    await expect(first.result).resolves.toBe(false);
    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );

    const second = await openStepUp();
    await within(second.dialog).findByLabelText(
      "Six-digit code of the authenticator app",
    );
    await user.keyboard("{Escape}");
    await expect(second.result).resolves.toBe(false);
    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );

    expect(requestsTo(requests, "POST", REAUTH)).toHaveLength(0);
    expect(requestsTo(requests, "GET", "/api/session")).toHaveLength(0);
  });

  test("two concurrent requestStepUp() calls open one dialog", async () => {
    const { user } = renderPage(security({ totp: totpEnabled }));
    await screen.findByText("page");

    let first: Promise<boolean> = Promise.resolve(true);
    let second: Promise<boolean> = Promise.resolve(true);
    await act(async () => {
      first = requestStepUp();
      second = requestStepUp();
    });

    const dialog = await screen.findByRole("dialog", { name: TITLE });
    expect(screen.getAllByRole("dialog")).toHaveLength(1);
    expect(second).toBe(first);
    await user.click(
      await within(dialog).findByRole("button", { name: "Cancel" }),
    );
    await expect(first).resolves.toBe(false);
    await expect(second).resolves.toBe(false);
  });

  test("an unmount of the provider resolves the pending request false", async () => {
    const { unmount } = renderPage(security({ totp: totpEnabled }));
    const { result } = await openStepUp();

    unmount();

    await expect(result).resolves.toBe(false);
    await expect(requestStepUp()).resolves.toBe(false);
  });

  // Step 13: initial focus on the first method, also when the dialog opens
  // on a page that has not loaded ["me", "security"] (the admin area of 0015).
  test.each([
    ["with", true],
    ["without", false],
  ])(
    "focus moves to the first method %s a cached security summary",
    async (_name, cached) => {
      const summary = security({ passkeys: [laptop], totp: totpEnabled });
      const { queryClient } = renderPage(summary);
      if (cached) queryClient.setQueryData(securityQueryKey, summary);
      const { dialog } = await openStepUp();

      const button = await within(dialog).findByRole("button", {
        name: "Use a passkey",
      });

      await waitFor(() => expect(button).toHaveFocus());
    },
  );

  test("has no axe violations while it is open", async () => {
    renderPage(security({ passkeys: [laptop], totp: totpEnabled }));
    const { dialog } = await openStepUp();
    await within(dialog).findByRole("button", { name: "Use a passkey" });

    await expectNoAxeViolations(document.body);
  });
});

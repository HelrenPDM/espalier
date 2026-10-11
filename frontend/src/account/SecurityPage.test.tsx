import { screen, waitFor, within } from "@testing-library/react";
import type userEvent from "@testing-library/user-event";
import { Navigate, useLocation } from "react-router";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { PasskeyView, SecuritySummary, SessionView } from "../api/account";
import { RECENT_AUTH_ERROR_CODE } from "../api/errors";
import type { SessionPayload } from "../api/session";
import { expectNoAxeViolations } from "../test/axe";
import {
  renderWithProviders,
  requestsTo,
  stubLocationAssign,
  type RecordedRequest,
  type StubResponses,
} from "../test/render";
import { sessionPayload, signedInPayload } from "../test/session";
import { resetWebAuthnMocks } from "../test/webauthn";
import { SecurityPage } from "./SecurityPage";
import { takeReturnTo } from "../auth/returnTo";

vi.mock("@simplewebauthn/browser");

const ROUTE = "/account/security";
const STEP_UP_TITLE = "Confirm it is you";
const CODE_LABEL = "Six-digit code of the authenticator app";
const LAST_FACTOR_REASON =
  "You cannot remove your only second factor. Add another one first.";

const entra = {
  key: "entra",
  type: "entra" as const,
  kind: "redirect" as const,
  label: "Entra ID",
  start_url: "/auth/oidc/entra",
};

const ldap = {
  key: "ldap",
  type: "ldap" as const,
  kind: "credentials" as const,
  label: "Directory account",
  start_url: "/api/auth/ldap/ldap",
};

const providers = [entra, ldap];

const laptop: PasskeyView = {
  id: "0b9f3c1e-6a2d-4c8e-9f1a-2b3c4d5e6f70",
  nickname: "Laptop",
  inserted_at: "2026-09-01T08:00:00Z",
  last_used_at: "2026-10-10T09:30:00Z",
  backed_up: true,
  backup_eligible: true,
  transports: ["internal"],
};

const securityKey: PasskeyView = {
  id: "1c0a4d2f-7b3e-4d9f-8a2b-3c4d5e6f7a81",
  nickname: "Security key",
  inserted_at: "2026-09-02T08:00:00Z",
  last_used_at: null,
  backed_up: false,
  backup_eligible: false,
  transports: ["usb"],
};

const totpEnabled = { enabled: true, enabled_at: "2026-09-03T08:00:00Z" };

/** One passkey and no authenticator app: a single second factor. */
const security = (
  overrides: Partial<SecuritySummary> = {},
): SecuritySummary => ({
  admin_passkey_required: false,
  linked_providers: [],
  passkeys: [laptop],
  password_set: true,
  recent_auth_until: null,
  recovery_codes: { generated_at: "2026-09-01T08:00:00Z", remaining: 10 },
  totp: { enabled: false, enabled_at: null },
  ...overrides,
});

const sessions: SessionView[] = [
  {
    id: "2d1b5e3a-8c4f-4e0a-9b3c-4d5e6f7a8b92",
    current: true,
    device: "Firefox on Linux",
    auth_methods: ["passkey"],
    strength: "mfa",
    authenticated_at: "2026-10-11T08:00:00Z",
    last_seen_at: "2026-10-11T09:00:00Z",
    expires_at: "2026-10-12T08:00:00Z",
  },
  {
    id: "3e2c6f4b-9d5a-4f1b-8c4d-5e6f7a8b9ca3",
    current: false,
    device: null,
    auth_methods: ["password", "totp"],
    strength: "mfa",
    authenticated_at: "2026-10-10T08:00:00Z",
    last_seen_at: "2026-10-10T12:00:00Z",
    expires_at: "2026-10-11T20:00:00Z",
  },
];

const RECENT_AUTH_UNTIL = "2026-10-11T11:10:00Z";

/** The session after a step-up: a new CSRF token and the open window. */
const renewed = signedInPayload("mfa", {
  providers,
  csrf_token: "csrf-2",
  session: { recent_auth_until: RECENT_AUTH_UNTIL },
});
const reauthSession = { ...renewed, recent_auth_until: RECENT_AUTH_UNTIL };

const reauthRequired = {
  status: 403,
  body: { error: RECENT_AUTH_ERROR_CODE },
};

const removePath = (passkey: PasskeyView) => `/api/me/passkeys/${passkey.id}`;

beforeEach(() => {
  resetWebAuthnMocks();
});

afterEach(() => {
  vi.unstubAllGlobals();
  takeReturnTo();
});

function renderSecurity({
  summary = security(),
  session = signedInPayload("mfa", { providers }),
  responses = {},
  ui = <SecurityPage />,
}: {
  summary?: SecuritySummary;
  session?: SessionPayload;
  responses?: StubResponses;
  ui?: React.ReactNode;
} = {}) {
  return renderWithProviders(ui, {
    route: ROUTE,
    session,
    responses: {
      "GET /api/me/security": { status: 200, body: summary },
      "GET /api/me/sessions": { status: 200, body: { sessions } },
      ...responses,
    },
  });
}

/** Waits until both queries of the page have loaded. */
const loaded = () => screen.findByRole("heading", { name: "Passkeys" });

const region = (name: string) => screen.getByRole("region", { name });

/**
 * The "Remove" button in the row of the passkey `name`. The row is the
 * list item that shows the nickname.
 */
const removeButton = (name: string) => {
  const row = within(region("Passkeys"))
    .getByText(name, { selector: "p" })
    .closest("li");
  if (row === null) throw new Error(`No row for the passkey ${name}`);
  return within(row).getByRole("button", { name: /^Remove/ });
};

/** The requests after the page load, without the GETs of the page. */
const changes = (requests: RecordedRequest[]) =>
  requests.filter(
    (request) =>
      request.method !== "GET" ||
      !["/api/me/security", "/api/me/sessions"].includes(request.path),
  );

/** Opens the confirmation of "Remove" for `name` and confirms it. */
async function removePasskey(
  user: ReturnType<typeof userEvent.setup>,
  name: string,
) {
  await user.click(removeButton(name));
  const dialog = await screen.findByRole("dialog", {
    name: "Remove the passkey?",
  });
  await user.click(within(dialog).getByRole("button", { name: "Remove" }));
}

/** Confirms the open step-up dialog with an authenticator code. */
async function stepUpWithCode(user: ReturnType<typeof userEvent.setup>) {
  const dialog = await screen.findByRole("dialog", { name: STEP_UP_TITLE });
  await user.type(within(dialog).getByLabelText(CODE_LABEL), "123456");
  await user.click(
    within(dialog).getByRole("button", { name: "Confirm with the code" }),
  );
}

describe("the page", () => {
  test("loads both queries and renders one section per topic", async () => {
    const { requests } = renderSecurity();
    await loaded();

    expect(
      screen
        .getAllByRole("heading", { level: 2 })
        .map((heading) => heading.textContent),
    ).toEqual([
      "Passkeys",
      "Authenticator app",
      "Recovery codes",
      "Password",
      "E-mail address",
      "Connected accounts",
      "Active sessions",
      "Sign out on this device",
    ]);
    expect(requestsTo(requests, "GET", "/api/me/security")).toHaveLength(1);
    expect(requestsTo(requests, "GET", "/api/me/sessions")).toHaveLength(1);
    expect(
      within(region("Password")).getByLabelText("Current password"),
    ).toBeInTheDocument();
    expect(
      within(region("E-mail address")).getByLabelText("New e-mail address"),
    ).toBeInTheDocument();
    expect(
      screen.queryByText(
        "Your role requires a passkey. Add a passkey to your account.",
      ),
    ).not.toBeInTheDocument();
  });

  test("a demo session sees only the demo notice", async () => {
    const { requests } = renderWithProviders(<SecurityPage />, {
      route: ROUTE,
      session: signedInPayload("demo", {
        session: { auth_methods: ["demo"] },
        flags: { demo: true },
      }),
    });

    expect(
      await screen.findByText("Demo accounts have no security settings."),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { level: 1, name: "Security settings" }),
    ).toBeInTheDocument();
    expect(screen.queryAllByRole("heading", { level: 2 })).toEqual([]);
    expect(screen.queryAllByRole("button")).toEqual([]);
    expect(
      requests.filter((request) => request.path.startsWith("/api/me")),
    ).toEqual([]);
  });

  test("flags.admin_passkey_required shows the notice above the passkey section", async () => {
    renderSecurity({
      session: signedInPayload("mfa", {
        providers,
        flags: { admin_passkey_required: true },
      }),
    });
    const heading = await loaded();

    const notice = screen.getByText(
      "Your role requires a passkey. Add a passkey to your account.",
    );
    expect(
      notice.compareDocumentPosition(heading) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  test("the location state of a recovery-code sign-in announces the codes left in a status region", async () => {
    // The sign-in navigates here with the state, as SignInPage does.
    function AfterRecoverySignIn() {
      const location = useLocation();
      return location.state === null || location.state === undefined ? (
        <Navigate to={ROUTE} replace state={{ recoveryCodesRemaining: 3 }} />
      ) : (
        <SecurityPage />
      );
    }
    renderSecurity({ ui: <AfterRecoverySignIn /> });

    const notice = await screen.findByText(
      "You signed in with a recovery code. 3 codes are left. Create new codes below.",
    );
    expect(notice).toHaveAttribute("role", "status");
  });

  test("the page has its own sign-out button", async () => {
    const { requests, user, location } = renderSecurity({
      responses: {
        "DELETE /api/session": { status: 204 },
        "GET /api/session": { status: 200, body: sessionPayload() },
      },
    });
    await loaded();

    await user.click(
      within(region("Sign out on this device")).getByRole("button", {
        name: "Sign out",
      }),
    );

    await waitFor(() => expect(location()).toBe("/sign-in"));
    expect(requestsTo(requests, "DELETE", "/api/session")).toHaveLength(1);
  });

  test("has no axe violations when loaded and with a dialog open", async () => {
    const { user } = renderSecurity({
      // The Layout renders every page inside <main>.
      ui: (
        <main>
          <SecurityPage />
        </main>
      ),
      summary: security({
        passkeys: [laptop, securityKey],
        totp: totpEnabled,
        recovery_codes: { generated_at: null, remaining: 2 },
      }),
    });
    await loaded();

    await expectNoAxeViolations(document.body);

    await user.click(screen.getByRole("button", { name: "Connect Entra ID" }));
    await screen.findByRole("dialog", { name: "Connect Entra ID?" });

    await expectNoAxeViolations(document.body);
  });
});

describe("removing a factor", () => {
  test.each([
    ["the only passkey", security(), () => removeButton("Laptop")],
    [
      "the only authenticator app",
      security({ passkeys: [], totp: totpEnabled }),
      () =>
        within(region("Authenticator app")).getByRole("button", {
          name: "Remove",
        }),
    ],
  ])(
    '"Remove" is disabled for %s, with the reason linked through aria-describedby',
    async (_name, summary, button) => {
      renderSecurity({ summary });
      await loaded();

      const remove = button();
      expect(remove).toBeDisabled();
      expect(remove).toHaveAccessibleDescription(LAST_FACTOR_REASON);
    },
  );

  test('a passkey and the authenticator app leave both "Remove" buttons enabled', async () => {
    renderSecurity({ summary: security({ totp: totpEnabled }) });
    await loaded();

    for (const remove of [
      removeButton("Laptop"),
      within(region("Authenticator app")).getByRole("button", {
        name: "Remove",
      }),
    ]) {
      expect(remove).toBeEnabled();
      expect(remove).not.toHaveAttribute("aria-describedby");
    }
    expect(screen.queryByText(LAST_FACTOR_REASON)).not.toBeInTheDocument();
  });

  test("409 last_factor shows its message", async () => {
    const { requests, user } = renderSecurity({
      summary: security({ passkeys: [laptop, securityKey] }),
      responses: {
        [`DELETE ${removePath(laptop)}`]: {
          status: 409,
          body: { error: "last_factor" },
        },
      },
    });
    await loaded();
    expect(removeButton("Laptop")).toBeEnabled();

    await removePasskey(user, "Laptop");

    await waitFor(() =>
      expect(within(region("Passkeys")).getByRole("alert")).toHaveTextContent(
        "You cannot remove your last second factor.",
      ),
    );
    expect(requestsTo(requests, "DELETE", removePath(laptop))).toHaveLength(1);
  });

  test("other_sessions above zero after a removal offers to end the other sessions", async () => {
    const { user } = renderSecurity({
      summary: security({ passkeys: [laptop, securityKey] }),
      responses: {
        [`DELETE ${removePath(laptop)}`]: {
          status: 200,
          body: { other_sessions: 2 },
        },
      },
    });
    await loaded();

    await removePasskey(user, "Laptop");

    expect(
      await screen.findByRole("heading", { name: "End your other sessions?" }),
    ).toBeInTheDocument();
    expect(
      within(region("Passkeys")).getByText("The passkey was removed."),
    ).toBeInTheDocument();

    await user.click(
      screen.getByRole("button", { name: "Keep the other sessions" }),
    );
    expect(
      screen.queryByRole("heading", { name: "End your other sessions?" }),
    ).not.toBeInTheDocument();
  });

  test("other_sessions of zero after a removal shows no prompt", async () => {
    const { user } = renderSecurity({
      summary: security({ passkeys: [laptop, securityKey] }),
      responses: {
        [`DELETE ${removePath(laptop)}`]: {
          status: 200,
          body: { other_sessions: 0 },
        },
      },
    });
    await loaded();

    await removePasskey(user, "Laptop");

    expect(
      await within(region("Passkeys")).findByText("The passkey was removed."),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "End your other sessions?" }),
    ).not.toBeInTheDocument();
  });
});

describe("the step-up", () => {
  const twoFactors = security({
    passkeys: [laptop, securityKey],
    totp: totpEnabled,
  });

  test(`a 403 with ${RECENT_AUTH_ERROR_CODE} opens the step-up dialog`, async () => {
    const { requests, user } = renderSecurity({
      summary: twoFactors,
      responses: { [`DELETE ${removePath(laptop)}`]: reauthRequired },
    });
    await loaded();

    await removePasskey(user, "Laptop");

    const dialog = await screen.findByRole("dialog", { name: STEP_UP_TITLE });
    expect(
      within(dialog).getByText(
        "This change needs a recent confirmation with a second factor.",
      ),
    ).toBeInTheDocument();
    expect(requestsTo(requests, "DELETE", removePath(laptop))).toHaveLength(1);

    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));
    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );
    expect(requestsTo(requests, "DELETE", removePath(laptop))).toHaveLength(1);
    expect(requestsTo(requests, "POST", "/api/me/reauth")).toHaveLength(0);
  });

  test("the original request repeats once after a successful step-up, with the CSRF token of the refetched session", async () => {
    const { requests, user } = renderSecurity({
      summary: twoFactors,
      responses: {
        [`DELETE ${removePath(laptop)}`]: [
          reauthRequired,
          { status: 200, body: { other_sessions: 0 } },
        ],
        "POST /api/me/reauth": { status: 200, body: reauthSession },
        "GET /api/session": { status: 200, body: renewed },
      },
    });
    await loaded();

    await removePasskey(user, "Laptop");
    await stepUpWithCode(user);

    expect(
      await within(region("Passkeys")).findByText("The passkey was removed."),
    ).toBeInTheDocument();
    expect(
      changes(requests).map((request) => `${request.method} ${request.path}`),
    ).toEqual([
      `DELETE ${removePath(laptop)}`,
      "POST /api/me/reauth",
      "GET /api/session",
      `DELETE ${removePath(laptop)}`,
    ]);
    expect(
      requestsTo(requests, "DELETE", removePath(laptop)).map((request) =>
        request.headers.get("x-csrf-token"),
      ),
    ).toEqual(["csrf-1", "csrf-2"]);
    expect(
      requestsTo(requests, "POST", "/api/me/reauth").map(
        (request) => request.body,
      ),
    ).toEqual([{ totp: "123456" }]);
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  test("after a wrong code and a correct one the removed passkey leaves the list", async () => {
    let removed = false;
    const { requests, user } = renderSecurity({
      summary: twoFactors,
      responses: {
        "GET /api/me/security": () => ({
          status: 200,
          body: removed
            ? { ...twoFactors, passkeys: [securityKey] }
            : twoFactors,
        }),
        [`DELETE ${removePath(laptop)}`]: () => {
          if (requestsTo(requests, "POST", "/api/me/reauth").length < 2)
            return reauthRequired;
          removed = true;
          return { status: 200, body: { other_sessions: 0 } };
        },
        "POST /api/me/reauth": [
          { status: 401, body: { error: "authentication_failed" } },
          { status: 200, body: reauthSession },
        ],
        "GET /api/session": { status: 200, body: renewed },
      },
    });
    await loaded();

    await removePasskey(user, "Laptop");
    const dialog = await screen.findByRole("dialog", { name: STEP_UP_TITLE });
    await user.type(await within(dialog).findByLabelText(CODE_LABEL), "000000");
    await user.click(
      within(dialog).getByRole("button", { name: "Confirm with the code" }),
    );
    await waitFor(() =>
      expect(within(dialog).getByRole("alert")).toHaveTextContent(
        "The confirmation failed. Please try again.",
      ),
    );
    const field = await within(dialog).findByLabelText(CODE_LABEL);
    await user.clear(field);
    await user.type(field, "123456");
    await user.click(
      within(dialog).getByRole("button", { name: "Confirm with the code" }),
    );

    await waitFor(() =>
      expect(requestsTo(requests, "DELETE", removePath(laptop))).toHaveLength(
        2,
      ),
    );
    await waitFor(() =>
      expect(
        within(region("Passkeys")).queryByText("Laptop", { selector: "p" }),
      ).not.toBeInTheDocument(),
    );
    expect(
      within(region("Passkeys")).getByText("Security key", { selector: "p" }),
    ).toBeInTheDocument();
  });

  test("a second 403 does not reopen the dialog", async () => {
    const { requests, user } = renderSecurity({
      summary: twoFactors,
      responses: {
        [`DELETE ${removePath(laptop)}`]: reauthRequired,
        "POST /api/me/reauth": { status: 200, body: reauthSession },
        "GET /api/session": { status: 200, body: renewed },
      },
    });
    await loaded();

    await removePasskey(user, "Laptop");
    await stepUpWithCode(user);

    await waitFor(() =>
      expect(requestsTo(requests, "DELETE", removePath(laptop))).toHaveLength(
        2,
      ),
    );
    await waitFor(() =>
      expect(within(region("Passkeys")).getByRole("alert")).toHaveTextContent(
        "Something went wrong. Please try again.",
      ),
    );
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(requestsTo(requests, "POST", "/api/me/reauth")).toHaveLength(1);
    expect(requestsTo(requests, "DELETE", removePath(laptop))).toHaveLength(2);
  });
});

describe("connected accounts", () => {
  test('"Connect" on a redirect provider confirms first, then posts the link intent before window.location.assign', async () => {
    const assign = stubLocationAssign();
    const { requests, user } = renderSecurity({
      responses: {
        "POST /api/auth/oidc/entra/intents": {
          status: 201,
          body: { url: "/auth/oidc/entra?intent=intent-1" },
        },
      },
    });
    let intentsAtAssign = -1;
    let returnToAtAssign: string | null = null;
    assign.mockImplementation(() => {
      intentsAtAssign = requestsTo(
        requests,
        "POST",
        "/api/auth/oidc/entra/intents",
      ).length;
      returnToAtAssign = takeReturnTo();
    });
    await loaded();
    const before = requests.length;

    await user.click(screen.getByRole("button", { name: "Connect Entra ID" }));

    const dialog = await screen.findByRole("dialog", {
      name: "Connect Entra ID?",
    });
    expect(dialog).toHaveTextContent(
      "After the connection, this account signs in with Entra ID only. Your passkeys, your authenticator app and your recovery codes then serve as the second step after Entra ID. Sign-in with a password, sign-in with a passkey alone and recovery through an e-mail link end for this account.",
    );
    expect(requests.slice(before)).toEqual([]);

    await user.click(within(dialog).getByRole("button", { name: "Connect" }));

    await waitFor(() =>
      expect(assign).toHaveBeenCalledWith("/auth/oidc/entra?intent=intent-1"),
    );
    expect(assign).toHaveBeenCalledTimes(1);
    expect(intentsAtAssign).toBe(1);
    expect(
      requests.slice(before).map((request) => [request.method, request.path]),
    ).toEqual([["POST", "/api/auth/oidc/entra/intents"]]);
    expect(requests[before].body).toEqual({ purpose: "link" });
    expect(returnToAtAssign).toBe(ROUTE);
  });

  test('"Cancel" in the confirmation of a redirect provider sends no request', async () => {
    const assign = stubLocationAssign();
    const { requests, user } = renderSecurity();
    await loaded();
    const before = requests.length;

    await user.click(screen.getByRole("button", { name: "Connect Entra ID" }));
    const dialog = await screen.findByRole("dialog", {
      name: "Connect Entra ID?",
    });
    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );
    expect(requests.slice(before)).toEqual([]);
    expect(assign).not.toHaveBeenCalled();
  });

  test('"Cancel" in the confirmation of an LDAP form sends no request', async () => {
    const { requests, user } = renderSecurity({
      responses: {
        "POST /api/me/identities/ldap/ldap": {
          status: 200,
          body: { status: "linked" },
        },
      },
    });
    await loaded();
    const before = requests.length;
    const form = screen.getByRole("form", { name: "Directory account" });
    await user.type(within(form).getByLabelText("User name"), "ada");
    await user.type(within(form).getByLabelText("Password"), "directory pass");

    await user.click(
      within(form).getByRole("button", { name: "Connect Directory account" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Connect Directory account?",
    });
    expect(dialog).toHaveTextContent(
      "After the connection, this account signs in with Directory account only.",
    );
    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );
    expect(requests.slice(before)).toEqual([]);

    // "Connect" in the confirmation sends the form.
    await user.click(
      within(form).getByRole("button", { name: "Connect Directory account" }),
    );
    await user.click(
      within(
        await screen.findByRole("dialog", {
          name: "Connect Directory account?",
        }),
      ).getByRole("button", { name: "Connect" }),
    );

    expect(
      await within(form).findByText("The account is connected."),
    ).toBeInTheDocument();
    expect(
      requestsTo(requests, "POST", "/api/me/identities/ldap/ldap").map(
        (request) => request.body,
      ),
    ).toEqual([{ username: "ada", password: "directory pass" }]);
  });

  test("a linked LDAP account shows connected without a form, the password section shows external and the e-mail section is gone", async () => {
    renderSecurity({
      summary: security({ linked_providers: ["ldap"], password_set: true }),
    });
    await loaded();

    const entry = within(region("Connected accounts"))
      .getByText("Directory account")
      .closest("li");
    expect(entry).toHaveTextContent("Directory account: connected");
    expect(entry?.querySelector("form, input, button")).toBeNull();
    expect(
      screen.queryByRole("form", { name: "Directory account" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Connect Entra ID" }),
    ).toBeInTheDocument();

    const password = region("Password");
    expect(password).toHaveTextContent(
      "This account signs in through a connected provider and has no password sign-in.",
    );
    expect(password.querySelector("form, input")).toBeNull();
    expect(within(password).queryByRole("button")).toBeNull();

    expect(
      screen.queryByRole("region", { name: "E-mail address" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByLabelText("New e-mail address"),
    ).not.toBeInTheDocument();
  });
});

describe("sessions", () => {
  test('the current session shows "This device" without an End button, and a session without device shows "Unknown device"', async () => {
    renderSecurity();
    await loaded();

    const [current, other] = within(region("Active sessions")).getAllByRole(
      "listitem",
    );
    expect(current).toHaveTextContent("Firefox on Linux");
    expect(current).toHaveTextContent("This device");
    expect(within(current).queryByRole("button")).toBeNull();

    expect(other).toHaveTextContent("Unknown device");
    expect(other).not.toHaveTextContent("This device");
    expect(other).toHaveTextContent("Password, Authenticator app");
    expect(within(other).getByRole("button", { name: /^End/ })).toBeEnabled();
  });
});

describe("accessible names", () => {
  // "Remove" and "End" repeat in every row, so each button names its
  // passkey or device for screen readers (WCAG 2.4.6).
  test('"Remove" names its passkey and "End" names its device', async () => {
    renderSecurity({ summary: security({ passkeys: [laptop, securityKey] }) });
    await loaded();

    expect(
      screen.getByRole("button", { name: "Remove Laptop" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Remove Security key" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "End Unknown device" }),
    ).toBeInTheDocument();
  });
});

import { act, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { expectNoAxeViolations } from "../test/axe";
import {
  renderWithProviders,
  requestsTo,
  stubLocationAssign,
} from "../test/render";
import { sessionPayload, signedInPayload } from "../test/session";
import {
  assertion,
  requestOptions,
  resetWebAuthnMocks,
  webauthn,
} from "../test/webauthn";
import { SignInPage } from "./SignInPage";
import { takeReturnTo } from "./returnTo";

vi.mock("@simplewebauthn/browser");

const providers = [
  {
    key: "entra",
    type: "entra" as const,
    kind: "redirect" as const,
    label: "Entra ID",
    start_url: "/auth/oidc/entra",
  },
  {
    key: "ldap",
    type: "ldap" as const,
    kind: "credentials" as const,
    label: "Directory account",
    start_url: "/api/auth/ldap/ldap",
  },
];

const OPTIONS = "/api/auth/passkey/options";

beforeEach(() => {
  resetWebAuthnMocks();
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  takeReturnTo();
});

const renderSignIn = (
  options: Parameters<typeof renderWithProviders>[1] = {},
) =>
  renderWithProviders(<SignInPage />, {
    route: "/sign-in?return_to=%2Fprograms%2Fdemo",
    ...options,
    responses: {
      [`POST ${OPTIONS}`]: { status: 200, body: requestOptions },
      ...options.responses,
    },
  });

const optionRequests = (requests: { method: string; path: string }[]) =>
  requestsTo(requests as never, "POST", OPTIONS);

describe("conditional UI", () => {
  test("the e-mail field is the only field with webauthn in its autocomplete", async () => {
    const { container } = renderSignIn({
      session: sessionPayload({ providers }),
    });

    const email = await screen.findByLabelText("E-mail address");
    expect(email).toHaveAttribute("autocomplete", "username webauthn");
    expect(email).toHaveAttribute("id", "signin-email");
    expect(email).toHaveAttribute("name", "username");
    expect(container.querySelectorAll("[autocomplete*='webauthn']")).toEqual(
      expect.objectContaining({ length: 1 }),
    );
  });

  test("inside StrictMode exactly one sign_in options request leaves and autofill starts once", async () => {
    const { requests } = renderSignIn({ strict: true });

    await waitFor(() =>
      expect(webauthn.startAuthentication).toHaveBeenCalledTimes(1),
    );
    expect(optionRequests(requests).map((request) => request.body)).toEqual([
      { purpose: "sign_in" },
    ]);
    expect(webauthn.startAuthentication).toHaveBeenCalledWith({
      optionsJSON: requestOptions,
      useBrowserAutofill: true,
    });
  });

  test("no options request leaves after the second-factor step opens, also after 300 seconds", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const { requests, user } = renderSignIn({
      responses: {
        "POST /api/auth/password": {
          status: 200,
          body: { next: "second_factor" },
        },
      },
    });
    await waitFor(() => expect(optionRequests(requests)).toHaveLength(1));

    await user.type(screen.getByLabelText("E-mail address"), "a@example.test");
    await user.type(screen.getByLabelText("Password"), "a long passphrase");
    await user.click(
      screen.getByRole("button", { name: "Continue with password" }),
    );
    expect(
      await screen.findByRole("heading", { name: "Confirm your sign-in" }),
    ).toBeInTheDocument();

    await act(() => vi.advanceTimersByTimeAsync(300_000));

    expect(optionRequests(requests)).toHaveLength(1);
    expect(webauthn.startAuthentication).toHaveBeenCalledTimes(1);
    expect(webauthn.cancelCeremony).toHaveBeenCalled();
  });

  test("the conditional request renews its options after 290 seconds", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const { requests } = renderSignIn();
    await waitFor(() => expect(optionRequests(requests)).toHaveLength(1));

    await act(() => vi.advanceTimersByTimeAsync(290_000));

    await waitFor(() => expect(optionRequests(requests)).toHaveLength(2));
    expect(webauthn.cancelCeremony).toHaveBeenCalledTimes(1);
  });

  test("a passkey the server rejects shows the generic message", async () => {
    webauthn.startAuthentication.mockResolvedValue(assertion);
    renderSignIn({
      responses: {
        "POST /api/auth/passkey": {
          status: 401,
          body: { error: "authentication_failed" },
        },
      },
    });

    const alerts = await screen.findAllByRole("alert");
    await waitFor(() =>
      expect(
        alerts.some(
          (alert) =>
            alert.textContent ===
            "Sign-in failed. Check your details and try again.",
        ),
      ).toBe(true),
    );
  });
});

describe("the passkey button", () => {
  test("stops the conditional request and signs in without autofill", async () => {
    const { requests, user, location } = renderSignIn({
      responses: {
        "POST /api/auth/passkey": {
          status: 200,
          body: signedInPayload("mfa"),
        },
        "GET /api/session": [{ status: 200, body: signedInPayload("mfa") }],
      },
    });
    await waitFor(() =>
      expect(webauthn.startAuthentication).toHaveBeenCalledTimes(1),
    );
    webauthn.startAuthentication.mockResolvedValueOnce(assertion);

    await user.click(
      screen.getByRole("button", { name: "Sign in with a passkey" }),
    );

    await waitFor(() => expect(location()).toBe("/programs/demo"));
    expect(webauthn.cancelCeremony).toHaveBeenCalled();
    expect(webauthn.startAuthentication).toHaveBeenLastCalledWith({
      optionsJSON: requestOptions,
    });
    expect(requestsTo(requests, "POST", "/api/auth/passkey")[0].body).toEqual(
      assertion,
    );
  });

  test("a closed passkey dialog shows its message and keeps every method", async () => {
    const { user } = renderSignIn({ session: sessionPayload({ providers }) });
    await waitFor(() =>
      expect(webauthn.startAuthentication).toHaveBeenCalledTimes(1),
    );
    webauthn.startAuthentication.mockRejectedValueOnce(
      Object.assign(new Error("closed"), {
        name: "NotAllowedError",
        code: "ERROR_PASSTHROUGH_SEE_CAUSE_PROPERTY",
      }),
    );

    await user.click(
      screen.getByRole("button", { name: "Sign in with a passkey" }),
    );

    expect(
      await screen.findByText(
        "The passkey request was closed or timed out. Try again or choose another way to sign in.",
      ),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("E-mail address")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Entra ID" }),
    ).toBeInTheDocument();
  });
});

describe("the password form", () => {
  test("a 401 shows the generic message in the alert region of the form", async () => {
    const { user } = renderSignIn({
      responses: {
        "POST /api/auth/password": {
          status: 401,
          body: { error: "invalid_credentials" },
        },
      },
    });

    await user.type(screen.getByLabelText("E-mail address"), "a@example.test");
    await user.type(screen.getByLabelText("Password"), "wrong");
    await user.click(
      screen.getByRole("button", { name: "Continue with password" }),
    );

    const form = screen.getByRole("form", {
      name: "Sign in with e-mail and password",
    });
    await waitFor(() =>
      expect(within(form).getByRole("alert")).toHaveTextContent(
        "Sign-in failed. Check your details and try again.",
      ),
    );
  });

  test("a 429 shows the wait time of Retry-After in minutes", async () => {
    const { user } = renderSignIn({
      responses: {
        "POST /api/auth/password": {
          status: 429,
          body: { error: "rate_limited" },
          headers: { "retry-after": "61" },
        },
      },
    });

    await user.type(screen.getByLabelText("E-mail address"), "a@example.test");
    await user.type(screen.getByLabelText("Password"), "wrong");
    await user.click(
      screen.getByRole("button", { name: "Continue with password" }),
    );

    expect(
      await screen.findByText("Too many attempts. Try again in 2 minutes."),
    ).toBeInTheDocument();
  });

  test("next second_factor moves focus to the heading of the second-factor step", async () => {
    const { user } = renderSignIn({
      responses: {
        "POST /api/auth/password": {
          status: 200,
          body: { next: "second_factor" },
        },
      },
    });

    await user.type(screen.getByLabelText("E-mail address"), "a@example.test");
    await user.type(screen.getByLabelText("Password"), "a long passphrase");
    await user.click(
      screen.getByRole("button", { name: "Continue with password" }),
    );

    const heading = await screen.findByRole("heading", {
      name: "Confirm your sign-in",
    });
    await waitFor(() => expect(heading).toHaveFocus());
  });

  test("the password field has a reveal button, autocomplete and no maxLength", async () => {
    const { user } = renderSignIn();
    const password = screen.getByLabelText("Password");

    expect(password).toHaveAttribute("type", "password");
    expect(password).toHaveAttribute("autocomplete", "current-password");
    expect(password).not.toHaveAttribute("maxlength");
    const reveal = screen.getByRole("button", { name: "Show password" });
    expect(reveal).toHaveAttribute("aria-pressed", "false");

    await user.type(password, "visible");
    await user.click(reveal);

    expect(password).toHaveAttribute("type", "text");
    expect(reveal).toHaveAttribute("aria-pressed", "true");
  });
});

describe("providers", () => {
  test("only providers with kind credentials render as forms", async () => {
    renderSignIn({ session: sessionPayload({ providers }) });

    expect(
      await screen.findByRole("form", { name: "Directory account" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("form", { name: "Entra ID" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Entra ID" }),
    ).toBeInTheDocument();
  });

  test("a provider click cancels the ceremony before window.location.assign with its start_url", async () => {
    const assign = stubLocationAssign();
    const order: string[] = [];
    webauthn.cancelCeremony.mockImplementation(() => order.push("cancel"));
    assign.mockImplementation(() => order.push("assign"));
    const { user } = renderSignIn({ session: sessionPayload({ providers }) });

    await user.click(await screen.findByRole("button", { name: "Entra ID" }));

    expect(assign).toHaveBeenCalledWith("/auth/oidc/entra");
    expect(order).toEqual(["cancel", "assign"]);
    expect(takeReturnTo()).toBe("/programs/demo");
  });

  test("an LDAP form with a whitespace-only password sends no request", async () => {
    const { requests, user } = renderSignIn({
      session: sessionPayload({ providers }),
    });
    const form = await screen.findByRole("form", { name: "Directory account" });

    await user.type(within(form).getByLabelText("User name"), "dora");
    await user.type(within(form).getByLabelText("Password"), "   ");
    await user.click(
      within(form).getByRole("button", {
        name: "Sign in with Directory account",
      }),
    );

    expect(
      requests.filter((request) => request.path.startsWith("/api/auth/ldap")),
    ).toEqual([]);
    expect(within(form).getByRole("alert")).toHaveTextContent(
      "Enter the user name and the password.",
    );
  });

  test("an LDAP form posts to the entry's start_url and opens the second factor", async () => {
    const { requests, user } = renderSignIn({
      session: sessionPayload({ providers }),
      responses: {
        "POST /api/auth/ldap/ldap": {
          status: 200,
          body: { next: "second_factor" },
        },
      },
    });
    const form = await screen.findByRole("form", { name: "Directory account" });

    await user.type(within(form).getByLabelText("User name"), "dora");
    await user.type(within(form).getByLabelText("Password"), "dir-secret");
    await user.click(
      within(form).getByRole("button", {
        name: "Sign in with Directory account",
      }),
    );

    expect(
      await screen.findByRole("heading", { name: "Confirm your sign-in" }),
    ).toBeInTheDocument();
    const posted = requests.filter((request) => request.method === "POST");
    expect(posted.at(-1)).toMatchObject({
      path: providers[1].start_url,
      body: { username: "dora", password: "dir-secret" },
    });
  });

  test("an LDAP answer link_required shows its message", async () => {
    const { user } = renderSignIn({
      session: sessionPayload({ providers }),
      responses: {
        "POST /api/auth/ldap/ldap": {
          status: 409,
          body: { error: "link_required" },
        },
      },
    });
    const form = await screen.findByRole("form", { name: "Directory account" });

    await user.type(within(form).getByLabelText("User name"), "dora");
    await user.type(within(form).getByLabelText("Password"), "dir-secret");
    await user.click(
      within(form).getByRole("button", {
        name: "Sign in with Directory account",
      }),
    );

    expect(
      await within(form).findByText(
        "An account with this e-mail address exists. Sign in to it and connect this account in your security settings.",
      ),
    ).toBeInTheDocument();
  });
});

describe("demo and links", () => {
  test("the demo list renders only with flags.demo", async () => {
    const first = renderSignIn();
    expect(
      screen.queryByRole("heading", { name: "Demo accounts" }),
    ).not.toBeInTheDocument();
    first.unmount();

    renderSignIn({ session: sessionPayload({ flags: { demo: true } }) });
    expect(
      await screen.findByRole("heading", { name: "Demo accounts" }),
    ).toBeInTheDocument();
    expect(
      screen.getAllByRole("button", { name: /^Test person \d+$/ }),
    ).toHaveLength(20);
  });

  test("a demo button signs in through the API client and opens the return path", async () => {
    const { requests, user, location } = renderSignIn({
      session: sessionPayload({ flags: { demo: true } }),
      responses: {
        "POST /api/auth/demo": { status: 200, body: signedInPayload("demo") },
        "GET /api/session": { status: 200, body: signedInPayload("demo") },
      },
    });

    await user.click(
      await screen.findByRole("button", { name: "Test person 3" }),
    );

    await waitFor(() => expect(location()).toBe("/programs/demo"));
    expect(requestsTo(requests, "POST", "/api/auth/demo")[0].body).toEqual({
      slot: 3,
    });
  });

  test("the invitation link appears only with signup invite or domain", async () => {
    const closed = renderSignIn();
    expect(
      screen.getByRole("link", {
        name: "Lost access to your sign-in methods?",
      }),
    ).toHaveAttribute("href", "/recover");
    expect(
      screen.queryByRole("link", { name: "Request an invitation link" }),
    ).not.toBeInTheDocument();
    closed.unmount();

    renderSignIn({ session: sessionPayload({ flags: { signup: "invite" } }) });
    expect(
      await screen.findByRole("link", { name: "Request an invitation link" }),
    ).toHaveAttribute("href", "/invite");
  });

  test("without local accounts only the providers remain", async () => {
    renderSignIn({
      session: sessionPayload({
        providers,
        flags: { local_accounts: false },
      }),
    });

    expect(
      await screen.findByRole("button", { name: "Entra ID" }),
    ).toBeInTheDocument();
    expect(screen.queryByLabelText("E-mail address")).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Sign in with a passkey" }),
    ).not.toBeInTheDocument();
    expect(webauthn.browserSupportsWebAuthnAutofill).not.toHaveBeenCalled();
  });
});

describe("session states", () => {
  test("an enrollment session goes on to /enroll", async () => {
    const { location } = renderSignIn({
      session: signedInPayload("enrollment"),
    });
    await waitFor(() => expect(location()).toBe("/enroll"));
  });

  test("a full session goes to return_to", async () => {
    const { location } = renderSignIn({ session: signedInPayload("mfa") });
    await waitFor(() => expect(location()).toBe("/programs/demo"));
  });

  test("a pending second factor opens the second-factor step", async () => {
    renderSignIn({
      session: sessionPayload({
        pending: {
          next: "second_factor",
          expires_at: "2026-10-11T10:05:00Z",
        },
      }),
    });

    expect(
      await screen.findByRole("heading", { name: "Confirm your sign-in" }),
    ).toBeInTheDocument();
  });
});

test("the sign-in page has no axe violations in light, dark and German", async () => {
  const { container } = renderSignIn({
    session: sessionPayload({
      providers,
      flags: { demo: true, signup: "invite" },
    }),
  });
  await screen.findByLabelText("E-mail address");

  await expectNoAxeViolations(container);
});

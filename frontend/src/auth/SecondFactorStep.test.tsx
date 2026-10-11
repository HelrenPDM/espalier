import { screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { expectNoAxeViolations } from "../test/axe";
import { renderWithProviders, requestsTo } from "../test/render";
import { sessionPayload, signedInPayload } from "../test/session";
import {
  assertion,
  requestOptions,
  resetWebAuthnMocks,
  webauthn,
  webauthnError,
} from "../test/webauthn";
import { SignInPage } from "./SignInPage";
import { takeReturnTo } from "./returnTo";

vi.mock("@simplewebauthn/browser");

const SECOND_FACTOR = "/api/auth/second-factor";
const OPTIONS = "/api/auth/passkey/options";

const pendingSession = () =>
  sessionPayload({
    pending: { next: "second_factor", expires_at: "2026-10-11T10:05:00Z" },
  });

beforeEach(() => {
  resetWebAuthnMocks();
});

afterEach(() => {
  vi.unstubAllGlobals();
  takeReturnTo();
});

/**
 * Renders `/sign-in` with a pending second factor, so `SignInPage` opens
 * the second-factor step at once.
 */
const renderStep = (options: Parameters<typeof renderWithProviders>[1] = {}) =>
  renderWithProviders(<SignInPage />, {
    route: "/sign-in?return_to=%2Fprograms%2Fdemo",
    session: pendingSession(),
    ...options,
    responses: {
      [`POST ${OPTIONS}`]: { status: 200, body: requestOptions },
      ...options.responses,
    },
  });

const heading = () =>
  screen.findByRole("heading", { name: "Confirm your sign-in" });

describe("the step itself", () => {
  test("the heading receives focus on mount", async () => {
    renderStep();

    const title = await heading();
    await waitFor(() => expect(title).toHaveFocus());
  });

  test("the code field is numeric, one-time-code, six digits and at most six characters", async () => {
    renderStep();
    await heading();

    const code = screen.getByLabelText("Six-digit code");
    expect(code).toHaveAttribute("inputmode", "numeric");
    expect(code).toHaveAttribute("autocomplete", "one-time-code");
    expect(code).toHaveAttribute("pattern", "[0-9]{6}");
    expect(code).toHaveAttribute("maxlength", "6");
  });

  test("the code form posts { totp } to the second-factor route", async () => {
    const { requests, user, location } = renderStep({
      responses: {
        [`POST ${SECOND_FACTOR}`]: {
          status: 200,
          body: signedInPayload("mfa"),
        },
        "GET /api/session": { status: 200, body: signedInPayload("mfa") },
      },
    });
    await heading();

    await user.type(screen.getByLabelText("Six-digit code"), "123456");
    await user.click(screen.getByRole("button", { name: "Confirm" }));

    await waitFor(() => expect(location()).toBe("/programs/demo"));
    expect(
      requestsTo(requests, "POST", SECOND_FACTOR).map(
        (request) => request.body,
      ),
    ).toEqual([{ totp: "123456" }]);
  });

  test("the step links to /recover", async () => {
    renderStep();
    await heading();

    expect(
      screen.getByRole("link", {
        name: "Lost access to your sign-in methods?",
      }),
    ).toHaveAttribute("href", "/recover");
  });
});

describe("the passkey", () => {
  test("a NotAllowedError shows the cancelled message and keeps the code field", async () => {
    webauthn.startAuthentication.mockRejectedValueOnce(
      webauthnError("NotAllowedError", "ERROR_PASSTHROUGH_SEE_CAUSE_PROPERTY"),
    );
    const { requests, user } = renderStep();
    await heading();

    await user.click(screen.getByRole("button", { name: "Use a passkey" }));

    expect(
      await screen.findByText(
        "The passkey request was closed or timed out. Try again or choose another way to sign in.",
      ),
    ).toHaveAttribute("role", "alert");
    expect(screen.getByLabelText("Six-digit code")).toBeInTheDocument();
    expect(requestsTo(requests, "POST", SECOND_FACTOR)).toEqual([]);
  });

  test("the passkey result goes out under the key passkey", async () => {
    webauthn.startAuthentication.mockResolvedValueOnce(assertion);
    const { requests, user, location } = renderStep({
      responses: {
        [`POST ${SECOND_FACTOR}`]: {
          status: 200,
          body: signedInPayload("mfa"),
        },
        "GET /api/session": { status: 200, body: signedInPayload("mfa") },
      },
    });
    await heading();

    await user.click(screen.getByRole("button", { name: "Use a passkey" }));

    await waitFor(() => expect(location()).toBe("/programs/demo"));
    expect(
      requestsTo(requests, "POST", OPTIONS).map((request) => request.body),
    ).toEqual([{ purpose: "second_factor" }]);
    expect(webauthn.startAuthentication).toHaveBeenCalledWith({
      optionsJSON: requestOptions,
    });
    expect(
      requestsTo(requests, "POST", SECOND_FACTOR).map(
        (request) => request.body,
      ),
    ).toEqual([{ passkey: assertion }]);
  });
});

describe("the recovery code", () => {
  test("Use a recovery code swaps the field and posts { recovery_code }", async () => {
    const { requests, user } = renderStep({
      responses: {
        [`POST ${SECOND_FACTOR}`]: {
          status: 200,
          body: { ...signedInPayload("mfa"), recovery_codes_remaining: 9 },
        },
        "GET /api/session": { status: 200, body: signedInPayload("mfa") },
      },
    });
    await heading();

    await user.click(
      screen.getByRole("button", { name: "Use a recovery code" }),
    );

    expect(screen.queryByLabelText("Six-digit code")).not.toBeInTheDocument();
    const field = screen.getByLabelText("Recovery code");
    expect(field).toHaveAttribute("autocomplete", "off");
    expect(field).toHaveAttribute("spellcheck", "false");
    expect(
      screen.getByRole("button", { name: "Use the authenticator app" }),
    ).toBeInTheDocument();

    await user.type(field, "abcd-efgh-ijkl");
    await user.click(screen.getByRole("button", { name: "Confirm" }));

    await waitFor(() =>
      expect(requestsTo(requests, "POST", SECOND_FACTOR)).toHaveLength(1),
    );
    expect(requestsTo(requests, "POST", SECOND_FACTOR)[0].body).toEqual({
      recovery_code: "abcd-efgh-ijkl",
    });
  });

  test("recovery_codes_remaining leads to /account/security with the count in the location state", async () => {
    const { requests, router, user, location } = renderStep({
      responses: {
        [`POST ${SECOND_FACTOR}`]: {
          status: 200,
          body: { ...signedInPayload("mfa"), recovery_codes_remaining: 3 },
        },
        "GET /api/session": { status: 200, body: signedInPayload("mfa") },
      },
    });
    await heading();

    await user.click(
      screen.getByRole("button", { name: "Use a recovery code" }),
    );
    await user.type(screen.getByLabelText("Recovery code"), "abcd-efgh");
    await user.click(screen.getByRole("button", { name: "Confirm" }));

    await waitFor(() => expect(location()).toBe("/account/security"));
    expect(router.state.location.state).toEqual({ recoveryCodesRemaining: 3 });
    // sessionChanged("signed-in") refetched the session before the navigation.
    expect(requestsTo(requests, "GET", "/api/session")).not.toHaveLength(0);
  });
});

describe("failures", () => {
  test("a 401 keeps the step and shows the generic message", async () => {
    const { requests, user } = renderStep({
      responses: {
        [`POST ${SECOND_FACTOR}`]: {
          status: 401,
          body: { error: "authentication_failed" },
        },
      },
    });
    await heading();

    await user.type(screen.getByLabelText("Six-digit code"), "000000");
    await user.click(screen.getByRole("button", { name: "Confirm" }));

    expect(
      await screen.findByText(
        "Sign-in failed. Check your details and try again.",
      ),
    ).toHaveAttribute("role", "alert");
    await waitFor(() =>
      expect(requestsTo(requests, "GET", "/api/session")).not.toHaveLength(0),
    );
    expect(
      screen.getByRole("heading", { name: "Confirm your sign-in" }),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("Six-digit code")).toBeInTheDocument();
  });

  test("a 401 whose refetched session has no pending returns to the first step with the restart message", async () => {
    const { user } = renderStep({
      responses: {
        [`POST ${SECOND_FACTOR}`]: {
          status: 401,
          body: { error: "authentication_failed" },
        },
        "GET /api/session": { status: 200, body: sessionPayload() },
      },
    });
    await heading();

    await user.type(screen.getByLabelText("Six-digit code"), "000000");
    await user.click(screen.getByRole("button", { name: "Confirm" }));

    expect(
      await screen.findByText("Sign-in failed. Please start again."),
    ).toHaveAttribute("role", "alert");
    expect(
      screen.getByRole("heading", { name: "Sign in" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Confirm your sign-in" }),
    ).not.toBeInTheDocument();
  });
});

test("the second-factor step has no axe violations in light, dark and German", async () => {
  const { container } = renderStep();
  await heading();

  await expectNoAxeViolations(container);
});

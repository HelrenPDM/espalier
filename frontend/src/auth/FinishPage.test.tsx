import { screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { expectNoAxeViolations } from "../test/axe";
import { renderWithProviders, requestsTo } from "../test/render";
import { sessionPayload, signedInPayload } from "../test/session";
import { resetWebAuthnMocks } from "../test/webauthn";
import { FinishPage } from "./FinishPage";
import { rememberReturnTo, takeReturnTo } from "./returnTo";

vi.mock("@simplewebauthn/browser");

const FINISH = "/api/auth/finish";

beforeEach(() => {
  resetWebAuthnMocks();
});

afterEach(() => {
  vi.unstubAllGlobals();
  takeReturnTo();
});

const renderFinish = (
  options: Parameters<typeof renderWithProviders>[1] = {},
) =>
  renderWithProviders(<FinishPage />, {
    route: "/auth/finish#ticket=ticket-1",
    ...options,
  });

const posts = (requests: { method: string }[]) =>
  requests.filter((request) => request.method === "POST");

describe("the ticket", () => {
  test("inside StrictMode the ticket is posted once and the fragment is gone afterwards", async () => {
    const { requests } = renderFinish({
      strict: true,
      responses: {
        [`POST ${FINISH}`]: { status: 200, body: { next: "second_factor" } },
      },
    });

    expect(
      await screen.findByRole("heading", { name: "Confirm your sign-in" }),
    ).toBeInTheDocument();
    expect(
      requestsTo(requests, "POST", FINISH).map((request) => request.body),
    ).toEqual([{ ticket: "ticket-1" }]);
    expect(window.location.hash).toBe("");
  });

  test("a missing ticket shows the generic message without a request", async () => {
    const { requests } = renderFinish({ route: "/auth/finish" });

    expect(
      await screen.findByText(
        "Sign-in failed. Check your details and try again.",
      ),
    ).toHaveAttribute("role", "alert");
    expect(posts(requests)).toEqual([]);
  });
});

describe("the answers of README 6.12", () => {
  test('{"next": "second_factor"} renders the second-factor step', async () => {
    renderFinish({
      responses: {
        [`POST ${FINISH}`]: { status: 200, body: { next: "second_factor" } },
      },
    });

    expect(
      await screen.findByRole("heading", { name: "Confirm your sign-in" }),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("Six-digit code")).toBeInTheDocument();
  });

  test('{"next": "enroll_second_factor"} refetches the session and leads to /enroll', async () => {
    const { requests, location } = renderFinish({
      responses: {
        [`POST ${FINISH}`]: {
          status: 200,
          body: { next: "enroll_second_factor" },
        },
        "GET /api/session": {
          status: 200,
          body: signedInPayload("enrollment"),
        },
      },
    });

    await waitFor(() => expect(location()).toBe("/enroll"));
    expect(requestsTo(requests, "GET", "/api/session")).not.toHaveLength(0);
  });

  test("a session body without next leads to the remembered return path and deletes it", async () => {
    rememberReturnTo("/programs/demo");
    const { requests, location } = renderFinish({
      responses: {
        [`POST ${FINISH}`]: { status: 200, body: signedInPayload("mfa") },
        "GET /api/session": { status: 200, body: signedInPayload("mfa") },
      },
    });

    await waitFor(() => expect(location()).toBe("/programs/demo"));
    expect(takeReturnTo()).toBeNull();
    expect(requestsTo(requests, "GET", "/api/session")).not.toHaveLength(0);
  });

  test("a session body with linked true shows the linked message in a status region", async () => {
    rememberReturnTo("/account/security");
    const { location } = renderFinish({
      session: signedInPayload("mfa"),
      responses: {
        [`POST ${FINISH}`]: {
          status: 200,
          body: { ...signedInPayload("mfa"), linked: true },
        },
      },
    });

    expect(
      await screen.findByText("The account is connected."),
    ).toHaveAttribute("role", "status");
    expect(location()).toMatch(/^\/auth\/finish/);
    expect(takeReturnTo()).toBeNull();
  });
});

describe("errors", () => {
  test("?error=oidc_failed shows the generic message without a request", async () => {
    const { requests } = renderFinish({
      route: "/auth/finish?error=oidc_failed",
    });

    expect(
      await screen.findByText(
        "Sign-in failed. Check your details and try again.",
      ),
    ).toHaveAttribute("role", "alert");
    expect(posts(requests)).toEqual([]);
  });

  test("?error=oidc_identity_in_use shows the identity-in-use message without a request", async () => {
    const { requests } = renderFinish({
      route: "/auth/finish?error=oidc_identity_in_use",
    });

    expect(
      await screen.findByText("This sign-in belongs to another account."),
    ).toHaveAttribute("role", "alert");
    expect(posts(requests)).toEqual([]);
  });

  test("a 409 provider_already_linked shows its message", async () => {
    renderFinish({
      session: signedInPayload("mfa"),
      responses: {
        [`POST ${FINISH}`]: {
          status: 409,
          body: { error: "provider_already_linked" },
        },
      },
    });

    expect(
      await screen.findByText(
        "Your account is already connected to this provider.",
      ),
    ).toHaveAttribute("role", "alert");
  });

  test("a 401 ticket_invalid shows the generic message", async () => {
    renderFinish({
      responses: {
        [`POST ${FINISH}`]: { status: 401, body: { error: "ticket_invalid" } },
      },
    });

    expect(
      await screen.findByText(
        "Sign-in failed. Check your details and try again.",
      ),
    ).toHaveAttribute("role", "alert");
  });
});

describe("the link under a message", () => {
  test("goes to /sign-in without a user", async () => {
    renderFinish({
      session: sessionPayload(),
      route: "/auth/finish?error=oidc_failed",
    });

    expect(
      await screen.findByRole("link", { name: "Go to the sign-in page" }),
    ).toHaveAttribute("href", "/sign-in");
    expect(
      screen.queryByRole("link", { name: "Go to the security settings" }),
    ).not.toBeInTheDocument();
  });

  test("goes to /account/security with a user", async () => {
    renderFinish({
      session: signedInPayload("mfa"),
      route: "/auth/finish?error=oidc_identity_in_use",
    });

    expect(
      await screen.findByRole("link", { name: "Go to the security settings" }),
    ).toHaveAttribute("href", "/account/security");
    expect(
      screen.queryByRole("link", { name: "Go to the sign-in page" }),
    ).not.toBeInTheDocument();
  });
});

test("the finish page has no axe violations in light, dark and German", async () => {
  const { container } = renderFinish({
    session: signedInPayload("mfa"),
    responses: {
      [`POST ${FINISH}`]: {
        status: 200,
        body: { ...signedInPayload("mfa"), linked: true },
      },
    },
  });
  await screen.findByText("The account is connected.");

  await expectNoAxeViolations(container);
});

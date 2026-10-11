import { screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import { expectNoAxeViolations } from "../test/axe";
import { renderWithProviders, requestsTo } from "../test/render";
import { sessionPayload, signedInPayload } from "../test/session";
import { InvitationPage } from "./InvitationPage";
import { takeReturnTo } from "./returnTo";

const ACCEPT = "/api/auth/invitations/accept";
const REQUEST = "/api/auth/invitations";

afterEach(() => {
  vi.unstubAllGlobals();
  takeReturnTo();
});

const renderInvitation = (
  options: Parameters<typeof renderWithProviders>[1] = {},
) =>
  renderWithProviders(<InvitationPage />, {
    route: "/invite#token=invite-token-1",
    ...options,
  });

const continueButton = () => screen.findByRole("button", { name: "Continue" });

describe("with a token", () => {
  test("no request leaves before the click", async () => {
    const { requests } = renderInvitation();

    expect(
      await screen.findByRole("heading", { name: "Accept the invitation" }),
    ).toBeInTheDocument();
    await continueButton();

    expect(requests).toEqual([]);
  });

  test("the fragment is gone after mount", async () => {
    renderInvitation();
    await continueButton();

    expect(window.location.hash).toBe("");
  });

  test("inside StrictMode the posted body carries the token and success leads to /enroll", async () => {
    const { requests, user, location } = renderInvitation({
      strict: true,
      responses: {
        [`POST ${ACCEPT}`]: {
          status: 200,
          body: signedInPayload("enrollment"),
        },
        "GET /api/session": {
          status: 200,
          body: signedInPayload("enrollment"),
        },
      },
    });

    await user.click(await continueButton());

    await waitFor(() => expect(location()).toBe("/enroll"));
    expect(
      requestsTo(requests, "POST", ACCEPT).map((request) => request.body),
    ).toEqual([{ token: "invite-token-1" }]);
    expect(requestsTo(requests, "GET", "/api/session")).not.toHaveLength(0);
  });

  test("a 400 invalid_token shows the invalid-link message", async () => {
    const { user, location } = renderInvitation({
      responses: {
        [`POST ${ACCEPT}`]: { status: 400, body: { error: "invalid_token" } },
      },
    });

    await user.click(await continueButton());

    expect(
      await screen.findByText(
        "This link is invalid or has expired. Please ask for a new one.",
      ),
    ).toHaveAttribute("role", "alert");
    expect(location()).toMatch(/^\/invite/);
  });
});

describe("without a token", () => {
  test("with signup invite the e-mail form posts { email } and shows the sent message", async () => {
    const { requests, user } = renderInvitation({
      route: "/invite",
      session: sessionPayload({ flags: { signup: "invite" } }),
      responses: { [`POST ${REQUEST}`]: { status: 202 } },
    });

    expect(
      await screen.findByRole("heading", { name: "Request an invitation" }),
    ).toBeInTheDocument();
    await user.type(screen.getByLabelText("E-mail address"), "a@example.test");
    await user.click(
      screen.getByRole("button", { name: "Send an invitation link" }),
    );

    expect(
      await screen.findByText(
        "If the address can receive an invitation, we have sent a link to it.",
      ),
    ).toHaveAttribute("role", "status");
    expect(
      requestsTo(requests, "POST", REQUEST).map((request) => request.body),
    ).toEqual([{ email: "a@example.test" }]);
  });

  test("an error answer other than 429 shows the same sent message", async () => {
    const { user } = renderInvitation({
      route: "/invite",
      session: sessionPayload({ flags: { signup: "domain" } }),
      responses: {
        [`POST ${REQUEST}`]: { status: 422, body: { error: "invalid" } },
      },
    });

    await user.type(
      await screen.findByLabelText("E-mail address"),
      "b@example.test",
    );
    await user.click(
      screen.getByRole("button", { name: "Send an invitation link" }),
    );

    expect(
      await screen.findByText(
        "If the address can receive an invitation, we have sent a link to it.",
      ),
    ).toHaveAttribute("role", "status");
  });

  test("a 429 on the request form shows the too-many-attempts message", async () => {
    const { user } = renderInvitation({
      route: "/invite",
      session: sessionPayload({ flags: { signup: "invite" } }),
      responses: {
        [`POST ${REQUEST}`]: {
          status: 429,
          body: { error: "rate_limited" },
          headers: { "retry-after": "120" },
        },
      },
    });

    await user.type(
      await screen.findByLabelText("E-mail address"),
      "a@example.test",
    );
    await user.click(
      screen.getByRole("button", { name: "Send an invitation link" }),
    );

    expect(
      await screen.findByText("Too many attempts. Try again in 2 minutes."),
    ).toHaveAttribute("role", "alert");
    expect(
      screen.queryByText(
        "If the address can receive an invitation, we have sent a link to it.",
      ),
    ).not.toBeInTheDocument();
  });

  test("with signup closed no form renders and the invalid-link message shows", async () => {
    const { container, requests } = renderInvitation({
      route: "/invite",
      session: sessionPayload({ flags: { signup: "closed" } }),
    });

    expect(
      await screen.findByText(
        "This link is invalid or has expired. Please ask for a new one.",
      ),
    ).toHaveAttribute("role", "alert");
    expect(container.querySelector("form")).toBeNull();
    expect(screen.queryByLabelText("E-mail address")).not.toBeInTheDocument();
    expect(requests).toEqual([]);
  });
});

test("the invitation page has no axe violations in light, dark and German", async () => {
  const { container } = renderInvitation({
    route: "/invite",
    session: sessionPayload({ flags: { signup: "invite" } }),
  });
  await screen.findByLabelText("E-mail address");

  await expectNoAxeViolations(container);
});

import { act, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import { sessionQueryKey, toSession } from "../api/session";
import { expectNoAxeViolations } from "../test/axe";
import { renderWithProviders, requestsTo } from "../test/render";
import { sessionPayload, signedInPayload } from "../test/session";
import { EmailConfirmPage } from "./EmailConfirmPage";
import { takeReturnTo } from "../auth/returnTo";

const CONFIRM = "/api/me/email/confirm";
const LINK_INVALID =
  "This link is invalid or has expired. Please ask for a new one.";

afterEach(() => {
  vi.unstubAllGlobals();
  takeReturnTo();
});

const renderConfirm = (
  options: Parameters<typeof renderWithProviders>[1] = {},
) =>
  renderWithProviders(<EmailConfirmPage />, {
    route: "/account/email/confirm#token=email-token-1",
    session: signedInPayload("mfa"),
    ...options,
  });

const confirmButton = () =>
  screen.findByRole("button", { name: "Confirm new address" });

describe("the token", () => {
  test("inside StrictMode nothing is posted before the click and the body carries the token from the fragment", async () => {
    const { requests, user } = renderConfirm({
      strict: true,
      responses: { [`POST ${CONFIRM}`]: { status: 204 } },
    });

    const button = await confirmButton();
    expect(window.location.hash).toBe("");
    expect(requestsTo(requests, "POST", CONFIRM)).toEqual([]);

    await user.click(button);

    await waitFor(() =>
      expect(requestsTo(requests, "POST", CONFIRM)).toHaveLength(1),
    );
    expect(requestsTo(requests, "POST", CONFIRM)[0].body).toEqual({
      token: "email-token-1",
    });
  });

  test("without a token the page shows the invalid-link message and no button", async () => {
    renderConfirm({ route: "/account/email/confirm" });

    expect(await screen.findByText(LINK_INVALID)).toHaveAttribute(
      "role",
      "alert",
    );
    expect(
      screen.queryByRole("button", { name: "Confirm new address" }),
    ).not.toBeInTheDocument();
  });
});

describe("the answers", () => {
  test("success shows the changed message", async () => {
    const { user } = renderConfirm({
      responses: { [`POST ${CONFIRM}`]: { status: 204 } },
    });

    await user.click(await confirmButton());

    expect(
      await screen.findByText("Your e-mail address was changed."),
    ).toHaveAttribute("role", "status");
    expect(
      screen.queryByRole("button", { name: "Confirm new address" }),
    ).not.toBeInTheDocument();
  });

  test("a 400 invalid_token shows the invalid-link message", async () => {
    const { user } = renderConfirm({
      responses: {
        [`POST ${CONFIRM}`]: { status: 400, body: { error: "invalid_token" } },
      },
    });

    await user.click(await confirmButton());

    expect(await screen.findByText(LINK_INVALID)).toHaveAttribute(
      "role",
      "alert",
    );
    expect(
      screen.queryByRole("button", { name: "Confirm new address" }),
    ).not.toBeInTheDocument();
  });

  test("a 401 offers the sign-in in a new tab and enables the button again once the session shows a user", async () => {
    const { requests, user, queryClient } = renderConfirm({
      session: sessionPayload(),
      responses: {
        [`POST ${CONFIRM}`]: [
          { status: 401, body: { error: "unauthenticated" } },
          { status: 204 },
        ],
      },
    });

    await user.click(await confirmButton());

    const link = await screen.findByRole("link", {
      name: "Sign in in a new tab",
    });
    expect(link).toHaveAttribute("href", "/sign-in");
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
    expect(
      screen.getByText(
        "Sign in to the account first. The button works again once you are signed in.",
      ),
    ).toHaveAttribute("role", "alert");
    expect(
      screen.getByRole("button", { name: "Confirm new address" }),
    ).toBeDisabled();
    // The 401 invalidates the session query; its refetch still shows no user.
    await waitFor(() => expect(queryClient.isFetching()).toBe(0));
    expect(
      screen.getByRole("button", { name: "Confirm new address" }),
    ).toBeDisabled();

    act(() => {
      queryClient.setQueryData(
        sessionQueryKey,
        toSession(signedInPayload("mfa")),
      );
    });

    const button = screen.getByRole("button", { name: "Confirm new address" });
    await waitFor(() => expect(button).toBeEnabled());
    await user.click(button);

    expect(
      await screen.findByText("Your e-mail address was changed."),
    ).toHaveAttribute("role", "status");
    expect(
      requestsTo(requests, "POST", CONFIRM).map((request) => request.body),
    ).toEqual([{ token: "email-token-1" }, { token: "email-token-1" }]);
  });
});

test("the e-mail confirmation page has no axe violations in light, dark and German", async () => {
  const { container } = renderConfirm();
  await confirmButton();

  await expectNoAxeViolations(container);
});

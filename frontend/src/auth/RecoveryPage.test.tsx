import { screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import { expectNoAxeViolations } from "../test/axe";
import { renderWithProviders, requestsTo } from "../test/render";
import { signedInPayload } from "../test/session";
import { RecoveryPage } from "./RecoveryPage";
import { takeReturnTo } from "./returnTo";

const START = "/api/auth/recovery/start";
const VERIFY = "/api/auth/recovery/verify";
const SENT = "If the address belongs to an account, we have sent a link to it.";

afterEach(() => {
  vi.unstubAllGlobals();
  takeReturnTo();
});

const renderRecovery = (
  options: Parameters<typeof renderWithProviders>[1] = {},
) =>
  renderWithProviders(<RecoveryPage />, {
    route: "/recover#token=recovery-token-1",
    ...options,
  });

describe("opened from the mail", () => {
  test("inside StrictMode the posted body carries the token from the fragment and success leads to /enroll", async () => {
    const { requests, user, location } = renderRecovery({
      strict: true,
      responses: {
        [`POST ${VERIFY}`]: { status: 200, body: signedInPayload("recovery") },
        "GET /api/session": { status: 200, body: signedInPayload("recovery") },
      },
    });

    await user.type(
      await screen.findByLabelText("Recovery code"),
      "ABCD-EFGH-IJKL",
    );
    await user.click(screen.getByRole("button", { name: "Recover access" }));

    await waitFor(() => expect(location()).toBe("/enroll"));
    expect(
      requestsTo(requests, "POST", VERIFY).map((request) => request.body),
    ).toEqual([{ token: "recovery-token-1", recovery_code: "ABCD-EFGH-IJKL" }]);
    expect(requestsTo(requests, "GET", "/api/session")).not.toHaveLength(0);
  });

  test("the fragment is gone after mount and nothing is posted before the submit", async () => {
    const { requests } = renderRecovery();

    await screen.findByLabelText("Recovery code");

    expect(window.location.hash).toBe("");
    expect(requests).toEqual([]);
  });

  test("a 401 shows the recovery-failed message and keeps the token for a second submit", async () => {
    const { requests, user } = renderRecovery({
      responses: {
        [`POST ${VERIFY}`]: {
          status: 401,
          body: { error: "recovery_failed" },
        },
      },
    });
    const field = await screen.findByLabelText("Recovery code");

    await user.type(field, "WRONG-CODE");
    await user.click(screen.getByRole("button", { name: "Recover access" }));
    expect(
      await screen.findByText(
        "The recovery code did not match, or the link has expired.",
      ),
    ).toHaveAttribute("role", "alert");

    await user.clear(field);
    await user.type(field, "OTHER-CODE");
    await user.click(screen.getByRole("button", { name: "Recover access" }));

    await waitFor(() =>
      expect(requestsTo(requests, "POST", VERIFY)).toHaveLength(2),
    );
    expect(
      requestsTo(requests, "POST", VERIFY).map((request) => request.body),
    ).toEqual([
      { token: "recovery-token-1", recovery_code: "WRONG-CODE" },
      { token: "recovery-token-1", recovery_code: "OTHER-CODE" },
    ]);
  });

  test("a 429 shows the too-many-attempts message", async () => {
    const { user } = renderRecovery({
      responses: {
        [`POST ${VERIFY}`]: {
          status: 429,
          body: { error: "rate_limited" },
          headers: { "retry-after": "120" },
        },
      },
    });

    await user.type(await screen.findByLabelText("Recovery code"), "CODE");
    await user.click(screen.getByRole("button", { name: "Recover access" }));

    expect(
      await screen.findByText("Too many attempts. Try again in 2 minutes."),
    ).toHaveAttribute("role", "alert");
  });
});

describe("without a fragment", () => {
  test("the e-mail form posts { email } to the start route and shows the sent message", async () => {
    const { requests, user } = renderRecovery({
      route: "/recover",
      responses: { [`POST ${START}`]: { status: 202 } },
    });

    await user.type(
      await screen.findByLabelText("E-mail address"),
      "a@example.test",
    );
    await user.click(
      screen.getByRole("button", { name: "Send the recovery link" }),
    );

    expect(await screen.findByText(SENT)).toHaveAttribute("role", "status");
    expect(
      requestsTo(requests, "POST", START).map((request) => request.body),
    ).toEqual([{ email: "a@example.test" }]);
    expect(requestsTo(requests, "POST", VERIFY)).toEqual([]);
  });

  test("the sent message shows also when the server answers an error", async () => {
    const { user } = renderRecovery({
      route: "/recover",
      responses: {
        [`POST ${START}`]: { status: 500, body: { error: "internal" } },
      },
    });

    await user.type(
      await screen.findByLabelText("E-mail address"),
      "a@example.test",
    );
    await user.click(
      screen.getByRole("button", { name: "Send the recovery link" }),
    );

    expect(await screen.findByText(SENT)).toHaveAttribute("role", "status");
  });
});

test("the recovery page has no axe violations in light, dark and German", async () => {
  const { container } = renderRecovery();
  await screen.findByLabelText("Recovery code");

  await expectNoAxeViolations(container);
});

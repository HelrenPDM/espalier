import { screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { SecuritySummary } from "../api/account";
import { expectNoAxeViolations } from "../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../test/render";
import { signedInPayload } from "../test/session";
import { PasswordSection } from "./PasswordSection";
import { takeReturnTo } from "../auth/returnTo";

/** 15 code points as typed, 14 after NFC (the length test value of 0004 step 45). */
const NFD = "Lernpfad Café!";
const GUIDANCE =
  "Use at least 15 characters. A passphrase of several unrelated words reaches that length. Avoid well-known phrases, the name of this service and your own name or e-mail address.";
const REJECTED =
  "The new password was not accepted. The reason is shown below the field.";

const security = (
  overrides: Partial<SecuritySummary> = {},
): SecuritySummary => ({
  admin_passkey_required: false,
  linked_providers: [],
  passkeys: [],
  password_set: true,
  recent_auth_until: null,
  recovery_codes: { generated_at: "2026-10-01T10:00:00Z", remaining: 10 },
  totp: { enabled: true, enabled_at: "2026-10-01T10:00:00Z" },
  ...overrides,
});

const renderSection = ({
  summary = security(),
  responses = {},
}: { summary?: SecuritySummary; responses?: StubResponses } = {}) =>
  renderWithProviders(<PasswordSection security={summary} />, {
    route: "/account/security",
    session: signedInPayload("mfa"),
    responses,
  });

const rejected = (fields: Record<string, string[]>) => ({
  "PUT /api/me/password": {
    status: 422,
    body: { error: "validation_failed", fields },
  },
});

/** The ids in `aria-describedby` of `element`. */
const describedBy = (element: HTMLElement) =>
  (element.getAttribute("aria-describedby") ?? "").split(/\s+/).filter(Boolean);

/** The text of each element that `aria-describedby` of `element` names. */
const descriptions = (element: HTMLElement) =>
  describedBy(element).map(
    (id) => document.getElementById(id)?.textContent ?? null,
  );

const currentField = () => screen.getByLabelText("Current password");
const newField = () => screen.getByLabelText("New password");

async function submit(
  user: ReturnType<typeof renderSection>["user"],
  current: string,
  password: string,
) {
  await user.type(currentField(), current);
  await user.type(newField(), password);
  await user.click(screen.getByRole("button", { name: "Change the password" }));
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  takeReturnTo();
});

describe("a 422 validation_failed on the new password", () => {
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
    "%s shows its field error with aria-invalid and aria-describedby next to the guidance",
    async (code, message) => {
      const { user } = renderSection({
        responses: rejected({ password: [code] }),
      });

      await submit(user, "the current passphrase", "a long enough passphrase");

      const field = await screen.findByText(message);
      const input = newField();
      expect(input).toHaveAttribute("aria-invalid", "true");
      const ids = describedBy(input);
      const errorId = field.closest("[id]")?.id;
      const guidanceId = screen.getByText(GUIDANCE).id;
      expect(errorId).toBeTruthy();
      expect(guidanceId).toBeTruthy();
      expect(ids).toEqual(expect.arrayContaining([guidanceId, errorId]));
      expect(input).toHaveAccessibleDescription(
        expect.stringContaining(message),
      );
      expect(input).toHaveAccessibleDescription(
        expect.stringContaining(GUIDANCE),
      );
      expect(screen.getByRole("alert")).toHaveTextContent(REJECTED);
      expect(currentField()).not.toHaveAttribute("aria-invalid");
    },
  );
});

describe("a 422 validation_failed on the current password", () => {
  test.each([
    ["invalid", "The current password is not correct."],
    ["required", "Enter your current password."],
  ])(
    "%s shows its message at the current-password field",
    async (code, message) => {
      const { user } = renderSection({
        responses: rejected({ current_password: [code] }),
      });

      await submit(user, "a wrong passphrase", "a long enough passphrase");

      await waitFor(() =>
        expect(currentField()).toHaveAttribute("aria-invalid", "true"),
      );
      const current = currentField();
      expect(descriptions(current)).toContain(message);
      expect(current).toHaveAccessibleDescription(
        expect.stringContaining(message),
      );
      expect(newField()).not.toHaveAttribute("aria-invalid");
      expect(descriptions(newField())).not.toContain(message);
      expect(screen.getByRole("alert")).toHaveTextContent(message);
    },
  );
});

test("the counter shows code points after NFC, and the body carries the password as typed", async () => {
  const { requests, user } = renderSection({
    responses: {
      "PUT /api/me/password": { status: 200, body: signedInPayload("mfa") },
    },
  });
  expect(NFD).toHaveLength(15);

  await user.type(newField(), NFD);

  expect(newField()).toHaveValue(NFD);
  expect(screen.getByText("14 characters (15 to 128)")).toBeInTheDocument();
  expect(newField()).toHaveAccessibleDescription(
    expect.stringContaining("14 characters (15 to 128)"),
  );

  await user.type(currentField(), "the current passphrase");
  await user.click(screen.getByRole("button", { name: "Change the password" }));

  await waitFor(() =>
    expect(requestsTo(requests, "PUT", "/api/me/password")).toHaveLength(1),
  );
  const [put] = requestsTo(requests, "PUT", "/api/me/password");
  expect(put.body).toStrictEqual({
    current_password: "the current passphrase",
    password: NFD,
  });
  const sent = (put.body as { password: string }).password;
  expect(sent).toBe(NFD);
  expect(sent).not.toBe(NFD.normalize("NFC"));
  expect([...sent]).toHaveLength(15);
});

test("success refetches the session and shows the confirmation in a status region", async () => {
  const { requests, user } = renderSection({
    responses: {
      "PUT /api/me/password": { status: 200, body: signedInPayload("mfa") },
    },
  });

  await submit(user, "the current passphrase", "a new long passphrase");

  await waitFor(() =>
    expect(screen.getByRole("status")).toHaveTextContent(
      "The password was changed. Your other sessions have ended.",
    ),
  );
  const put = requests.findIndex(
    (request) =>
      request.method === "PUT" && request.path === "/api/me/password",
  );
  const refetch = requests.findIndex(
    (request, index) =>
      index > put &&
      request.method === "GET" &&
      request.path === "/api/session",
  );
  expect(put).toBeGreaterThanOrEqual(0);
  expect(refetch).toBeGreaterThan(put);
  expect(currentField()).toHaveValue("");
  expect(newField()).toHaveValue("");
});

test("an account with a linked provider shows the external notice and no form", () => {
  const { container } = renderSection({
    summary: security({ linked_providers: ["ldap"], password_set: true }),
  });

  expect(
    screen.getByText(
      "This account signs in through a connected provider and has no password sign-in.",
    ),
  ).toBeInTheDocument();
  expect(container.querySelector("form")).toBeNull();
  expect(container.querySelector("input")).toBeNull();
  expect(screen.queryByLabelText("New password")).not.toBeInTheDocument();
});

test("both password fields are masked, have autocomplete, no maxlength and reveal buttons", async () => {
  const { user } = renderSection();
  const current = currentField();
  const fresh = newField();

  expect(current).toHaveAttribute("type", "password");
  expect(fresh).toHaveAttribute("type", "password");
  expect(current).toHaveAttribute("autocomplete", "current-password");
  expect(fresh).toHaveAttribute("autocomplete", "new-password");
  expect(current).not.toHaveAttribute("maxlength");
  expect(fresh).not.toHaveAttribute("maxlength");

  const reveals = screen.getAllByRole("button", { name: "Show password" });
  expect(reveals).toHaveLength(2);
  for (const reveal of reveals)
    expect(reveal).toHaveAttribute("aria-pressed", "false");
  const revealFor = (input: HTMLElement) => {
    const button = reveals.find(
      (reveal) => reveal.getAttribute("aria-controls") === input.id,
    );
    if (!button) throw new Error(`no reveal button for ${input.id}`);
    return button;
  };

  await user.type(fresh, "visible passphrase");
  await user.click(revealFor(fresh));

  expect(fresh).toHaveAttribute("type", "text");
  expect(revealFor(fresh)).toHaveAttribute("aria-pressed", "true");
  expect(current).toHaveAttribute("type", "password");
  expect(revealFor(current)).toHaveAttribute("aria-pressed", "false");
});

test("paste works in both password fields", async () => {
  const { user } = renderSection();

  await user.click(currentField());
  await user.paste("pasted current passphrase");
  await user.click(newField());
  await user.paste("pasted new passphrase");

  expect(currentField()).toHaveValue("pasted current passphrase");
  expect(newField()).toHaveValue("pasted new passphrase");
});

test("the section has no axe violations in light, dark and German", async () => {
  const { container, user } = renderSection({
    responses: rejected({ password: ["common"] }),
  });
  const section = screen.getByRole("region", { name: "Password" });

  await submit(user, "the current passphrase", "a long enough passphrase");
  await within(section).findByText(
    "This password is on a list of commonly used passwords. Choose a different one.",
  );

  await expectNoAxeViolations(container);
});

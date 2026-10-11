import { screen, waitFor, within } from "@testing-library/react";
import type { QueryClient } from "@tanstack/react-query";
import { afterEach, expect, test, vi } from "vitest";
import { expectNoAxeViolations } from "../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../test/render";
import { signedInPayload } from "../test/session";
import { TotpSetup } from "./TotpSetup";
import { takeReturnTo } from "../auth/returnTo";

const SECRET = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP";
const GROUPED = "JBSW Y3DP EHPK 3PXP JBSW Y3DP EHPK 3PXP";
const QR =
  "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciLz4=";

const enrollment = (qr = QR) => ({
  otpauth_uri: `otpauth://totp/Espalier:ada%40example.test?secret=${SECRET}&issuer=Espalier`,
  qr_svg_data_url: qr,
  secret_base32: SECRET,
});

const confirmed = {
  other_sessions: 0,
  totp: { enabled: true, enabled_at: "2026-10-11T10:00:00Z" },
};

const renderSetup = ({
  responses = {},
  strict = false,
  onConfirmed = vi.fn(),
}: {
  responses?: StubResponses;
  strict?: boolean;
  onConfirmed?: () => void;
} = {}) =>
  renderWithProviders(<TotpSetup onConfirmed={onConfirmed} />, {
    route: "/account/security",
    session: signedInPayload("mfa"),
    strict,
    responses: {
      "POST /api/me/totp": { status: 200, body: enrollment() },
      "POST /api/me/totp/confirm": { status: 200, body: confirmed },
      ...responses,
    },
  });

/** The cached mutations whose data holds the TOTP secret. */
const secretMutations = (queryClient: QueryClient) =>
  queryClient
    .getMutationCache()
    .getAll()
    .filter((mutation) =>
      JSON.stringify(mutation.state.data ?? null).includes("secret_base32"),
    );

/**
 * Replaces the clipboard stub of user-event, which `renderWithProviders`
 * attaches, so call it after the render.
 */
function mockClipboard() {
  const writeText = vi.fn(async (_text: string) => {});
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: { writeText },
  });
  return writeText;
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  takeReturnTo();
  Reflect.deleteProperty(navigator, "clipboard");
});

test("the QR code renders as an img with the data URL, and no svg enters the DOM", async () => {
  const { container } = renderSetup();

  const qr = await screen.findByRole("img", {
    name: "QR code for the authenticator app",
  });
  expect(qr.tagName).toBe("IMG");
  expect(qr).toHaveAttribute("src", QR);
  expect(qr).toHaveAttribute("alt", "QR code for the authenticator app");
  expect(qr).toHaveAttribute("width", "200");
  expect(qr).toHaveAttribute("height", "200");
  expect(container.querySelector("svg")).toBeNull();
  expect(document.querySelector("svg")).toBeNull();
});

test("a QR value that is no SVG data URL renders no img", async () => {
  renderSetup({
    responses: {
      "POST /api/me/totp": {
        status: 200,
        body: enrollment("data:text/html;base64,PHNjcmlwdD48L3NjcmlwdD4="),
      },
    },
  });

  expect(await screen.findByText(GROUPED)).toBeInTheDocument();
  expect(screen.queryByRole("img")).not.toBeInTheDocument();
  expect(document.querySelector("img, svg")).toBeNull();
});

test("the secret shows in groups of four", async () => {
  renderSetup();

  expect(await screen.findByText(GROUPED)).toBeInTheDocument();
  expect(screen.getByText("Key for entry by hand")).toBeInTheDocument();
});

test("the copy button writes the secret to the clipboard", async () => {
  const { user } = renderSetup();
  const writeText = mockClipboard();

  await user.click(await screen.findByRole("button", { name: "Copy the key" }));

  expect(writeText).toHaveBeenCalledWith(SECRET);
  await waitFor(() =>
    expect(screen.getByRole("status")).toHaveTextContent("The key was copied."),
  );
});

test("inside StrictMode exactly one setup request leaves", async () => {
  const { requests } = renderSetup({ strict: true });

  expect(await screen.findByText(GROUPED)).toBeInTheDocument();
  expect(requestsTo(requests, "POST", "/api/me/totp")).toHaveLength(1);
});

test("the first code goes to the confirm route as { code }", async () => {
  const onConfirmed = vi.fn();
  const { requests, user } = renderSetup({ onConfirmed });

  await user.type(
    await screen.findByLabelText("Six-digit code from the app"),
    "123456",
  );
  await user.click(screen.getByRole("button", { name: "Confirm the code" }));

  await waitFor(() => expect(onConfirmed).toHaveBeenCalledTimes(1));
  expect(onConfirmed).toHaveBeenCalledWith(confirmed);
  expect(
    requestsTo(requests, "POST", "/api/me/totp/confirm").map(
      (request) => request.body,
    ),
  ).toEqual([{ code: "123456" }]);
});

test("after the confirmation the secret leaves the DOM and the mutation cache", async () => {
  const onConfirmed = vi.fn();
  const { container, queryClient, user } = renderSetup({ onConfirmed });

  expect(await screen.findByText(GROUPED)).toBeInTheDocument();
  expect(secretMutations(queryClient)).toHaveLength(1);

  await user.type(
    screen.getByLabelText("Six-digit code from the app"),
    "123456",
  );
  await user.click(screen.getByRole("button", { name: "Confirm the code" }));

  await waitFor(() => expect(onConfirmed).toHaveBeenCalledTimes(1));
  await waitFor(() =>
    expect(screen.queryByText(GROUPED)).not.toBeInTheDocument(),
  );
  expect(container.innerHTML).not.toContain(SECRET);
  expect(container.innerHTML).not.toContain("JBSW Y3DP");
  expect(container.querySelector("img")).toBeNull();
  await waitFor(() => expect(secretMutations(queryClient)).toEqual([]));
});

test("a 422 invalid_code shows its message in the alert region", async () => {
  const onConfirmed = vi.fn();
  const { user } = renderSetup({
    onConfirmed,
    responses: {
      "POST /api/me/totp/confirm": {
        status: 422,
        body: { error: "invalid_code" },
      },
    },
  });

  await user.type(
    await screen.findByLabelText("Six-digit code from the app"),
    "000000",
  );
  await user.click(screen.getByRole("button", { name: "Confirm the code" }));

  await waitFor(() =>
    expect(screen.getByRole("alert")).toHaveTextContent(
      "The code is not correct. Check the time on your device and try again.",
    ),
  );
  expect(onConfirmed).not.toHaveBeenCalled();
  expect(screen.getByText(GROUPED)).toBeInTheDocument();
});

test("the setup has no axe violations in light, dark and German", async () => {
  const { container } = renderSetup();
  const qr = await screen.findByRole("img", {
    name: "QR code for the authenticator app",
  });
  expect(within(container).getByText(GROUPED)).toBeInTheDocument();
  expect(qr).toBeInTheDocument();

  await expectNoAxeViolations(container);
});

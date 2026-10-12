import { screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { AdminWebhook } from "../../api/admin/webhooks";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { WebhooksPage } from "./WebhooksPage";

/**
 * Task 0015 step 16: the webhooks page adds a receiver, lists the
 * receivers and deletes one. The form checks the URL scheme (`https`
 * outside a development build) and the prefix `WEBHOOK_SECRET_` before it
 * sends, and it shows `host_not_allowed` at the URL field and
 * `secret_env_unset` at the secret field.
 */
const uuid = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

const ROUTE = "/admin/webhooks";
const URL_FIELD = "Receiver URL";
const SECRET_FIELD = "Secret variable";
const URL_HINT =
  "An https address of a host that the operator admits in WEBHOOK_ALLOWED_HOSTS.";
const SECRET_HINT =
  "The name of the environment variable on the server that holds the signing secret, such as WEBHOOK_SECRET_RECEIVER.";

const receiver: AdminWebhook = {
  id: uuid(1),
  url: "https://hooks.example.org/credentials",
  events: ["credential.issued", "credential.revoked"],
  secret_env: "WEBHOOK_SECRET_RECEIVER",
  active: true,
};

function renderPage(responses: StubResponses = {}) {
  return renderWithProviders(<WebhooksPage />, {
    route: ROUTE,
    session: signedInPayload("mfa", { roles: ["learner", "admin"] }),
    responses: {
      "GET /api/admin/webhooks": { status: 200, body: { data: [receiver] } },
      ...responses,
    },
  });
}

const form = () => screen.findByRole("region", { name: "Add a webhook" });

/** Fills the form; the four events stay checked. */
async function fill(
  user: ReturnType<typeof renderPage>["user"],
  { url, secret }: { url: string; secret: string },
) {
  const section = await form();
  await user.type(within(section).getByLabelText(URL_FIELD), url);
  await user.type(within(section).getByLabelText(SECRET_FIELD), secret);
  await user.click(
    within(section).getByRole("button", { name: "Add webhook" }),
  );
  return section;
}

beforeEach(() => {
  // A production build admits https only.
  vi.stubEnv("DEV", false);
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("the webhook form", () => {
  test("sends a valid webhook in the nested body and confirms", async () => {
    const { user, requests } = renderPage({
      "POST /api/admin/webhooks": {
        status: 201,
        body: { data: { ...receiver, id: uuid(2) } },
      },
    });

    const section = await fill(user, {
      url: "https://hooks.example.org/new",
      secret: "WEBHOOK_SECRET_NEW",
    });

    expect(
      await within(section).findByText("The webhook is added."),
    ).toHaveAttribute("role", "status");
    expect(requestsTo(requests, "POST", "/api/admin/webhooks")[0].body).toEqual(
      {
        webhook: {
          url: "https://hooks.example.org/new",
          events: [
            "credential.issued",
            "credential.refresh_due",
            "credential.expired",
            "credential.revoked",
          ],
          secret_env: "WEBHOOK_SECRET_NEW",
          active: true,
        },
      },
    );
    expect(within(section).getByLabelText(URL_FIELD)).toHaveValue("");
    await waitFor(() =>
      expect(requestsTo(requests, "GET", "/api/admin/webhooks")).toHaveLength(
        2,
      ),
    );
  });

  test("refuses an http URL before sending", async () => {
    const { user, requests } = renderPage();

    const section = await fill(user, {
      url: "http://hooks.example.org/new",
      secret: "WEBHOOK_SECRET_NEW",
    });

    const field = within(section).getByLabelText(URL_FIELD);
    expect(field).toHaveAttribute("aria-invalid", "true");
    expect(field).toHaveAccessibleDescription(
      `${URL_HINT} The address must start with https://.`,
    );
    expect(requestsTo(requests, "POST", "/api/admin/webhooks")).toEqual([]);
  });

  test("admits an http URL in a development build", async () => {
    vi.stubEnv("DEV", true);
    const { user, requests } = renderPage({
      "POST /api/admin/webhooks": {
        status: 201,
        body: { data: { ...receiver, id: uuid(2) } },
      },
    });

    await fill(user, {
      url: "http://localhost:4100/hooks",
      secret: "WEBHOOK_SECRET_NEW",
    });

    await waitFor(() =>
      expect(requestsTo(requests, "POST", "/api/admin/webhooks")).toHaveLength(
        1,
      ),
    );
  });

  test.each([
    ["not a url", "Enter a complete address without user name or password"],
    [
      "https://user:secret@hooks.example.org/x",
      "Enter a complete address without user name or password",
    ],
    [
      `https://hooks.example.org/${"a".repeat(250)}`,
      "The address may have at most 255 characters.",
    ],
  ])("refuses the URL %s before sending", async (url, message) => {
    const { user, requests } = renderPage();

    const section = await fill(user, { url, secret: "WEBHOOK_SECRET_NEW" });

    expect(
      within(section).getByLabelText(URL_FIELD),
    ).toHaveAccessibleDescription(expect.stringContaining(message));
    expect(requestsTo(requests, "POST", "/api/admin/webhooks")).toEqual([]);
  });

  test("refuses a secret variable without the prefix WEBHOOK_SECRET_ before sending", async () => {
    const { user, requests } = renderPage();

    const section = await fill(user, {
      url: "https://hooks.example.org/new",
      secret: "CLOAK_KEY_V1",
    });

    const field = within(section).getByLabelText(SECRET_FIELD);
    expect(field).toHaveAttribute("aria-invalid", "true");
    expect(field).toHaveAccessibleDescription(
      `${SECRET_HINT} The name starts with WEBHOOK_SECRET_ and continues with capital letters, digits or underscores.`,
    );
    expect(within(section).getByLabelText(URL_FIELD)).not.toHaveAttribute(
      "aria-invalid",
    );
    expect(requestsTo(requests, "POST", "/api/admin/webhooks")).toEqual([]);
  });

  test("refuses a webhook without an event before sending", async () => {
    const { user, requests } = renderPage();
    const section = await form();

    for (const name of [
      "Credential issued",
      "Refresher due",
      "Credential expired",
      "Credential revoked",
    ])
      await user.click(within(section).getByRole("checkbox", { name }));
    await fill(user, {
      url: "https://hooks.example.org/new",
      secret: "WEBHOOK_SECRET_NEW",
    });

    expect(
      within(section).getByText("Choose at least one event."),
    ).toBeInTheDocument();
    expect(requestsTo(requests, "POST", "/api/admin/webhooks")).toEqual([]);
  });

  test("shows host_not_allowed at the URL field", async () => {
    const { user } = renderPage({
      "POST /api/admin/webhooks": {
        status: 422,
        body: {
          error: "validation_failed",
          fields: { url: ["host_not_allowed"] },
        },
      },
    });

    const section = await fill(user, {
      url: "https://elsewhere.example.net/hook",
      secret: "WEBHOOK_SECRET_NEW",
    });

    const field = within(section).getByLabelText(URL_FIELD);
    await waitFor(() => expect(field).toHaveAttribute("aria-invalid", "true"));
    expect(field).toHaveAccessibleDescription(
      `${URL_HINT} The server does not admit this host. The operator lists the admitted hosts in WEBHOOK_ALLOWED_HOSTS.`,
    );
    expect(field).toHaveValue("https://elsewhere.example.net/hook");
    expect(within(section).getByRole("alert")).toBeEmptyDOMElement();
  });

  test("shows secret_env_unset at the secret field", async () => {
    const { user } = renderPage({
      "POST /api/admin/webhooks": {
        status: 422,
        body: { error: "secret_env_unset" },
      },
    });

    const section = await fill(user, {
      url: "https://hooks.example.org/new",
      secret: "WEBHOOK_SECRET_MISSING",
    });

    const field = within(section).getByLabelText(SECRET_FIELD);
    await waitFor(() => expect(field).toHaveAttribute("aria-invalid", "true"));
    expect(field).toHaveAccessibleDescription(
      `${SECRET_HINT} The server has no value for this variable. Set it in the environment of the server first.`,
    );
  });
});

describe("the webhook list", () => {
  test("lists URL, events, secret variable and status", async () => {
    renderPage();

    const table = await screen.findByRole("table", { name: "Receivers" });
    expect(
      within(table)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual(["URL", "Events", "Secret variable", "Status", "Actions"]);
    const row = within(table)
      .getByRole("rowheader", { name: receiver.url })
      .closest("tr");
    if (row === null) throw new Error("no row");
    expect(
      within(row)
        .getAllByRole("listitem")
        .map((item) => item.textContent),
    ).toEqual(["Credential issued", "Credential revoked"]);
    expect(within(row).getAllByRole("cell")[1]).toHaveTextContent(
      "WEBHOOK_SECRET_RECEIVER",
    );
    expect(within(row).getAllByRole("cell")[2]).toHaveTextContent("Active");
  });

  test("deletes a webhook after a confirmation", async () => {
    const { user, requests } = renderPage({
      [`DELETE /api/admin/webhooks/${receiver.id}`]: { status: 204 },
    });

    await user.click(
      await screen.findByRole("button", { name: `Delete ${receiver.url}` }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Delete this webhook?",
    });
    expect(dialog).toHaveTextContent(
      `${receiver.url} receives no more events.`,
    );
    await user.click(within(dialog).getByRole("button", { name: "Delete" }));

    expect(await screen.findByText("The webhook is deleted.")).toHaveAttribute(
      "role",
      "status",
    );
    expect(
      requestsTo(requests, "DELETE", `/api/admin/webhooks/${receiver.id}`),
    ).toHaveLength(1);
  });

  test("axe reports no violation, also with field errors", async () => {
    const { container, user } = renderPage();
    await screen.findByRole("table", { name: "Receivers" });
    await expectNoAxeViolations(container);

    await fill(user, { url: "http://x", secret: "WRONG" });
    await expectNoAxeViolations(container);
  });
});

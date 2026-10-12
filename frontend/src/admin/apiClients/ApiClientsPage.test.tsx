import { screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import type {
  AdminApiClient,
  AdminApiClientCreated,
} from "../../api/admin/apiClients";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { ApiClientsPage } from "./ApiClientsPage";

/**
 * Task 0015 step 16: the API clients page creates a machine client, shows
 * its token once with a copy button, lists the clients and deletes one
 * after a confirmation.
 */
const uuid = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

const ROUTE = "/admin/api-clients";
const TOKEN = "q3Jk2m9Vx1-token-shown-once_Zp7";

const reporting: AdminApiClient = {
  id: uuid(1),
  name: "Reporting",
  scopes: ["credentials:read"],
  inserted_at: "2026-09-01T08:00:00Z",
  last_used_at: null,
};
const archive: AdminApiClient = {
  id: uuid(2),
  name: "Archive",
  scopes: ["credentials:read"],
  inserted_at: "2026-09-02T08:00:00Z",
  last_used_at: "2026-10-10T09:30:00Z",
};
const created: AdminApiClientCreated = {
  client: {
    id: uuid(3),
    name: "Registry sync",
    scopes: ["credentials:read"],
    inserted_at: "2026-10-12T08:00:00Z",
    last_used_at: null,
  },
  token: TOKEN,
};

function renderPage(responses: StubResponses = {}) {
  return renderWithProviders(<ApiClientsPage />, {
    route: ROUTE,
    session: signedInPayload("mfa", { roles: ["learner", "admin"] }),
    responses: {
      "GET /api/admin/api-clients": [
        { status: 200, body: { clients: [reporting, archive] } },
        {
          status: 200,
          body: { clients: [reporting, archive, created.client] },
        },
      ],
      ...responses,
    },
  });
}

/** Replaces the clipboard stub of user-event; call it after the render. */
function mockClipboard() {
  const writeText = vi.fn(async (_text: string) => {});
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: { writeText },
  });
  return writeText;
}

afterEach(() => {
  Reflect.deleteProperty(navigator, "clipboard");
});

const createForm = () =>
  screen.findByRole("region", { name: "Create an API client" });

describe("the API clients page", () => {
  test("lists the clients with scopes, creation and last use", async () => {
    renderPage();

    const table = await screen.findByRole("table", { name: "Clients" });
    expect(
      within(table)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual(["Name", "Scopes", "Created", "Last used", "Actions"]);
    const row = within(table)
      .getByRole("rowheader", { name: "Reporting" })
      .closest("tr");
    if (row === null) throw new Error("no row");
    const cells = within(row).getAllByRole("cell");
    expect(cells[0]).toHaveTextContent("credentials:read");
    expect(cells[2]).toHaveTextContent("Never");
    expect(
      within(row).getByRole("button", { name: "Delete Reporting" }),
    ).toBeInTheDocument();
  });

  test("shows the token once after the create, with a copy button", async () => {
    const { user, requests } = renderPage({
      "POST /api/admin/api-clients": { status: 201, body: created },
    });
    const writeText = mockClipboard();
    const form = await createForm();

    expect(
      within(form).getByRole("checkbox", {
        name: "credentials:read, read credentials",
      }),
    ).toBeChecked();
    await user.type(within(form).getByLabelText("Name"), "Registry sync");
    await user.click(
      within(form).getByRole("button", { name: "Create client" }),
    );

    const heading = await screen.findByRole("heading", {
      name: "The token of Registry sync",
    });
    expect(heading).toHaveFocus();
    expect(screen.getByLabelText("Token")).toHaveValue(TOKEN);
    expect(
      requestsTo(requests, "POST", "/api/admin/api-clients")[0].body,
    ).toEqual({ name: "Registry sync", scopes: ["credentials:read"] });
    // While the token is shown, the panel takes the place of the form.
    expect(
      screen.queryByRole("region", { name: "Create an API client" }),
    ).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Copy token" }));
    expect(writeText).toHaveBeenCalledWith(TOKEN);
    expect(await screen.findByText("Copied to the clipboard.")).toHaveAttribute(
      "role",
      "status",
    );

    // The list loads again and names the new client, without its token.
    const table = await screen.findByRole("table", { name: "Clients" });
    await within(table).findByRole("rowheader", { name: "Registry sync" });
    expect(table).not.toHaveTextContent(TOKEN);

    await user.click(screen.getByRole("button", { name: "Done" }));
    expect(await createForm()).toBeInTheDocument();
    expect(screen.queryByDisplayValue(TOKEN)).not.toBeInTheDocument();
    expect(document.body).not.toHaveTextContent(TOKEN);
    expect(requestsTo(requests, "POST", "/api/admin/api-clients")).toHaveLength(
      1,
    );
  });

  test("a failed copy says so", async () => {
    const { user } = renderPage({
      "POST /api/admin/api-clients": { status: 201, body: created },
    });
    const writeText = mockClipboard();
    writeText.mockRejectedValueOnce(new Error("denied"));
    const form = await createForm();

    await user.type(within(form).getByLabelText("Name"), "Registry sync");
    await user.click(
      within(form).getByRole("button", { name: "Create client" }),
    );
    await user.click(await screen.findByRole("button", { name: "Copy token" }));

    expect(
      await screen.findByText(
        "Copying failed. Select the text and copy it by hand.",
      ),
    ).toBeInTheDocument();
  });

  test("checks the name and the scopes before it sends", async () => {
    const { user, requests } = renderPage();
    const form = await createForm();
    const name = within(form).getByLabelText("Name");

    await user.click(
      within(form).getByRole("button", { name: "Create client" }),
    );
    expect(name).toHaveAccessibleDescription(
      "For example the name of the system that reads the credentials. Enter a name of 1 to 100 characters.",
    );

    await user.type(name, "Registry sync");
    await user.click(within(form).getByRole("checkbox"));
    await user.click(
      within(form).getByRole("button", { name: "Create client" }),
    );
    expect(
      within(form).getByText("Choose at least one scope."),
    ).toBeInTheDocument();
    expect(requestsTo(requests, "POST", "/api/admin/api-clients")).toEqual([]);
  });

  test("deletes a client after a confirmation", async () => {
    const { user, requests } = renderPage({
      [`DELETE /api/admin/api-clients/${reporting.id}`]: { status: 204 },
    });

    await user.click(
      await screen.findByRole("button", { name: "Delete Reporting" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Delete this API client?",
    });
    expect(dialog).toHaveTextContent(
      "The token of Reporting stops working at once.",
    );
    await user.click(within(dialog).getByRole("button", { name: "Delete" }));

    expect(
      await screen.findByText("The API client Reporting is deleted."),
    ).toHaveAttribute("role", "status");
    expect(
      requestsTo(requests, "DELETE", `/api/admin/api-clients/${reporting.id}`),
    ).toHaveLength(1);
    await waitFor(() =>
      expect(
        requestsTo(requests, "GET", "/api/admin/api-clients"),
      ).toHaveLength(2),
    );
  });

  test("states an empty list", async () => {
    renderPage({
      "GET /api/admin/api-clients": { status: 200, body: { clients: [] } },
    });

    expect(
      await screen.findByText("There are no API clients yet."),
    ).toBeInTheDocument();
  });

  test("axe reports no violation on the page and on the token panel", async () => {
    const { container, user } = renderPage({
      "POST /api/admin/api-clients": { status: 201, body: created },
    });
    await screen.findByRole("table", { name: "Clients" });
    await expectNoAxeViolations(container);

    const form = await createForm();
    await user.type(within(form).getByLabelText("Name"), "Registry sync");
    await user.click(
      within(form).getByRole("button", { name: "Create client" }),
    );
    await screen.findByRole("heading", { name: "The token of Registry sync" });
    await expectNoAxeViolations(container);
  });
});

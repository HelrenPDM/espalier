import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type { AdminUser } from "../../api/admin/users";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload, TEST_USER } from "../../test/session";
import { RolesPage } from "./RolesPage";

/**
 * Task 0015 step 15: the roles page lists the users with grants, finds one
 * user by the exact address, shows the grants per user with their source,
 * adds and removes `manual` grants, and states in the confirmation that
 * the change ends the person's sessions.
 */
const uuid = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

const ROUTE = "/admin/roles";
const CLEO = uuid(2);
const AUTHOR_GRANT = uuid(61);
const CLAIM_GRANT = uuid(62);

const ada: AdminUser = {
  id: TEST_USER.id,
  display_name: "Ada Example",
  status: "active",
  enrolled: true,
  roles: ["learner", "admin"],
  provider_keys: [],
  last_login_at: "2026-10-01T08:00:00Z",
  grants: [
    {
      id: uuid(60),
      user_id: TEST_USER.id,
      role: "admin",
      source: "manual",
      provider_key: null,
    },
  ],
};
const cleo: AdminUser = {
  id: CLEO,
  display_name: "Cleo Example",
  status: "active",
  enrolled: true,
  roles: ["learner", "author", "analyst"],
  provider_keys: ["oidc-main"],
  last_login_at: "2026-10-02T09:00:00Z",
  grants: [
    {
      id: AUTHOR_GRANT,
      user_id: CLEO,
      role: "author",
      source: "manual",
      provider_key: null,
    },
    {
      id: CLAIM_GRANT,
      user_id: CLEO,
      role: "analyst",
      source: "idp_claim",
      provider_key: "oidc-main",
    },
  ],
};
const ben: AdminUser = {
  id: uuid(1),
  display_name: "Ben Learner",
  status: "active",
  enrolled: true,
  roles: ["learner"],
  provider_keys: [],
  last_login_at: null,
  grants: [],
};

const admin = signedInPayload("mfa", { roles: ["learner", "admin"] });

function renderPage(responses: StubResponses = {}) {
  return renderWithProviders(<RolesPage />, {
    route: ROUTE,
    session: admin,
    responses: {
      "GET /api/admin/role-grants": {
        status: 200,
        body: { users: [ada, cleo] },
      },
      ...responses,
    },
  });
}

async function rowOf(tableName: string, name: string) {
  const table = await screen.findByRole("table", { name: tableName });
  const row = within(table).getByRole("rowheader", { name }).closest("tr");
  if (row === null) throw new Error(`no row for ${name}`);
  return row;
}

const holderRow = (name: string) => rowOf("People with roles", name);

describe("the roles page", () => {
  test("lists the people with grants, the source of each grant and 'Remove' for manual grants only", async () => {
    renderPage();

    const table = await screen.findByRole("table", {
      name: "People with roles",
    });
    expect(
      within(table)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual(["Person", "Roles", "Add a role"]);
    const row = await holderRow("Cleo Example");
    const items = within(row)
      .getAllByRole("listitem")
      .map((item) => item.textContent);
    expect(items).toEqual([
      "Author (granted here)Remove",
      "Analyst (from oidc-main)",
    ]);
    expect(
      within(row).getByRole("button", {
        name: "Remove the role Author of Cleo Example",
      }),
    ).toBeInTheDocument();
    expect(
      within(row).queryByRole("button", { name: /Analyst/ }),
    ).not.toBeInTheDocument();
    // The select offers the roles that the person does not hold manually.
    expect(
      within(within(row).getByLabelText("Role for Cleo Example"))
        .getAllByRole("option")
        .map((option) => option.textContent),
    ).toEqual(["Facilitator", "Registrar", "Analyst", "Administrator"]);
  });

  test("grants a role after a confirmation that names the ended sessions", async () => {
    const { user, requests } = renderPage({
      "POST /api/admin/role-grants": {
        status: 201,
        body: {
          id: uuid(70),
          user_id: CLEO,
          role: "registrar",
          source: "manual",
          provider_key: null,
        },
      },
    });

    const row = await holderRow("Cleo Example");
    await user.selectOptions(
      within(row).getByLabelText("Role for Cleo Example"),
      "registrar",
    );
    await user.click(
      within(row).getByRole("button", {
        name: "Grant the chosen role to Cleo Example",
      }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Grant this role?",
    });
    expect(dialog).toHaveTextContent(
      "Cleo Example receives the role Registrar.",
    );
    expect(dialog).toHaveTextContent(
      "The change ends every session of the person, so that the roles apply from the next sign-in.",
    );
    expect(dialog).not.toHaveTextContent("This is your own account");
    await user.click(within(dialog).getByRole("button", { name: "Grant" }));

    expect(
      await screen.findByText("Cleo Example holds the role Registrar."),
    ).toHaveAttribute("role", "status");
    expect(
      requestsTo(requests, "POST", "/api/admin/role-grants")[0].body,
    ).toEqual({ user_id: CLEO, role: "registrar" });
    await waitFor(() =>
      expect(
        requestsTo(requests, "GET", "/api/admin/role-grants"),
      ).toHaveLength(2),
    );
    expect(requestsTo(requests, "GET", "/api/session")).toHaveLength(0);
  });

  test("removes a manual grant after a confirmation", async () => {
    const { user, requests } = renderPage({
      [`DELETE /api/admin/role-grants/${AUTHOR_GRANT}`]: { status: 204 },
    });

    await user.click(
      within(await holderRow("Cleo Example")).getByRole("button", {
        name: "Remove the role Author of Cleo Example",
      }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Remove this role?",
    });
    expect(dialog).toHaveTextContent("Cleo Example loses the role Author.");
    expect(dialog).toHaveTextContent(
      "The change ends every session of the person",
    );
    await user.click(within(dialog).getByRole("button", { name: "Remove" }));

    expect(
      await screen.findByText("Cleo Example no longer holds the role Author."),
    ).toBeInTheDocument();
    expect(
      requestsTo(requests, "DELETE", `/api/admin/role-grants/${AUTHOR_GRANT}`),
    ).toHaveLength(1);
  });

  test("a change of the own grants says so and refetches the session", async () => {
    const { user, requests } = renderPage({
      "POST /api/admin/role-grants": {
        status: 201,
        body: {
          id: uuid(71),
          user_id: TEST_USER.id,
          role: "facilitator",
          source: "manual",
          provider_key: null,
        },
      },
    });

    await user.click(
      within(await holderRow("Ada Example")).getByRole("button", {
        name: "Grant the chosen role to Ada Example",
      }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Grant this role?",
    });
    expect(dialog).toHaveTextContent(
      "This is your own account: you sign in again afterwards.",
    );
    await user.click(within(dialog).getByRole("button", { name: "Grant" }));

    await waitFor(() =>
      expect(requestsTo(requests, "GET", "/api/session")).toHaveLength(1),
    );
  });

  test.each([
    ["demo_user", "Demo accounts receive no roles."],
    [
      "idp_claim",
      "This role comes from the identity provider and changes only there.",
    ],
  ])("409 %s reads as its own message", async (code, message) => {
    const { user } = renderPage({
      [`DELETE /api/admin/role-grants/${AUTHOR_GRANT}`]: {
        status: 409,
        body: { error: code },
      },
    });

    await user.click(
      within(await holderRow("Cleo Example")).getByRole("button", {
        name: "Remove the role Author of Cleo Example",
      }),
    );
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", {
        name: "Remove",
      }),
    );

    expect(await screen.findByText(message)).toHaveAttribute("role", "alert");
  });

  test("finds a person by address and grants a role to them", async () => {
    const { user, requests } = renderPage({
      "POST /api/admin/user-lookups": { status: 200, body: ben },
      "POST /api/admin/role-grants": {
        status: 201,
        body: {
          id: uuid(72),
          user_id: ben.id,
          role: "facilitator",
          source: "manual",
          provider_key: null,
        },
      },
    });
    const section = await screen.findByRole("region", {
      name: "Find a person",
    });

    await user.type(
      within(section).getByLabelText("E-mail address"),
      "ben@example.test",
    );
    await user.click(within(section).getByRole("button", { name: "Find" }));
    const row = await rowOf("Search result", "Ben Learner");
    expect(within(row).getAllByRole("cell")[0]).toHaveTextContent("None");
    await user.click(
      within(row).getByRole("button", {
        name: "Grant the chosen role to Ben Learner",
      }),
    );
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", {
        name: "Grant",
      }),
    );

    await waitFor(() =>
      expect(
        requestsTo(requests, "POST", "/api/admin/role-grants")[0]?.body,
      ).toEqual({ user_id: ben.id, role: "facilitator" }),
    );
    expect(
      requestsTo(requests, "POST", "/api/admin/user-lookups")[0].body,
    ).toEqual({ email: "ben@example.test" });
    // The change refreshes the lookup.
    await waitFor(() =>
      expect(
        requestsTo(requests, "POST", "/api/admin/user-lookups"),
      ).toHaveLength(2),
    );
  });

  test("states an empty list", async () => {
    renderPage({
      "GET /api/admin/role-grants": { status: 200, body: { users: [] } },
    });

    expect(
      await screen.findByText("Nobody holds a role beyond learner yet."),
    ).toBeInTheDocument();
  });

  test("axe reports no violation on the page and in the dialog", async () => {
    const { container, user } = renderPage();
    await screen.findByRole("table", { name: "People with roles" });
    await expectNoAxeViolations(container);

    await user.click(
      within(await holderRow("Cleo Example")).getByRole("button", {
        name: "Remove the role Author of Cleo Example",
      }),
    );
    await screen.findByRole("dialog", { name: "Remove this role?" });
    await expectNoAxeViolations(document.body);
  });
});

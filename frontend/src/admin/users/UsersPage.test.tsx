import { screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { AdminUser, AdminUserList } from "../../api/admin/users";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type RecordedRequest,
  type StubResponses,
} from "../../test/render";
import {
  signedInPayload,
  TEST_USER,
  type PayloadOverrides,
} from "../../test/session";
import { UsersPage } from "./UsersPage";

/**
 * Task 0015 step 12: the users page. It invites a local user, finds one by
 * the exact address in the body of `POST /api/admin/user-lookups`, lists
 * the users 50 per page with status, roles, linked providers and last
 * sign-in, and offers per user "Resend invitation" (only for a local user
 * without a second factor), "Disable" and "End sessions" with a
 * confirmation, "Reset second factors" behind the identity check of
 * decision D11, and "Reset failure counters". "End all sessions" states
 * that the admin's own session ends as well, and "Revoke credential" takes
 * an id and asks for a confirmation.
 */
const uuid = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

const ROUTE = "/admin/users";
const BEN = uuid(1);
const CREDENTIAL = uuid(90);

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
      id: uuid(51),
      user_id: TEST_USER.id,
      role: "admin",
      source: "manual",
      provider_key: null,
    },
  ],
};
const ben: AdminUser = {
  id: BEN,
  display_name: "Ben Invited",
  status: "active",
  enrolled: false,
  roles: ["learner"],
  provider_keys: [],
  last_login_at: null,
  grants: [],
};
const cleo: AdminUser = {
  id: uuid(2),
  display_name: "Cleo Federated",
  status: "active",
  enrolled: false,
  roles: ["learner", "author"],
  provider_keys: ["oidc-main"],
  last_login_at: "2026-10-02T09:00:00Z",
  grants: [
    {
      id: uuid(52),
      user_id: uuid(2),
      role: "author",
      source: "idp_claim",
      provider_key: "oidc-main",
    },
  ],
};
const dora: AdminUser = {
  id: uuid(3),
  display_name: null,
  status: "disabled",
  enrolled: true,
  roles: ["learner"],
  provider_keys: [],
  last_login_at: "2026-09-20T10:00:00Z",
  grants: [],
};

const list = (overrides: Partial<AdminUserList> = {}): AdminUserList => ({
  users: [ada, ben, cleo, dora],
  page: 1,
  per_page: 50,
  total: 4,
  ...overrides,
});

const admin = (overrides: PayloadOverrides = {}) =>
  signedInPayload("mfa", { roles: ["learner", "admin"], ...overrides });

function renderPage(
  responses: StubResponses = {},
  { route = ROUTE, session = admin() } = {},
) {
  return renderWithProviders(<UsersPage />, {
    route,
    path: ROUTE,
    session,
    responses: {
      "GET /api/admin/users": { status: 200, body: list() },
      ...responses,
    },
  });
}

/** The row of the table `tableName` whose row header starts with `name`. */
async function rowOf(tableName: string, name: string) {
  const table = await screen.findByRole("table", { name: tableName });
  const header = within(table).getByRole("rowheader", {
    name: new RegExp(`^${name}`),
  });
  const row = header.closest("tr");
  if (row === null) throw new Error(`no row for ${name}`);
  return row;
}

const listRow = (name: string) => rowOf("All users", name);

/** The texts of the data cells of `row`. */
const cellTexts = (row: HTMLElement) =>
  within(row)
    .getAllByRole("cell")
    .map((cell) => cell.textContent);

/** The requests after the page load, without the GETs of the page. */
const changes = (requests: RecordedRequest[]) =>
  requests.filter((request) => request.method !== "GET");

/**
 * Records the URL of every request that the API client builds; the stub
 * fetch records the path only, and the list names its page in the query.
 */
function recordRequestUrls(): string[] {
  const urls: string[] = [];
  const Base = globalThis.Request;
  vi.stubGlobal(
    "Request",
    class extends Base {
      constructor(input: RequestInfo | URL, init?: RequestInit) {
        super(input, init);
        urls.push(this.url);
      }
    },
  );
  return urls;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("the user list", () => {
  test("shows status, roles, linked providers and last sign-in per user", async () => {
    renderPage();

    const table = await screen.findByRole("table", { name: "All users" });
    expect(table).toHaveAccessibleDescription(
      "50 people per page, in the order in which their accounts were created.",
    );
    expect(
      within(table)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual([
      "Name",
      "Status",
      "Roles",
      "Linked providers",
      "Last sign-in",
      "Actions",
    ]);
    expect(cellTexts(await listRow("Ben Invited")).slice(0, 4)).toEqual([
      "ActiveNo second factor yet",
      "Learner",
      "None",
      "Never",
    ]);
    expect(cellTexts(await listRow("Cleo Federated")).slice(0, 3)).toEqual([
      "ActiveNo second factor yet",
      "Learner, Author",
      "oidc-main",
    ]);
    expect(cellTexts(await listRow("No name")).slice(0, 1)).toEqual([
      "Disabled",
    ]);
    expect(
      within(await listRow("Ada Example")).getByText("You"),
    ).toBeInTheDocument();
    // No pager for a single page.
    expect(
      screen.queryByRole("navigation", { name: "Pages of the user list" }),
    ).not.toBeInTheDocument();
  });

  test("offers 'Resend invitation' only to a local user without a second factor", async () => {
    renderPage();

    const action = (row: HTMLElement) =>
      within(row).queryByRole("button", { name: /^Resend invitation/ });
    expect(action(await listRow("Ben Invited"))).toHaveAccessibleName(
      "Resend invitation Ben Invited",
    );
    expect(action(await listRow("Ada Example"))).toBeNull();
    expect(action(await listRow("Cleo Federated"))).toBeNull();
    expect(action(await listRow("No name"))).toBeNull();
  });

  test("leaves 'Disable' and 'Reset second factors' off the admin's own row and 'Disable' off a disabled user", async () => {
    renderPage();

    const own = await listRow("Ada Example");
    expect(
      within(own).queryByRole("button", { name: /^Disable/ }),
    ).not.toBeInTheDocument();
    expect(
      within(own).queryByRole("button", { name: /^Reset second factors/ }),
    ).not.toBeInTheDocument();
    expect(
      within(own).getByRole("button", { name: /^End sessions/ }),
    ).toBeInTheDocument();
    expect(
      within(await listRow("No name")).queryByRole("button", {
        name: /^Disable/,
      }),
    ).not.toBeInTheDocument();
  });

  test("pages through the list with ?page= and the total of the answer", async () => {
    const urls = recordRequestUrls();
    const { user, location } = renderPage({
      "GET /api/admin/users": { status: 200, body: list({ total: 120 }) },
    });

    const pager = await screen.findByRole("navigation", {
      name: "Pages of the user list",
    });
    expect(within(pager).getByText("Page 1 of 3")).toBeInTheDocument();
    expect(
      within(pager).getByRole("button", { name: "Previous page" }),
    ).toBeDisabled();
    await user.click(within(pager).getByRole("button", { name: "Next page" }));

    await waitFor(() => expect(location()).toBe("/admin/users?page=2"));
    await waitFor(() =>
      expect(
        urls
          .map((url) => new URL(url))
          .filter((url) => url.pathname === "/api/admin/users")
          .map((url) => url.searchParams.get("page")),
      ).toEqual(["1", "2"]),
    );
  });

  test("states a failed load", async () => {
    renderPage({
      "GET /api/admin/users": { status: 500, body: { error: "internal" } },
    });

    expect(
      await screen.findByText(
        "The data could not be loaded. Please try again later.",
      ),
    ).toHaveAttribute("role", "alert");
  });
});

describe("the actions per user", () => {
  test("'Reset second factors' cannot confirm without the identity check and then sends identity_verified: true", async () => {
    const { user, requests } = renderPage({
      [`POST /api/admin/users/${BEN}/reset-factors`]: {
        status: 200,
        body: { invitation_sent: true },
      },
    });

    await user.click(
      within(await listRow("Ben Invited")).getByRole("button", {
        name: "Reset second factors Ben Invited",
      }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Reset the second factors?",
    });
    expect(dialog).toHaveTextContent(
      "Every passkey, authenticator app and recovery code of Ben Invited is removed, and every session of the person ends.",
    );
    expect(dialog).toHaveTextContent(
      "A local account receives a new invitation",
    );
    const confirm = within(dialog).getByRole("button", {
      name: "Reset second factors",
    });
    const checkbox = within(dialog).getByRole("checkbox", {
      name: "The organization has verified this person's identity",
    });
    expect(checkbox).not.toBeChecked();
    expect(confirm).toBeDisabled();
    await user.click(confirm);
    expect(changes(requests)).toEqual([]);

    await user.click(checkbox);
    expect(confirm).toBeEnabled();
    await user.click(confirm);

    await waitFor(() =>
      expect(
        requestsTo(requests, "POST", `/api/admin/users/${BEN}/reset-factors`),
      ).toHaveLength(1),
    );
    expect(
      requestsTo(requests, "POST", `/api/admin/users/${BEN}/reset-factors`)[0]
        .body,
    ).toEqual({ identity_verified: true });
    expect(
      await screen.findByText(
        "The second factors of Ben Invited are reset. A new invitation is on its way.",
      ),
    ).toHaveAttribute("role", "status");
    expect(
      screen.queryByRole("dialog", { name: "Reset the second factors?" }),
    ).not.toBeInTheDocument();
  });

  test("the reset dialog starts unchecked each time and Cancel sends nothing", async () => {
    const { user, requests } = renderPage();
    const open = async () => {
      await user.click(
        within(await listRow("Cleo Federated")).getByRole("button", {
          name: "Reset second factors Cleo Federated",
        }),
      );
      return screen.findByRole("dialog", { name: "Reset the second factors?" });
    };

    let dialog = await open();
    await user.click(within(dialog).getByRole("checkbox"));
    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));
    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );

    dialog = await open();
    expect(within(dialog).getByRole("checkbox")).not.toBeChecked();
    expect(changes(requests)).toEqual([]);
  });

  test("a reset without an invitation says that the person enrolls at the next sign-in", async () => {
    const { user } = renderPage({
      [`POST /api/admin/users/${uuid(2)}/reset-factors`]: {
        status: 200,
        body: { invitation_sent: false },
      },
    });

    await user.click(
      within(await listRow("Cleo Federated")).getByRole("button", {
        name: "Reset second factors Cleo Federated",
      }),
    );
    const dialog = await screen.findByRole("dialog");
    await user.click(within(dialog).getByRole("checkbox"));
    await user.click(
      within(dialog).getByRole("button", { name: "Reset second factors" }),
    );

    expect(
      await screen.findByText(
        "The second factors of Cleo Federated are reset. The person sets up a new second factor at the next sign-in through the identity provider.",
      ),
    ).toBeInTheDocument();
  });

  test("'Disable' asks first, sends after the confirmation and refreshes the list", async () => {
    const { user, requests } = renderPage({
      [`POST /api/admin/users/${BEN}/disable`]: {
        status: 200,
        body: { ...ben, status: "disabled" },
      },
    });

    await user.click(
      within(await listRow("Ben Invited")).getByRole("button", {
        name: "Disable Ben Invited",
      }),
    );
    let dialog = await screen.findByRole("dialog", {
      name: "Disable this account?",
    });
    expect(dialog).toHaveTextContent(
      "Ben Invited can no longer sign in, and every session of the person ends at once.",
    );
    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));
    expect(changes(requests)).toEqual([]);

    await user.click(
      within(await listRow("Ben Invited")).getByRole("button", {
        name: "Disable Ben Invited",
      }),
    );
    dialog = await screen.findByRole("dialog", {
      name: "Disable this account?",
    });
    await user.click(within(dialog).getByRole("button", { name: "Disable" }));

    expect(
      await screen.findByText(
        "Ben Invited is disabled, and every session of the person has ended.",
      ),
    ).toHaveAttribute("role", "status");
    expect(changes(requests).map((request) => request.path)).toEqual([
      `/api/admin/users/${BEN}/disable`,
    ]);
    await waitFor(() =>
      expect(requestsTo(requests, "GET", "/api/admin/users")).toHaveLength(2),
    );
  });

  test("'End sessions' asks first and sends DELETE", async () => {
    const { user, requests } = renderPage({
      [`DELETE /api/admin/users/${BEN}/sessions`]: { status: 204 },
    });

    await user.click(
      within(await listRow("Ben Invited")).getByRole("button", {
        name: "End sessions Ben Invited",
      }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "End the sessions?",
    });
    expect(dialog).not.toHaveTextContent("This is your own account");
    await user.click(
      within(dialog).getByRole("button", { name: "End sessions" }),
    );

    expect(
      await screen.findByText("Every session of Ben Invited has ended."),
    ).toBeInTheDocument();
    expect(
      requestsTo(requests, "DELETE", `/api/admin/users/${BEN}/sessions`),
    ).toHaveLength(1);
  });

  test("ending the own sessions says so in the dialog and refetches the session", async () => {
    const { user, requests } = renderPage({
      [`DELETE /api/admin/users/${TEST_USER.id}/sessions`]: { status: 204 },
    });

    await user.click(
      within(await listRow("Ada Example")).getByRole("button", {
        name: "End sessions Ada Example",
      }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "End the sessions?",
    });
    expect(dialog).toHaveTextContent(
      "This is your own account: your current session ends as well, and you sign in again.",
    );
    await user.click(
      within(dialog).getByRole("button", { name: "End sessions" }),
    );

    await waitFor(() =>
      expect(requestsTo(requests, "GET", "/api/session")).toHaveLength(1),
    );
  });

  test("'Reset failure counters' and 'Resend invitation' send at once and report the result", async () => {
    const { user, requests } = renderPage({
      [`POST /api/admin/users/${BEN}/reset-failure-counters`]: { status: 204 },
      [`POST /api/admin/users/${BEN}/invitation`]: [
        { status: 202, body: { status: "accepted" } },
        { status: 409, body: { error: "not_invitable" } },
      ],
    });
    const row = await listRow("Ben Invited");

    await user.click(
      within(row).getByRole("button", {
        name: "Reset failure counters Ben Invited",
      }),
    );
    expect(
      await screen.findByText("The failure counters of Ben Invited are reset."),
    ).toBeInTheDocument();

    await user.click(
      within(await listRow("Ben Invited")).getByRole("button", {
        name: "Resend invitation Ben Invited",
      }),
    );
    expect(
      await screen.findByText("A new invitation to Ben Invited is on its way."),
    ).toBeInTheDocument();

    await user.click(
      within(await listRow("Ben Invited")).getByRole("button", {
        name: "Resend invitation Ben Invited",
      }),
    );
    expect(
      await screen.findByText(
        "This person cannot receive an invitation: the account is set up, disabled or signs in through a provider.",
      ),
    ).toHaveAttribute("role", "alert");
    expect(changes(requests).map((request) => request.path)).toEqual([
      `/api/admin/users/${BEN}/reset-failure-counters`,
      `/api/admin/users/${BEN}/invitation`,
      `/api/admin/users/${BEN}/invitation`,
    ]);
  });

  test("409 own_account reads as a message of its own", async () => {
    const { user } = renderPage({
      [`POST /api/admin/users/${BEN}/disable`]: {
        status: 409,
        body: { error: "own_account" },
      },
    });

    await user.click(
      within(await listRow("Ben Invited")).getByRole("button", {
        name: "Disable Ben Invited",
      }),
    );
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", {
        name: "Disable",
      }),
    );

    expect(
      await screen.findByText(
        "This action is not available for your own account.",
      ),
    ).toHaveAttribute("role", "alert");
  });

  test("a closed step-up dialog leaves the user unchanged and says why", async () => {
    const { user, requests } = renderPage({
      [`POST /api/admin/users/${BEN}/disable`]: {
        status: 403,
        body: { error: "reauth_required" },
      },
    });

    await user.click(
      within(await listRow("Ben Invited")).getByRole("button", {
        name: "Disable Ben Invited",
      }),
    );
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", {
        name: "Disable",
      }),
    );
    const stepUp = await screen.findByRole("dialog", {
      name: "Confirm it is you",
    });
    await user.click(within(stepUp).getByRole("button", { name: "Cancel" }));

    expect(
      await screen.findByText(
        "The change was not made, because the confirmation with a second factor was cancelled.",
      ),
    ).toHaveAttribute("role", "alert");
    expect(
      requestsTo(requests, "POST", `/api/admin/users/${BEN}/disable`),
    ).toHaveLength(1);
  });
});

describe("the invitation", () => {
  test("sends the address and the display name and confirms", async () => {
    const { user, requests } = renderPage({
      "POST /api/admin/users": { status: 202, body: { status: "accepted" } },
    });
    const form = await screen.findByRole("region", {
      name: "Invite a person",
    });

    await user.type(
      within(form).getByLabelText("E-mail address"),
      "new.person@example.test",
    );
    await user.type(within(form).getByLabelText("Display name"), "New Person");
    await user.click(
      within(form).getByRole("button", { name: "Send invitation" }),
    );

    expect(
      await within(form).findByText(
        "The invitation is on its way. Its link is valid for 10 minutes.",
      ),
    ).toHaveAttribute("role", "status");
    expect(requestsTo(requests, "POST", "/api/admin/users")[0].body).toEqual({
      email: "new.person@example.test",
      display_name: "New Person",
    });
    expect(within(form).getByLabelText("E-mail address")).toHaveValue("");
  });

  test("leaves out an empty display name and shows 409 user_exists", async () => {
    const { user, requests } = renderPage({
      "POST /api/admin/users": { status: 409, body: { error: "user_exists" } },
    });
    const form = await screen.findByRole("region", {
      name: "Invite a person",
    });

    await user.type(
      within(form).getByLabelText("E-mail address"),
      "ada@example.test",
    );
    await user.click(
      within(form).getByRole("button", { name: "Send invitation" }),
    );

    expect(
      await within(form).findByText(
        "An account with this e-mail address exists already.",
      ),
    ).toHaveAttribute("role", "alert");
    expect(requestsTo(requests, "POST", "/api/admin/users")[0].body).toEqual({
      email: "ada@example.test",
    });
  });

  test("shows a rejected address at its field", async () => {
    const { user } = renderPage({
      "POST /api/admin/users": {
        status: 422,
        body: { error: "validation_failed", fields: { email: ["format"] } },
      },
    });
    const form = await screen.findByRole("region", {
      name: "Invite a person",
    });

    const field = within(form).getByLabelText("E-mail address");
    await user.type(field, "x@y");
    await user.click(
      within(form).getByRole("button", { name: "Send invitation" }),
    );

    await waitFor(() =>
      expect(field).toHaveAccessibleDescription(
        "Enter a valid e-mail address.",
      ),
    );
    expect(field).toHaveAttribute("aria-invalid", "true");
  });

  test("shows a note in place of the form while local accounts are off", async () => {
    renderPage({}, { session: admin({ flags: { local_accounts: false } }) });

    const section = await screen.findByRole("region", {
      name: "Invite a person",
    });
    expect(section).toHaveTextContent(
      "Local accounts are turned off on this instance.",
    );
    expect(within(section).queryByRole("textbox")).not.toBeInTheDocument();
  });
});

describe("the lookup", () => {
  test("sends the address in the body and shows the user with its actions", async () => {
    const { user, requests } = renderPage({
      "POST /api/admin/user-lookups": { status: 200, body: ben },
    });
    const section = await screen.findByRole("region", {
      name: "Find a person",
    });

    await user.type(
      within(section).getByLabelText("E-mail address"),
      "  ben@example.test ",
    );
    await user.click(within(section).getByRole("button", { name: "Find" }));

    const row = await rowOf("Search result", "Ben Invited");
    expect(
      within(row).getByRole("button", { name: "Disable Ben Invited" }),
    ).toBeInTheDocument();
    expect(
      requestsTo(requests, "POST", "/api/admin/user-lookups")[0].body,
    ).toEqual({ email: "ben@example.test" });
  });

  test("says so when no account has the address", async () => {
    const { user } = renderPage({
      "POST /api/admin/user-lookups": {
        status: 404,
        body: { error: "not_found" },
      },
    });
    const section = await screen.findByRole("region", {
      name: "Find a person",
    });

    await user.type(
      within(section).getByLabelText("E-mail address"),
      "nobody@example.test",
    );
    await user.click(within(section).getByRole("button", { name: "Find" }));

    expect(
      await within(section).findByText("No account has this address."),
    ).toHaveAttribute("role", "status");
  });
});

describe("ending every session", () => {
  test("states that the admin's own session ends and refetches the session", async () => {
    const { user, requests } = renderPage({
      "DELETE /api/admin/sessions": { status: 204 },
    });
    const section = await screen.findByRole("region", { name: "All sessions" });

    await user.click(
      within(section).getByRole("button", { name: "End all sessions" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "End every session?",
    });
    expect(dialog).toHaveTextContent(
      "Your own session ends as well, and you sign in again afterwards.",
    );
    await user.click(
      within(dialog).getByRole("button", { name: "End all sessions" }),
    );

    await waitFor(() =>
      expect(requestsTo(requests, "GET", "/api/session")).toHaveLength(1),
    );
    expect(requestsTo(requests, "DELETE", "/api/admin/sessions")).toHaveLength(
      1,
    );
  });
});

describe("the revocation of a credential", () => {
  test("checks the id, asks first and reports the qualification", async () => {
    const { user, requests } = renderPage({
      [`POST /api/admin/credentials/${CREDENTIAL}/revoke`]: [
        {
          status: 200,
          body: {
            id: CREDENTIAL,
            qualification_code: "basic",
            status: "revoked",
          },
        },
        { status: 409, body: { error: "already_revoked" } },
      ],
    });
    const section = await screen.findByRole("region", {
      name: "Revoke a credential",
    });
    const field = within(section).getByLabelText("Credential id");

    await user.type(field, "not-an-id");
    await user.click(within(section).getByRole("button", { name: "Revoke" }));
    expect(field).toHaveAccessibleDescription(
      "Enter the id in the form 01234567-89ab-cdef-0123-456789abcdef.",
    );
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();

    await user.clear(field);
    await user.type(field, CREDENTIAL);
    await user.click(within(section).getByRole("button", { name: "Revoke" }));
    const dialog = await screen.findByRole("dialog", {
      name: "Revoke this credential?",
    });
    expect(dialog).toHaveTextContent(
      `The credential ${CREDENTIAL} receives the status revoked at once.`,
    );
    await user.click(
      within(dialog).getByRole("button", { name: "Revoke credential" }),
    );
    expect(
      await within(section).findByText(
        "The credential of the qualification basic is revoked.",
      ),
    ).toHaveAttribute("role", "status");

    await user.type(field, CREDENTIAL);
    await user.click(within(section).getByRole("button", { name: "Revoke" }));
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", {
        name: "Revoke credential",
      }),
    );
    expect(
      await within(section).findByText("This credential is revoked already."),
    ).toHaveAttribute("role", "alert");
    expect(
      requestsTo(
        requests,
        "POST",
        `/api/admin/credentials/${CREDENTIAL}/revoke`,
      ),
    ).toHaveLength(2);
  });

  test("an unknown id answers 'No credential has this id.'", async () => {
    const { user } = renderPage();
    const section = await screen.findByRole("region", {
      name: "Revoke a credential",
    });

    await user.type(
      within(section).getByLabelText("Credential id"),
      CREDENTIAL,
    );
    await user.click(within(section).getByRole("button", { name: "Revoke" }));
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", {
        name: "Revoke credential",
      }),
    );

    expect(
      await within(section).findByText("No credential has this id."),
    ).toHaveAttribute("role", "alert");
  });
});

describe("accessibility", () => {
  test("axe reports no violation on the page and in the reset dialog", async () => {
    const { container, user } = renderPage();
    await screen.findByRole("table", { name: "All users" });
    await expectNoAxeViolations(container);

    await user.click(
      within(await listRow("Ben Invited")).getByRole("button", {
        name: "Reset second factors Ben Invited",
      }),
    );
    await screen.findByRole("dialog", { name: "Reset the second factors?" });
    await expectNoAxeViolations(document.body);
  });
});

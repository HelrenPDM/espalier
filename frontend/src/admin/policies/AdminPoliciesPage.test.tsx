import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type {
  AdminPolicy,
  AdminPolicyVersionSummary,
} from "../../api/admin/policies";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { AdminPoliciesPage } from "./AdminPoliciesPage";

/**
 * Task 0015 step 13: `/admin/policies` lists the policies with create,
 * change and delete (409 `policy_in_use`), the versions of the open policy
 * with their state, a Markdown editor with a live preview, and a publish
 * dialog with `requires_refresher` and `refresh_due_count`. A draft below
 * a published version is marked superseded, and its publish dialog states
 * that it cannot be published and offers no confirmation; a 409
 * `superseded` answer shows the same statement, and a 409 `published` its
 * own message.
 */
const USAGE = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d";
const EXPORT = "2b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e";
const V1 = "3c4d5e6f-7a8b-4c9d-8e0f-2a3b4c5d6e7f";
const V2 = "4d5e6f7a-8b9c-4d0e-9f1a-3b4c5d6e7f8a";
const V3 = "5e6f7a8b-9c0d-4e1f-8a2b-4c5d6e7f8a9b";
const V4 = "6f7a8b9c-0d1e-4f2a-9b3c-5d6e7f8a9b0c";
const POLICIES = "/api/admin/policies";
const VERSIONS = "/api/admin/policy-versions";

const policies: AdminPolicy[] = [
  { id: EXPORT, key: "export-policy", title: "Export policy" },
  { id: USAGE, key: "usage-policy", title: "Usage policy" },
];

const version = (
  id: string,
  number: number,
  publishedAt: string | null,
  body = `Text of version ${number}.`,
): AdminPolicyVersionSummary => ({
  id,
  policy_id: USAGE,
  policy_key: "usage-policy",
  policy_title: "Usage policy",
  number,
  body,
  effective_from: "2026-10-01",
  published_at: publishedAt,
  requires_refresher: false,
});

// The highest number first, as the route lists them: version 2 is a draft
// below the published version 3, so it is superseded.
const versions = [
  version(V4, 4, null, "Use only **approved** assistants."),
  version(V3, 3, "2026-09-01T08:00:00Z"),
  version(V2, 2, null),
  version(V1, 1, "2026-03-01T08:00:00Z"),
];

const admin = signedInPayload("mfa", { roles: ["learner", "admin"] });

function renderPage(
  responses: StubResponses = {},
  route = `/admin/policies?policy=${USAGE}`,
  // The Layout renders every page inside <main>.
  ui = <AdminPoliciesPage />,
) {
  return renderWithProviders(ui, {
    route,
    path: "/admin/policies",
    session: admin,
    responses: {
      [`GET ${POLICIES}`]: { status: 200, body: { data: policies } },
      [`GET ${VERSIONS}`]: { status: 200, body: { versions } },
      [`GET ${VERSIONS}/${V4}`]: {
        status: 200,
        body: { ...versions[0], refresh_due_count: 3 },
      },
      ...responses,
    },
  });
}

const versionTable = () => screen.findByRole("table", { name: "Versions" });

/** The texts of the cells of each body row, the row header first. */
const bodyRows = (table: HTMLElement) =>
  within(table)
    .getAllByRole("row")
    .slice(1)
    .map((row) =>
      Array.from(row.querySelectorAll("th, td")).map(
        (cell) => cell.textContent,
      ),
    );

describe("the policy list", () => {
  test("lists the policies and opens one into the query", async () => {
    const { user, location } = renderPage({}, "/admin/policies");

    const list = await screen.findByRole("table", { name: "All policies" });
    expect(bodyRows(list)).toEqual([
      ["Export policy", "export-policy", "Open Export policy"],
      ["Usage policy", "usage-policy", "Open Usage policy"],
    ]);
    expect(
      screen.queryByRole("heading", { level: 2, name: "Usage policy" }),
    ).not.toBeInTheDocument();

    await user.click(
      within(list).getByRole("button", { name: "Open Usage policy" }),
    );
    expect(
      await screen.findByRole("heading", { level: 2, name: "Usage policy" }),
    ).toBeInTheDocument();
    expect(location()).toBe(`/admin/policies?policy=${USAGE}`);
    expect(
      within(list).getByRole("button", { name: "Open Usage policy" }),
    ).toHaveAttribute("aria-pressed", "true");
  });

  test("creates a policy with the nested body and checks the key first", async () => {
    const created: AdminPolicy = {
      id: "7a8b9c0d-1e2f-4a3b-8c4d-6e7f8a9b0c1d",
      key: "data-policy",
      title: "Data policy",
    };
    const { user, requests, location } = renderPage(
      { [`POST ${POLICIES}`]: { status: 201, body: { data: created } } },
      "/admin/policies",
    );
    await screen.findByRole("table", { name: "All policies" });
    const form = screen.getByRole("region", { name: "New policy" });

    await user.type(
      within(form).getByRole("textbox", { name: "Title" }),
      "Data policy",
    );
    const key = within(form).getByRole("textbox", { name: "Key" });
    await user.type(key, "Data Policy");
    await user.click(
      within(form).getByRole("button", { name: "Create the policy" }),
    );
    expect(key).toHaveAccessibleDescription(
      expect.stringContaining(
        "Use lower-case letters, digits and hyphens, starting with a letter or a digit.",
      ),
    );
    expect(requestsTo(requests, "POST", POLICIES)).toHaveLength(0);

    await user.clear(key);
    await user.type(key, "data-policy");
    await user.click(
      within(form).getByRole("button", { name: "Create the policy" }),
    );

    expect(
      await screen.findByText("The policy Data policy is created."),
    ).toBeInTheDocument();
    const [post] = requestsTo(requests, "POST", POLICIES);
    expect(post.body).toEqual({
      policy: { key: "data-policy", title: "Data policy" },
    });
    expect(post.headers.get("x-csrf-token")).toBe("csrf-1");
    expect(location()).toBe(`/admin/policies?policy=${created.id}`);
  });

  test("shows a taken key at the field", async () => {
    const { user } = renderPage(
      {
        [`POST ${POLICIES}`]: {
          status: 422,
          body: { error: "validation_failed", fields: { key: ["unique"] } },
        },
      },
      "/admin/policies",
    );
    await screen.findByRole("table", { name: "All policies" });
    const form = screen.getByRole("region", { name: "New policy" });

    await user.type(
      within(form).getByRole("textbox", { name: "Title" }),
      "Usage",
    );
    const key = within(form).getByRole("textbox", { name: "Key" });
    await user.type(key, "usage-policy");
    await user.click(
      within(form).getByRole("button", { name: "Create the policy" }),
    );

    await waitFor(() =>
      expect(key).toHaveAccessibleDescription(
        expect.stringContaining("Another policy has this key."),
      ),
    );
  });
});

describe("an open policy", () => {
  test("changes the title with the nested body and keeps the key of a policy in use", async () => {
    const renamed = { id: USAGE, key: "usage-policy", title: "AI usage" };
    const { user, requests } = renderPage({
      [`GET ${POLICIES}`]: [
        { status: 200, body: { data: policies } },
        { status: 200, body: { data: [policies[0], renamed] } },
      ],
      [`PUT ${POLICIES}/${USAGE}`]: [
        { status: 200, body: { data: renamed } },
        { status: 409, body: { error: "policy_in_use" } },
      ],
    });
    const detail = await screen.findByRole("region", { name: "Usage policy" });

    const title = within(detail).getByRole("textbox", { name: "Title" });
    await user.clear(title);
    await user.type(title, "AI usage");
    await user.click(
      within(detail).getByRole("button", { name: "Save key and title" }),
    );
    expect(
      await within(detail).findByText("Key and title are saved."),
    ).toBeInTheDocument();
    expect(requestsTo(requests, "PUT", `${POLICIES}/${USAGE}`)[0].body).toEqual(
      { policy: { title: "AI usage" } },
    );

    const key = within(detail).getByRole("textbox", { name: "Key" });
    await user.clear(key);
    await user.type(key, "ai-usage");
    await user.click(
      within(detail).getByRole("button", { name: "Save key and title" }),
    );
    await waitFor(() =>
      expect(key).toHaveAccessibleDescription(
        expect.stringContaining(
          "The key of a policy with a published version cannot change.",
        ),
      ),
    );
    expect(requestsTo(requests, "PUT", `${POLICIES}/${USAGE}`)[1].body).toEqual(
      { policy: { key: "ai-usage" } },
    );
  });

  test("shows the 409 policy_in_use of a deletion and deletes a policy of drafts", async () => {
    const { user, requests, location } = renderPage({
      [`DELETE ${POLICIES}/${USAGE}`]: [
        { status: 409, body: { error: "policy_in_use" } },
        { status: 204 },
      ],
    });
    const detail = await screen.findByRole("region", { name: "Usage policy" });

    await user.click(
      within(detail).getByRole("button", { name: "Delete the policy" }),
    );
    let dialog = await screen.findByRole("dialog", {
      name: "Delete the policy?",
    });
    expect(dialog).toHaveTextContent(
      "Usage policy is deleted together with its drafts.",
    );
    await user.click(
      within(dialog).getByRole("button", { name: "Delete the policy" }),
    );
    expect(
      await within(detail).findByText(
        "This policy has a published version and cannot be deleted.",
      ),
    ).toHaveAttribute("role", "alert");

    await user.click(
      within(detail).getByRole("button", { name: "Delete the policy" }),
    );
    dialog = await screen.findByRole("dialog", { name: "Delete the policy?" });
    await user.click(
      within(dialog).getByRole("button", { name: "Delete the policy" }),
    );
    expect(
      await screen.findByText("The policy Usage policy is deleted."),
    ).toBeInTheDocument();
    expect(requestsTo(requests, "DELETE", `${POLICIES}/${USAGE}`)).toHaveLength(
      2,
    );
    expect(location()).toBe("/admin/policies");
  });

  test("lists the versions with their state and marks a superseded draft", async () => {
    renderPage();

    const table = await versionTable();
    expect(bodyRows(table)).toEqual([
      [
        "Version 4",
        "Draft",
        "Oct 1, 2026",
        "Not required",
        "Edit Version 4Publish Version 4",
      ],
      [
        "Version 3",
        "Published on Sep 1, 2026",
        "Oct 1, 2026",
        "Not required",
        "",
      ],
      [
        "Version 2",
        "Superseded draftA version with a higher number is published, so this draft cannot be published.",
        "Oct 1, 2026",
        "Not required",
        "Edit Version 2Publish Version 2",
      ],
      [
        "Version 1",
        "Published on Mar 1, 2026",
        "Oct 1, 2026",
        "Not required",
        "",
      ],
    ]);
  });
});

describe("the publish dialog", () => {
  test("states that a superseded draft cannot be published and offers no confirmation", async () => {
    const { user, requests } = renderPage();

    const table = await versionTable();
    await user.click(
      within(table).getByRole("button", { name: "Publish Version 2" }),
    );

    const dialog = await screen.findByRole("dialog", {
      name: "Publish version 2 of Usage policy",
    });
    expect(within(dialog).getByRole("alert")).toHaveTextContent(
      "This draft cannot be published. The policy has a published version with a higher number, so this draft would never become the current version.",
    );
    expect(
      within(dialog)
        .getAllByRole("button")
        .map((button) => button.textContent),
    ).toEqual(["Close"]);
    expect(within(dialog).queryByRole("checkbox")).not.toBeInTheDocument();
    expect(requestsTo(requests, "GET", `${VERSIONS}/${V2}`)).toHaveLength(0);

    await user.click(within(dialog).getByRole("button", { name: "Close" }));
    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );
    expect(
      requests.filter((request) => request.path.endsWith("/publish")),
    ).toEqual([]);
  });

  test("shows refresh_due_count and sends requires_refresher", async () => {
    const published = {
      ...versions[0],
      published_at: "2026-10-12T09:00:00Z",
      requires_refresher: true,
      refresh_due_count: 0,
    };
    const { user, requests } = renderPage({
      [`POST ${VERSIONS}/${V4}/publish`]: { status: 200, body: published },
    });

    const table = await versionTable();
    await user.click(
      within(table).getByRole("button", { name: "Publish Version 4" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Publish version 4 of Usage policy",
    });
    expect(dialog).toHaveTextContent(
      "Version 4 becomes the current version of the policy, in effect from Oct 1, 2026.",
    );
    const checkbox = within(dialog).getByRole("checkbox", {
      name: "Requires a refresher",
    });
    expect(checkbox).not.toBeChecked();
    expect(
      await within(dialog).findByText(
        "With this option, 3 credentials move to Refresher due now.",
      ),
    ).toBeInTheDocument();
    expect(checkbox).toHaveAccessibleDescription(
      "Moves the credentials whose qualification requires this policy to the status Refresher due. With this option, 3 credentials move to Refresher due now.",
    );

    await user.click(checkbox);
    await user.click(within(dialog).getByRole("button", { name: "Publish" }));

    expect(
      await screen.findByText("Version 4 is published."),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );
    const [post] = requestsTo(requests, "POST", `${VERSIONS}/${V4}/publish`);
    expect(post.body).toEqual({ requires_refresher: true });
    expect(post.headers.get("x-csrf-token")).toBe("csrf-1");
    // The versions load again after the publication.
    await waitFor(() =>
      expect(requestsTo(requests, "GET", VERSIONS)).toHaveLength(2),
    );
  });

  test.each([
    [
      "superseded",
      "This draft cannot be published. The policy has a published version with a higher number, so this draft would never become the current version.",
    ],
    [
      "published",
      "This version is already published and can no longer change.",
    ],
  ])(
    "shows the statement of a 409 %s answer and no confirmation",
    async (code, statement) => {
      const { user } = renderPage({
        [`POST ${VERSIONS}/${V4}/publish`]: {
          status: 409,
          body: { error: code },
        },
      });

      const table = await versionTable();
      await user.click(
        within(table).getByRole("button", { name: "Publish Version 4" }),
      );
      const dialog = await screen.findByRole("dialog");
      await within(dialog).findByText(
        "With this option, 3 credentials move to Refresher due now.",
      );
      await user.click(within(dialog).getByRole("button", { name: "Publish" }));

      expect(await within(dialog).findByRole("alert")).toHaveTextContent(
        statement,
      );
      expect(
        within(dialog)
          .getAllByRole("button")
          .map((button) => button.textContent),
      ).toEqual(["Close"]);
    },
  );
});

describe("the Markdown editor", () => {
  test("starts a new draft from the highest version, previews it and creates it", async () => {
    const { user, requests } = renderPage({
      [`POST ${VERSIONS}`]: {
        status: 201,
        body: { ...version(V4, 5, null), refresh_due_count: 3 },
      },
    });
    await versionTable();

    await user.click(screen.getByRole("button", { name: "New draft" }));
    const editor = screen.getByRole("region", { name: "New draft" });
    const text = within(editor).getByRole("textbox", {
      name: "Text (Markdown)",
    });
    expect(text).toHaveValue("Use only **approved** assistants.");
    const preview = within(editor).getByRole("region", { name: "Preview" });
    expect(within(preview).getByText("approved").tagName).toBe("STRONG");
    // The text of the organization inherits the language of the document.
    expect(within(preview).getByText("approved").closest("[lang]")).toBe(
      document.documentElement,
    );

    await user.clear(text);
    await user.type(text, "# Rules{enter}{enter}1. Enter no personal data.");
    expect(
      within(preview).getByRole("heading", { name: "Rules" }),
    ).toBeInTheDocument();
    expect(within(preview).getByRole("listitem")).toHaveTextContent(
      "Enter no personal data.",
    );
    const day = within(editor).getByLabelText("In effect from");
    await user.clear(day);
    await user.type(day, "2026-11-01");
    await user.click(
      within(editor).getByRole("button", { name: "Save the draft" }),
    );

    expect(
      await screen.findByText("The draft of version 5 is saved."),
    ).toBeInTheDocument();
    const [post] = requestsTo(requests, "POST", VERSIONS);
    expect(post.body).toEqual({
      policy_id: USAGE,
      body: "# Rules\n\n1. Enter no personal data.",
      effective_from: "2026-11-01",
    });
    expect(
      screen.queryByRole("region", { name: "New draft" }),
    ).not.toBeInTheDocument();
  });

  test("changes a draft and shows the 409 published answer", async () => {
    const { user, requests } = renderPage({
      [`PUT ${VERSIONS}/${V4}`]: [
        { status: 200, body: { ...versions[0], refresh_due_count: 3 } },
        { status: 409, body: { error: "published" } },
      ],
    });

    const table = await versionTable();
    await user.click(
      within(table).getByRole("button", { name: "Edit Version 4" }),
    );
    let editor = screen.getByRole("region", {
      name: "Draft of version 4",
    });
    const text = within(editor).getByRole("textbox", {
      name: "Text (Markdown)",
    });
    await user.type(text, " Always.");
    await user.click(
      within(editor).getByRole("button", { name: "Save the draft" }),
    );
    expect(
      await screen.findByText("The draft of version 4 is saved."),
    ).toBeInTheDocument();
    expect(requestsTo(requests, "PUT", `${VERSIONS}/${V4}`)[0].body).toEqual({
      body: "Use only **approved** assistants. Always.",
      effective_from: "2026-10-01",
    });

    await user.click(
      within(table).getByRole("button", { name: "Edit Version 4" }),
    );
    editor = screen.getByRole("region", { name: "Draft of version 4" });
    await user.click(
      within(editor).getByRole("button", { name: "Save the draft" }),
    );
    expect(await within(editor).findByRole("alert")).toHaveTextContent(
      "This version is published and can no longer change.",
    );
  });
});

describe("accessibility", () => {
  test("has no axe violations with the versions, the editor and the publish dialog", async () => {
    const { user } = renderPage(
      undefined,
      undefined,
      <main>
        <AdminPoliciesPage />
      </main>,
    );

    const table = await versionTable();
    await user.click(screen.getByRole("button", { name: "New draft" }));
    await expectNoAxeViolations(document.body);

    await user.click(
      within(table).getByRole("button", { name: "Publish Version 4" }),
    );
    const dialog = await screen.findByRole("dialog");
    await within(dialog).findByText(
      "With this option, 3 credentials move to Refresher due now.",
    );
    await expectNoAxeViolations(document.body);
  });
});

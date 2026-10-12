import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type { AdminApprovedTool } from "../../api/admin/approvedTools";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { ApprovedToolsPage } from "./ApprovedToolsPage";

/**
 * Task 0015 step 14: `/admin/approved-tools` shows the approved tool list in
 * a table that sorts by each column, edits a row in place and sends the
 * changed fields in the nested body `{"approved_tool": {...}}` of the
 * generated route, adds a tool and deletes one after a confirmation.
 */
const DRAFTWELL = "8b3e4d5c-6f70-4b82-8c9d-1e2f3a4b5c6d";
const OPENCHAT = "9c4f5e6d-7081-4c93-9dae-2f3a4b5c6d7e";
const ATLAS = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d";
const LIST = "/api/admin/approved-tools";

const tools: AdminApprovedTool[] = [
  {
    id: DRAFTWELL,
    name: "Draftwell",
    vendor: "Example Software Ltd.",
    status: "approved",
    conditions: "Internal drafts without personal data.",
    reviewed_on: "2026-09-01",
    position: 1,
  },
  {
    id: OPENCHAT,
    name: "OpenChat Free",
    vendor: "Placeholder Labs",
    status: "not_approved",
    conditions: null,
    reviewed_on: null,
    position: 2,
  },
  {
    id: ATLAS,
    name: "Atlas Notes",
    vendor: "Sample Systems",
    status: "restricted",
    conditions: "Only for public sources.",
    reviewed_on: "2026-07-15",
    position: 3,
  },
];

const admin = signedInPayload("mfa", { roles: ["learner", "admin"] });

function renderPage(responses: StubResponses = {}) {
  return renderWithProviders(<ApprovedToolsPage />, {
    route: "/admin/approved-tools",
    session: admin,
    responses: {
      [`GET ${LIST}`]: { status: 200, body: { data: tools } },
      ...responses,
    },
  });
}

const table = () => screen.findByRole("table", { name: "Tool list" });

/** The row headers (the tool names) in the order of the table. */
const names = (scope: HTMLElement) =>
  within(scope)
    .getAllByRole("rowheader")
    .map((cell) => cell.textContent);

const rowOf = (scope: HTMLElement, name: string) => {
  const row = within(scope).getByRole("rowheader", { name }).closest("tr");
  if (row === null) throw new Error(`no row for ${name}`);
  return row;
};

describe("the approved tools page", () => {
  test("lists the tools by position and sorts by a column", async () => {
    const { user } = renderPage();

    const list = await table();
    expect(names(list)).toEqual(["Draftwell", "OpenChat Free", "Atlas Notes"]);
    expect(
      within(rowOf(list, "OpenChat Free"))
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual([
      "2",
      "Placeholder Labs",
      "Not approved",
      "None",
      "Not reviewed yet",
      "Edit OpenChat FreeDelete OpenChat Free",
    ]);
    const position = within(list).getByRole("columnheader", {
      name: "Position",
    });
    expect(position).toHaveAttribute("aria-sort", "ascending");

    await user.click(within(list).getByRole("button", { name: "Name" }));
    expect(names(list)).toEqual(["Atlas Notes", "Draftwell", "OpenChat Free"]);
    expect(
      within(list).getByRole("columnheader", { name: "Name" }),
    ).toHaveAttribute("aria-sort", "ascending");
    expect(position).not.toHaveAttribute("aria-sort");

    await user.click(within(list).getByRole("button", { name: "Name" }));
    expect(names(list)).toEqual(["OpenChat Free", "Draftwell", "Atlas Notes"]);
    expect(
      within(list).getByRole("columnheader", { name: "Name" }),
    ).toHaveAttribute("aria-sort", "descending");

    // A tool without a review date stays last in both directions.
    await user.click(within(list).getByRole("button", { name: "Reviewed on" }));
    expect(names(list)).toEqual(["Atlas Notes", "Draftwell", "OpenChat Free"]);
    await user.click(within(list).getByRole("button", { name: "Reviewed on" }));
    expect(names(list)).toEqual(["Draftwell", "Atlas Notes", "OpenChat Free"]);

    await user.click(within(list).getByRole("button", { name: "Status" }));
    expect(names(list)).toEqual(["Draftwell", "Atlas Notes", "OpenChat Free"]);
  });

  test("edits a row in place and sends the changed fields in the nested body", async () => {
    const changed = {
      ...tools[0],
      vendor: "Example Software GmbH",
      status: "restricted" as const,
      reviewed_on: null,
    };
    const { user, requests } = renderPage({
      [`GET ${LIST}`]: [
        { status: 200, body: { data: tools } },
        { status: 200, body: { data: [changed, tools[1], tools[2]] } },
      ],
      [`PUT ${LIST}/${DRAFTWELL}`]: { status: 200, body: { data: changed } },
    });

    const list = await table();
    await user.click(
      within(list).getByRole("button", { name: "Edit Draftwell" }),
    );

    const name = within(list).getByRole("textbox", { name: "Name" });
    expect(name).toHaveValue("Draftwell");
    expect(name).toHaveFocus();
    const vendor = within(list).getByRole("textbox", { name: "Vendor" });
    await user.clear(vendor);
    await user.type(vendor, "Example Software GmbH");
    await user.selectOptions(
      within(list).getByRole("combobox", { name: "Status" }),
      "restricted",
    );
    await user.clear(within(list).getByLabelText("Reviewed on"));
    await user.click(within(list).getByRole("button", { name: "Save" }));

    expect(
      await screen.findByText("The changes to Draftwell are saved."),
    ).toBeInTheDocument();
    const [put] = requestsTo(requests, "PUT", `${LIST}/${DRAFTWELL}`);
    expect(put.body).toEqual({
      approved_tool: {
        vendor: "Example Software GmbH",
        status: "restricted",
        reviewed_on: null,
      },
    });
    expect(put.headers.get("x-csrf-token")).toBe("csrf-1");
    await waitFor(() =>
      expect(requestsTo(requests, "GET", LIST)).toHaveLength(2),
    );
    const row = rowOf(list, "Draftwell");
    expect(row).toHaveTextContent("Example Software GmbH");
    expect(row).toHaveTextContent("Restricted");
    await waitFor(() =>
      expect(
        within(row).getByRole("button", { name: "Edit Draftwell" }),
      ).toHaveFocus(),
    );
  });

  test("shows the error of a taken name at the field and keeps the row open", async () => {
    const { user } = renderPage({
      [`PUT ${LIST}/${DRAFTWELL}`]: {
        status: 422,
        body: { error: "validation_failed", fields: { name: ["unique"] } },
      },
    });

    const list = await table();
    await user.click(
      within(list).getByRole("button", { name: "Edit Draftwell" }),
    );
    const name = within(list).getByRole("textbox", { name: "Name" });
    await user.clear(name);
    await user.type(name, "Atlas Notes");
    await user.click(within(list).getByRole("button", { name: "Save" }));

    await waitFor(() => expect(name).toHaveAttribute("aria-invalid", "true"));
    expect(name).toHaveAccessibleDescription("Another tool has this name.");
  });

  test("checks the fields before it sends, and Escape leaves the row unchanged", async () => {
    const { user, requests } = renderPage();

    const list = await table();
    await user.click(
      within(list).getByRole("button", { name: "Edit Draftwell" }),
    );
    await user.clear(within(list).getByRole("textbox", { name: "Name" }));
    await user.clear(
      within(list).getByRole("spinbutton", { name: "Position" }),
    );
    await user.click(within(list).getByRole("button", { name: "Save" }));

    expect(
      within(list).getByRole("textbox", { name: "Name" }),
    ).toHaveAccessibleDescription("Enter a value.");
    expect(
      within(list).getByRole("spinbutton", { name: "Position" }),
    ).toHaveAccessibleDescription("Enter a whole number from 0.");

    await user.keyboard("{Escape}");
    expect(
      within(list).queryByRole("textbox", { name: "Name" }),
    ).not.toBeInTheDocument();
    expect(names(list)).toEqual(["Draftwell", "OpenChat Free", "Atlas Notes"]);
    expect(requestsTo(requests, "PUT", `${LIST}/${DRAFTWELL}`)).toHaveLength(0);
  });

  test("adds a tool after the last position", async () => {
    const added: AdminApprovedTool = {
      id: "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
      name: "Transcriber",
      vendor: "Demo Audio",
      status: "restricted",
      conditions: null,
      reviewed_on: null,
      position: 4,
    };
    const { user, requests } = renderPage({
      [`POST ${LIST}`]: { status: 201, body: { data: added } },
    });
    await table();

    const form = screen.getByRole("region", { name: "Add a tool" });
    expect(
      within(form).getByRole("spinbutton", { name: "Position" }),
    ).toHaveValue(4);
    await user.type(
      within(form).getByRole("textbox", { name: "Name" }),
      "Transcriber",
    );
    await user.type(
      within(form).getByRole("textbox", { name: "Vendor" }),
      "Demo Audio",
    );
    await user.selectOptions(
      within(form).getByRole("combobox", { name: "Status" }),
      "restricted",
    );
    await user.click(
      within(form).getByRole("button", { name: "Add the tool" }),
    );

    expect(
      await screen.findByText("Transcriber is added."),
    ).toBeInTheDocument();
    const [post] = requestsTo(requests, "POST", LIST);
    expect(post.body).toEqual({
      approved_tool: {
        name: "Transcriber",
        vendor: "Demo Audio",
        status: "restricted",
        conditions: null,
        reviewed_on: null,
        position: 4,
      },
    });
    expect(within(form).getByRole("textbox", { name: "Name" })).toHaveValue("");
  });

  test("deletes a tool after the confirmation", async () => {
    const { user, requests } = renderPage({
      [`DELETE ${LIST}/${OPENCHAT}`]: { status: 204 },
    });

    const list = await table();
    await user.click(
      within(list).getByRole("button", { name: "Delete OpenChat Free" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Delete the tool?",
    });
    expect(dialog).toHaveTextContent(
      "OpenChat Free leaves the approved tool list, and the policies page no longer shows it.",
    );
    await user.click(within(dialog).getByRole("button", { name: "Delete" }));

    expect(
      await screen.findByText("OpenChat Free is deleted."),
    ).toBeInTheDocument();
    expect(requestsTo(requests, "DELETE", `${LIST}/${OPENCHAT}`)).toHaveLength(
      1,
    );
  });

  test("sends nothing when the deletion is cancelled", async () => {
    const { user, requests } = renderPage();

    const list = await table();
    await user.click(
      within(list).getByRole("button", { name: "Delete OpenChat Free" }),
    );
    const dialog = await screen.findByRole("dialog");
    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() =>
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
    );
    expect(requests.filter((request) => request.method === "DELETE")).toEqual(
      [],
    );
  });

  test("states an empty list", async () => {
    renderPage({ [`GET ${LIST}`]: { status: 200, body: { data: [] } } });
    expect(
      await screen.findByText(
        "The list of approved tools is empty. Add the first tool below.",
      ),
    ).toBeInTheDocument();
  });

  test("has no axe violations with the list and with a row in editing", async () => {
    const { container, user } = renderPage();

    const list = await table();
    await expectNoAxeViolations(container);
    await user.click(
      within(list).getByRole("button", { name: "Edit Draftwell" }),
    );
    await expectNoAxeViolations(container);
  });
});

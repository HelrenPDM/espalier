import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type { ApprovedTool, CurrentPolicy } from "../api/policies";
import { expectNoAxeViolations } from "../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../test/render";
import { signedInPayload } from "../test/session";
import { PoliciesPage } from "./PoliciesPage";

/**
 * Task 0013 steps 23 and 25: `/policies` shows the current version of each
 * policy as Markdown with title, number and effective date, sends the
 * acknowledgement of a version with the CSRF token and shows the new state,
 * and lists the approved tools.
 */
const USAGE_ID = "6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b";
const EXPORT_ID = "7a2d3c4b-5e6f-4a71-9b8c-0d1e2f3a4b5c";
const ACK_PATH = `/api/policy-versions/${USAGE_ID}/acknowledgements`;
const ACKNOWLEDGED_AT = "2026-10-11T09:30:00Z";

const usagePolicy = (acknowledgedAt: string | null): CurrentPolicy => ({
  id: USAGE_ID,
  key: "usage-policy",
  title: "Usage policy",
  number: 2,
  effective_from: "2026-10-01",
  body: "Use only **approved** assistants.\n\n1. Enter no personal data.",
  acknowledged_at: acknowledgedAt,
});

const exportPolicy: CurrentPolicy = {
  id: EXPORT_ID,
  key: "export-policy",
  title: "Export policy",
  number: 1,
  effective_from: "2026-09-01",
  body: "Share drafts inside the team only.",
  acknowledged_at: "2026-09-20T08:00:00Z",
};

const tools: ApprovedTool[] = [
  {
    id: "8b3e4d5c-6f70-4b82-8c9d-1e2f3a4b5c6d",
    name: "Draftwell",
    vendor: "Example Software Ltd.",
    status: "approved",
    conditions: "Internal drafts without personal data.",
    reviewed_on: "2026-09-01",
    position: 1,
  },
  {
    id: "9c4f5e6d-7081-4c93-9dae-2f3a4b5c6d7e",
    name: "OpenChat Free",
    vendor: "Placeholder Labs",
    status: "not_approved",
    conditions: null,
    reviewed_on: null,
    position: 2,
  },
];

function renderPolicies(responses: StubResponses = {}) {
  return renderWithProviders(<PoliciesPage />, {
    route: "/policies",
    session: signedInPayload("mfa"),
    responses: {
      "GET /api/policies": [
        {
          status: 200,
          body: { policies: [exportPolicy, usagePolicy(null)] },
        },
        {
          status: 200,
          body: { policies: [exportPolicy, usagePolicy(ACKNOWLEDGED_AT)] },
        },
      ],
      "GET /api/approved-tools": { status: 200, body: { tools } },
      [`POST ${ACK_PATH}`]: {
        status: 200,
        body: {
          policy_version_id: USAGE_ID,
          acknowledged_at: ACKNOWLEDGED_AT,
        },
      },
      ...responses,
    },
  });
}

const policySection = (title: string) =>
  screen.findByRole("region", { name: title });

describe("the policies page", () => {
  test("shows each current version as Markdown with title, number and effective date", async () => {
    renderPolicies();

    const usage = await policySection("Usage policy");
    expect(
      within(usage).getByText("Version 2, in effect from Oct 1, 2026."),
    ).toBeInTheDocument();
    const policyText = within(usage).getByText("approved", {
      selector: "strong",
    });
    // The policy text inherits the language of the document.
    expect(policyText.closest("[lang]")).toBe(document.documentElement);
    expect(within(usage).getByRole("listitem")).toHaveTextContent(
      "Enter no personal data.",
    );
    expect(
      within(usage).getByRole("button", { name: "I have read this version" }),
    ).toBeEnabled();

    // An acknowledged version shows the date and no button.
    const exported = await policySection("Export policy");
    expect(exported).toHaveTextContent(
      "You acknowledged this version on Sep 20, 2026.",
    );
    expect(within(exported).queryByRole("button")).toBeNull();
  });

  test("sends the acknowledgement with the CSRF token and shows the new state", async () => {
    const { user, requests } = renderPolicies();

    const usage = await policySection("Usage policy");
    await user.click(
      within(usage).getByRole("button", { name: "I have read this version" }),
    );

    await waitFor(() =>
      expect(usage).toHaveTextContent(
        "You acknowledged this version on Oct 11, 2026.",
      ),
    );
    expect(within(usage).queryByRole("button")).toBeNull();
    const [acknowledgement] = requestsTo(requests, "POST", ACK_PATH);
    expect(acknowledgement.headers.get("x-csrf-token")).toBe("csrf-1");
    expect(requestsTo(requests, "POST", ACK_PATH)).toHaveLength(1);
    // The acknowledgement invalidates the policies, which load again.
    await waitFor(() =>
      expect(requestsTo(requests, "GET", "/api/policies")).toHaveLength(2),
    );
    await waitFor(() =>
      expect(
        within(usage).getByText(
          "You acknowledged this version on Oct 11, 2026.",
        ),
      ).toHaveFocus(),
    );
  });

  test("a failed acknowledgement keeps the button and shows an alert", async () => {
    const { user } = renderPolicies({
      [`POST ${ACK_PATH}`]: { status: 404, body: { error: "not_found" } },
    });

    const usage = await policySection("Usage policy");
    await user.click(
      within(usage).getByRole("button", { name: "I have read this version" }),
    );

    expect(await within(usage).findByRole("alert")).toHaveTextContent(
      "The acknowledgement could not be saved. Please try again.",
    );
    expect(
      within(usage).getByRole("button", { name: "I have read this version" }),
    ).toBeEnabled();
  });

  test("the tool table scrolls inside a named group that takes the keyboard focus", async () => {
    const { user } = renderPolicies();

    await policySection("Usage policy");
    const table = await screen.findByRole("table", { name: "Approved tools" });
    const scroller = screen.getByRole("group", { name: "Approved tools" });
    expect(scroller).toHaveClass("overflow-x-auto");
    expect(scroller).toHaveAttribute("tabindex", "0");
    expect(scroller).toContainElement(table);

    // The button of the unacknowledged policy comes first, then the table.
    await user.tab();
    expect(
      screen.getByRole("button", { name: "I have read this version" }),
    ).toHaveFocus();
    await user.tab();
    expect(scroller).toHaveFocus();
  });

  test("lists the approved tools with name, vendor, status, conditions and review date", async () => {
    renderPolicies();

    const table = await screen.findByRole("table", { name: "Approved tools" });
    const rows = within(table).getAllByRole("row");
    expect(
      within(rows[0])
        .getAllByRole("columnheader")
        .map((cell) => cell.textContent),
    ).toEqual(["Tool", "Vendor", "Status", "Conditions", "Reviewed on"]);
    expect(
      within(rows[1])
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual([
      "Example Software Ltd.",
      "Approved",
      "Internal drafts without personal data.",
      "Sep 1, 2026",
    ]);
    expect(
      within(rows[1]).getByRole("rowheader", { name: "Draftwell" }),
    ).toBeInTheDocument();
    expect(
      within(rows[2])
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual(["Placeholder Labs", "Not approved", "None", "Not reviewed yet"]);
  });

  test("without a published policy, says so", async () => {
    renderPolicies({
      "GET /api/policies": { status: 200, body: { policies: [] } },
    });

    expect(
      await screen.findByText(
        "Your organization has not published a policy yet.",
      ),
    ).toBeInTheDocument();
  });

  test("has no axe violations", async () => {
    const { container } = renderPolicies();

    await policySection("Usage policy");
    await screen.findByRole("table", { name: "Approved tools" });
    await expectNoAxeViolations(container);
  });
});

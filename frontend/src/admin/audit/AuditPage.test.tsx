import { screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import type {
  AdminAuditEvent,
  AdminAuditEventList,
} from "../../api/admin/audit";
import { expectNoAxeViolations } from "../../test/axe";
import { renderWithProviders, type StubResponses } from "../../test/render";
import { signedInPayload } from "../../test/session";
import { AuditPage } from "./AuditPage";

/**
 * Task 0015 step 18: the audit page shows a table with time, actor,
 * action and subject, newest first, filters by action and actor id, and
 * pages by 50 events. Filters and page live in the URL and go into the
 * query of `GET /api/admin/audit`.
 */
const uuid = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

const ROUTE = "/admin/audit";
const ADA = uuid(1);

const event = (
  n: number,
  overrides: Partial<AdminAuditEvent> = {},
): AdminAuditEvent => ({
  id: uuid(100 + n),
  at: "2026-10-12T08:30:00Z",
  action: "user.disabled",
  actor_id: ADA,
  actor_display_name: "Ada Example",
  subject_type: "user",
  subject_id: uuid(200 + n),
  details: {},
  ...overrides,
});

const page = (
  events: AdminAuditEvent[],
  overrides: Partial<AdminAuditEventList> = {},
): AdminAuditEventList => ({ events, page: 1, per_page: 50, ...overrides });

const events = [
  event(1),
  event(2, {
    action: "role.synced",
    actor_id: null,
    actor_display_name: null,
  }),
  event(3, {
    action: "sessions.ended_all",
    actor_id: uuid(2),
    actor_display_name: null,
    subject_type: null,
    subject_id: null,
  }),
];

function renderPage(responses: StubResponses = {}, route = ROUTE) {
  return renderWithProviders(<AuditPage />, {
    route,
    path: ROUTE,
    session: signedInPayload("mfa", { roles: ["learner", "admin"] }),
    responses: {
      "GET /api/admin/audit": { status: 200, body: page(events) },
      ...responses,
    },
  });
}

/**
 * Records the URL of every request that the API client builds; the stub
 * fetch records the path only, and the filters travel in the query.
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

/** The queries of the audit requests, as objects. */
const auditQueries = (urls: string[]) =>
  urls
    .map((url) => new URL(url))
    .filter((url) => url.pathname === "/api/admin/audit")
    .map((url) => Object.fromEntries(url.searchParams));

const filters = () => screen.findByRole("region", { name: "Filters" });

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("the audit page", () => {
  test("shows time, actor, action and subject per event", async () => {
    renderPage();

    const table = await screen.findByRole("table", { name: "Events" });
    expect(
      within(table)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual(["Time", "Actor", "Action", "Subject"]);
    const rows = within(table).getAllByRole("row").slice(1);
    expect(rows).toHaveLength(3);
    expect(
      within(rows[0])
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual(["Ada Example", "user.disabled", `user ${uuid(201)}`]);
    expect(within(rows[0]).getByRole("rowheader")).toHaveTextContent("2026");
    expect(within(rows[1]).getAllByRole("cell")[0]).toHaveTextContent("System");
    expect(
      within(rows[2])
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual(["Unknown person", "sessions.ended_all", "None"]);
    expect(
      within(rows[0]).getByRole("button", {
        name: "Show only the events of Ada Example",
      }),
    ).toBeInTheDocument();
  });

  test("the action filter suggests the actions of the pack workbench", async () => {
    renderPage();
    const field = within(await filters()).getByLabelText("Action");

    const list = document.getElementById(field.getAttribute("list") ?? "");
    const actions = Array.from(
      list?.querySelectorAll("option") ?? [],
      (option) => option.value,
    );
    expect(actions).toEqual(
      expect.arrayContaining([
        "pack.imported",
        "pack.published",
        "pack_draft.created",
        "pack_draft.deleted",
      ]),
    );
  });

  test("the action filter suggests the actions of the media library", async () => {
    renderPage();
    const field = within(await filters()).getByLabelText("Action");

    const list = document.getElementById(field.getAttribute("list") ?? "");
    const actions = Array.from(
      list?.querySelectorAll("option") ?? [],
      (option) => option.value,
    );
    expect(actions).toEqual(
      expect.arrayContaining(["media.uploaded", "media.deleted"]),
    );
  });

  test("the filters send their query and live in the URL", async () => {
    const urls = recordRequestUrls();
    const { user, location } = renderPage();
    const section = await filters();
    await screen.findByRole("table", { name: "Events" });

    await user.type(within(section).getByLabelText("Action"), "user.disabled");
    await user.type(within(section).getByLabelText("Actor id"), ADA);
    await user.click(
      within(section).getByRole("button", { name: "Apply filters" }),
    );

    await waitFor(() =>
      expect(location()).toBe(
        `/admin/audit?action=user.disabled&actor_id=${ADA}`,
      ),
    );
    await waitFor(() =>
      expect(auditQueries(urls)).toEqual([
        { page: "1" },
        { action: "user.disabled", actor_id: ADA, page: "1" },
      ]),
    );
  });

  test("reads the filters of the URL into the fields and the query", async () => {
    const urls = recordRequestUrls();
    renderPage({}, `${ROUTE}?action=role.granted&page=3`);

    const section = await filters();
    expect(within(section).getByLabelText("Action")).toHaveValue(
      "role.granted",
    );
    await waitFor(() =>
      expect(auditQueries(urls)).toEqual([
        { action: "role.granted", page: "3" },
      ]),
    );
  });

  test("refuses an actor id that is no id before sending", async () => {
    const urls = recordRequestUrls();
    const { user, location } = renderPage();
    const section = await filters();
    await screen.findByRole("table", { name: "Events" });

    const field = within(section).getByLabelText("Actor id");
    await user.type(field, "Ada");
    await user.click(
      within(section).getByRole("button", { name: "Apply filters" }),
    );

    expect(field).toHaveAttribute("aria-invalid", "true");
    expect(field).toHaveAccessibleDescription(
      "The id of a person. Choose a name in the table to fill it in. Enter the id in the form 01234567-89ab-cdef-0123-456789abcdef.",
    );
    expect(location()).toBe(ROUTE);
    expect(auditQueries(urls)).toEqual([{ page: "1" }]);
  });

  test("a name in the table filters by its actor and keeps the action filter", async () => {
    const urls = recordRequestUrls();
    const { user, location } = renderPage({}, `${ROUTE}?action=user.disabled`);

    await user.click(
      await screen.findByRole("button", {
        name: "Show only the events of Ada Example",
      }),
    );

    await waitFor(() =>
      expect(location()).toBe(
        `/admin/audit?action=user.disabled&actor_id=${ADA}`,
      ),
    );
    expect(within(await filters()).getByLabelText("Actor id")).toHaveValue(ADA);
    await waitFor(() =>
      expect(auditQueries(urls).at(-1)).toEqual({
        action: "user.disabled",
        actor_id: ADA,
        page: "1",
      }),
    );
  });

  test("pages while a page is full and keeps the filters", async () => {
    const urls = recordRequestUrls();
    const full = Array.from({ length: 50 }, (_, index) => event(index + 1));
    const { user, location } = renderPage(
      {
        "GET /api/admin/audit": [
          { status: 200, body: page(full) },
          { status: 200, body: page([event(60)], { page: 2 }) },
        ],
      },
      `${ROUTE}?action=user.disabled`,
    );

    const pager = await screen.findByRole("navigation", {
      name: "Pages of the audit log",
    });
    expect(within(pager).getByText("Page 1")).toBeInTheDocument();
    await user.click(within(pager).getByRole("button", { name: "Next page" }));

    await waitFor(() =>
      expect(location()).toBe("/admin/audit?action=user.disabled&page=2"),
    );
    await waitFor(() =>
      expect(auditQueries(urls).at(-1)).toEqual({
        action: "user.disabled",
        page: "2",
      }),
    );
    const next = await screen.findByRole("navigation", {
      name: "Pages of the audit log",
    });
    await waitFor(() =>
      expect(
        within(next).getByRole("button", { name: "Next page" }),
      ).toBeDisabled(),
    );
    expect(
      within(next).getByRole("button", { name: "Previous page" }),
    ).toBeEnabled();
  });

  test("'Clear filters' empties the URL", async () => {
    const { user, location } = renderPage(
      {},
      `${ROUTE}?action=user.disabled&actor_id=${ADA}&page=2`,
    );

    await user.click(
      within(await filters()).getByRole("button", { name: "Clear filters" }),
    );

    await waitFor(() => expect(location()).toBe(ROUTE));
    expect(within(await filters()).getByLabelText("Action")).toHaveValue("");
  });

  test("states that no event matches", async () => {
    renderPage({ "GET /api/admin/audit": { status: 200, body: page([]) } });

    expect(
      await screen.findByText("No event matches the filters."),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("navigation", { name: "Pages of the audit log" }),
    ).not.toBeInTheDocument();
  });

  test("axe reports no violation", async () => {
    const { container } = renderPage();
    await screen.findByRole("table", { name: "Events" });
    await expectNoAxeViolations(container);
  });
});

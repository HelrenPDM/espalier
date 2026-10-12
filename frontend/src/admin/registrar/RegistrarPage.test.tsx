import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createMemoryRouter, Outlet, RouterProvider } from "react-router";
import { afterEach, describe, expect, test, vi } from "vitest";
import { ApiClientProvider } from "../../api/ApiClientProvider";
import type { RegistrarCredential } from "../../api/admin/registrar";
import { createApiClient } from "../../api/client";
import type { Role } from "../../api/session";
import { appRoutes, createRoutes } from "../../app/router";
import { SessionContext } from "../../auth/SessionProvider";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  stubFetch,
  type StubResponses,
} from "../../test/render";
import { sessionValue, signedInPayload } from "../../test/session";
import { RegistrarPage } from "./RegistrarPage";

/**
 * Task 0015 step 17 and the Acceptance line on the registrar: the page
 * `/admin/registrar` takes a qualification code, lists one row per
 * credential with display name, org unit, status, `issued_at` and
 * `valid_until` from `GET /api/registrar/credentials?qualification=<code>`,
 * and shows a notice when the route answers 404 while
 * `REGISTRAR_ENABLED=false`. A learner gets the 403 page, and the guard of
 * step 5 admits a registrar on `/admin` with the section Credentials.
 */
const PATH = "/api/registrar/credentials";

const credentials: RegistrarCredential[] = [
  {
    display_name: "Ada Example",
    org_unit: "Newsroom",
    status: "active",
    issued_at: "2026-09-14T08:30:00Z",
    valid_until: "2027-09-14",
  },
  // The same person holds the code in a second program.
  {
    display_name: "Ada Example",
    org_unit: "Newsroom",
    status: "refresh_due",
    issued_at: "2026-03-02T10:00:00Z",
    valid_until: null,
  },
  {
    display_name: null,
    org_unit: null,
    status: "revoked",
    issued_at: "2026-05-20T12:00:00Z",
    valid_until: "2026-11-20",
  },
];

const registrar = signedInPayload("mfa", { roles: ["learner", "registrar"] });

function renderPage(
  responses: StubResponses = {
    [`GET ${PATH}`]: { status: 200, body: { credentials } },
  },
  route = "/admin/registrar",
) {
  return renderWithProviders(<RegistrarPage />, {
    route,
    path: "/admin/registrar",
    session: registrar,
    responses,
  });
}

/** Records the URL of every request, because the stub fetch records the path only. */
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

const qualificationsOf = (urls: string[]) =>
  urls
    .map((url) => new URL(url))
    .filter((url) => url.pathname === PATH)
    .map((url) => url.searchParams.get("qualification"));

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

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("the registrar page", () => {
  test("lists one row per credential of the entered code", async () => {
    const urls = recordRequestUrls();
    const { user, location } = renderPage();

    expect(
      screen.getByRole("heading", {
        level: 1,
        name: "Credentials of a qualification",
      }),
    ).toBeInTheDocument();
    await user.type(
      screen.getByRole("textbox", { name: "Qualification code" }),
      "  basic ",
    );
    await user.click(screen.getByRole("button", { name: "Show credentials" }));

    const table = await screen.findByRole("table", {
      name: "Credentials of basic",
    });
    expect(table).toHaveAccessibleDescription("3 credentials");
    expect(
      within(table)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual(["Holder", "Org unit", "Status", "Issued on", "Valid until"]);
    expect(bodyRows(table)).toEqual([
      ["Ada Example", "Newsroom", "Active", "Sep 14, 2026", "Sep 14, 2027"],
      [
        "Ada Example",
        "Newsroom",
        "Refresher due",
        "Mar 2, 2026",
        "No expiry date",
      ],
      [
        "No display name recorded",
        "No org unit recorded",
        "Revoked",
        "May 20, 2026",
        "Nov 20, 2026",
      ],
    ]);
    // The table scrolls inside a region that takes the focus.
    expect(
      screen.getByRole("region", { name: "Credentials of basic" }),
    ).toHaveAttribute("tabindex", "0");
    expect(qualificationsOf(urls)).toEqual(["basic"]);
    expect(location()).toBe("/admin/registrar?qualification=basic");
  });

  test("reads the code of the query", async () => {
    const urls = recordRequestUrls();
    renderPage(undefined, "/admin/registrar?qualification=basic");

    expect(
      await screen.findByRole("table", { name: "Credentials of basic" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("textbox", { name: "Qualification code" }),
    ).toHaveValue("basic");
    expect(qualificationsOf(urls)).toEqual(["basic"]);
  });

  test("shows the notice when the route answers 404 while the list is turned off", async () => {
    const { user } = renderPage({
      [`GET ${PATH}`]: { status: 404, body: { error: "not_found" } },
    });

    await user.type(
      screen.getByRole("textbox", { name: "Qualification code" }),
      "basic",
    );
    await user.click(screen.getByRole("button", { name: "Show credentials" }));

    const notice = await screen.findByRole("region", {
      name: "The credential list is turned off",
    });
    expect(notice).toHaveTextContent(
      "The credential list is turned off on this instance.",
    );
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  test("checks the code format and sends no request for an invalid code", async () => {
    const { user, requests } = renderPage();

    const field = screen.getByRole("textbox", { name: "Qualification code" });
    await user.type(field, "Basic Code");
    await user.click(screen.getByRole("button", { name: "Show credentials" }));

    expect(field).toHaveAttribute("aria-invalid", "true");
    expect(field).toHaveAccessibleDescription(
      expect.stringContaining(
        "Enter the code in lower-case letters, digits and hyphens.",
      ),
    );
    expect(requestsTo(requests, "GET", PATH)).toHaveLength(0);
  });

  test("states an empty list and a failed request", async () => {
    const { user } = renderPage({
      [`GET ${PATH}`]: [
        { status: 200, body: { credentials: [] } },
        { status: 500, body: { error: "internal" } },
      ],
    });
    const field = screen.getByRole("textbox", { name: "Qualification code" });

    await user.type(field, "basic");
    await user.click(screen.getByRole("button", { name: "Show credentials" }));
    expect(
      await screen.findByText(
        "No credential of the qualification basic exists.",
      ),
    ).toBeInTheDocument();

    await user.clear(field);
    await user.type(field, "advanced");
    await user.click(screen.getByRole("button", { name: "Show credentials" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "The credentials could not be loaded. Please try again later.",
    );
  });

  test("has no axe violations with the table and with the notice", async () => {
    const { container, unmount } = renderPage(
      undefined,
      "/admin/registrar?qualification=basic",
    );
    await screen.findByRole("table", { name: "Credentials of basic" });
    await expectNoAxeViolations(container);
    unmount();

    const notice = renderPage(
      { [`GET ${PATH}`]: { status: 404, body: { error: "not_found" } } },
      "/admin/registrar?qualification=basic",
    );
    await screen.findByRole("region", {
      name: "The credential list is turned off",
    });
    await expectNoAxeViolations(notice.container);
  });
});

/** Renders the routes of the SPA at `path` for a session with `roles`. */
function renderApp(path: string, roles: Role[]) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  const { fetchImpl } = stubFetch({
    [`GET ${PATH}`]: { status: 200, body: { credentials } },
  });
  const router = createMemoryRouter(createRoutes(<Outlet />, appRoutes), {
    initialEntries: [path],
  });
  render(
    <QueryClientProvider client={queryClient}>
      <ApiClientProvider client={createApiClient(queryClient, fetchImpl)}>
        <SessionContext.Provider value={sessionValue({ roles })}>
          <RouterProvider router={router} />
        </SessionContext.Provider>
      </ApiClientProvider>
    </QueryClientProvider>,
  );
  return router;
}

describe("the route /admin/registrar", () => {
  test("renders the 403 page for a learner", () => {
    renderApp("/admin/registrar", ["learner"]);

    expect(
      screen.getByRole("heading", { level: 1, name: "Access denied" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("textbox", { name: "Qualification code" }),
    ).not.toBeInTheDocument();
  });

  test("renders the 403 page for a facilitator, whose role the section does not serve", () => {
    renderApp("/admin/registrar", ["learner", "facilitator"]);

    expect(
      screen.getByRole("heading", { level: 1, name: "Access denied" }),
    ).toBeInTheDocument();
  });

  test("the guard of /admin admits a registrar, whose navigation leads to the table", async () => {
    const router = renderApp("/admin", ["learner", "registrar"]);
    const user = userEvent.setup();

    expect(
      screen.getByRole("heading", { level: 1, name: "Administration" }),
    ).toBeInTheDocument();
    const navigation = screen.getByRole("navigation", {
      name: "Administration sections",
    });
    const link = within(navigation).getByRole("link", { name: "Credentials" });
    expect(link).toHaveAttribute("href", "/admin/registrar");

    await user.click(link);
    await user.type(
      await screen.findByRole("textbox", { name: "Qualification code" }),
      "basic",
    );
    await user.click(screen.getByRole("button", { name: "Show credentials" }));

    expect(
      await screen.findByRole("table", { name: "Credentials of basic" }),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(router.state.location.search).toBe("?qualification=basic"),
    );
  });
});

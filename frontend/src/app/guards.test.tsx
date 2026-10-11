import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import {
  createMemoryRouter,
  Outlet,
  RouterProvider,
  type RouteObject,
} from "react-router";
import { describe, expect, test, vi } from "vitest";
import {
  SessionContext,
  type SessionContextValue,
} from "../auth/SessionProvider";
import { sessionValue } from "../test/session";
import { appRoutes, createRoutes } from "./router";

function renderAt(
  path: string,
  value: SessionContextValue,
  children: RouteObject[] = appRoutes,
) {
  const router = createMemoryRouter(createRoutes(<Outlet />, children), {
    initialEntries: [path],
  });
  render(
    <QueryClientProvider client={new QueryClient()}>
      <SessionContext.Provider value={value}>
        <RouterProvider router={router} />
      </SessionContext.Provider>
    </QueryClientProvider>,
  );
  return router;
}

const location = (router: ReturnType<typeof createMemoryRouter>) =>
  router.state.location.pathname + router.state.location.search;

describe("RequireAuth", () => {
  test("shows the loading state and redirects nothing while the session loads", () => {
    const router = renderAt(
      "/programs/demo",
      sessionValue({ loading: true, user: null, sessionStrength: null }),
    );

    expect(screen.getByRole("status")).toHaveTextContent(
      "Loading the session…",
    );
    expect(location(router)).toBe("/programs/demo");
  });

  test("redirects a signed-out session to /sign-in with the encoded return_to", async () => {
    const router = renderAt(
      "/programs/demo?x=1",
      sessionValue({ user: null, sessionStrength: null, roles: [] }),
    );

    expect(
      await screen.findByRole("heading", { level: 1, name: "Sign in" }),
    ).toBeInTheDocument();
    expect(location(router)).toBe(
      "/sign-in?return_to=%2Fprograms%2Fdemo%3Fx%3D1",
    );
  });

  test.each([
    ["recovery", "Set up a new sign-in method"],
    ["enrollment", "Set up your sign-in"],
  ] as const)(
    "sends a %s session through /sign-in on to the enrollment wizard",
    async (sessionStrength, heading) => {
      const router = renderAt(
        "/me/credentials",
        sessionValue({ sessionStrength }),
      );

      expect(
        await screen.findByRole("heading", { level: 1, name: heading }),
      ).toBeInTheDocument();
      expect(location(router)).toBe("/enroll");
    },
  );

  test.each(["mfa", "demo"] as const)(
    "renders its children for an %s session",
    (sessionStrength) => {
      const router = renderAt(
        "/programs/demo",
        sessionValue({ sessionStrength }),
      );

      expect(
        screen.getByRole("heading", { level: 1, name: "Program" }),
      ).toBeInTheDocument();
      expect(location(router)).toBe("/programs/demo");
    },
  );
});

describe("RequireRole", () => {
  test("renders the 403 page for a learner on /admin", () => {
    renderAt("/admin", sessionValue({ roles: ["learner"] }));

    expect(
      screen.getByRole("heading", { level: 1, name: "Access denied" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Administration" }),
    ).not.toBeInTheDocument();
  });

  test.each([
    ["an analyst", "analyst", "/admin"],
    ["a registrar", "registrar", "/admin/registrar"],
  ] as const)("renders the admin placeholder for %s", (_name, role, path) => {
    renderAt(path, sessionValue({ roles: ["learner", role] }));

    expect(
      screen.getByRole("heading", { level: 1, name: "Administration" }),
    ).toBeInTheDocument();
  });
});

test("a route component that throws renders the error page", () => {
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
  const Thrower = () => {
    throw new Error("route failed");
  };

  renderAt("/boom", sessionValue(), [{ path: "boom", Component: Thrower }]);

  expect(
    screen.getByRole("heading", { level: 1, name: "Something went wrong" }),
  ).toBeInTheDocument();
  expect(
    screen.getByRole("link", { name: "Back to the start page" }),
  ).toHaveAttribute("href", "/");
  expect(screen.queryByText("route failed")).not.toBeInTheDocument();
  consoleError.mockRestore();
});

test("an unknown path renders the not-found page without a session", () => {
  renderAt(
    "/no/such/page",
    sessionValue({ user: null, sessionStrength: null }),
  );

  expect(
    screen.getByRole("heading", { level: 1, name: "Page not found" }),
  ).toBeInTheDocument();
});

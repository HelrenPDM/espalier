import type { ReactNode } from "react";
import { createBrowserRouter, Outlet, type RouteObject } from "react-router";
import type { Role } from "../api/session";
import { RequireAuth } from "../auth/RequireAuth";
import { RequireRole } from "../auth/RequireRole";
import { SessionProvider } from "../auth/SessionProvider";
import { ErrorPage } from "./ErrorPage";
import { Layout } from "./Layout";
import { NotFoundPage } from "./NotFoundPage";
import { PlaceholderPage } from "./PlaceholderPage";

/** The roles that the admin navigation of 0015 serves (README section 9). */
export const ADMIN_ROLES: readonly Role[] = [
  "author",
  "admin",
  "facilitator",
  "analyst",
  "registrar",
];

/** Every route except `/sign-in` and the not-found page sits under `RequireAuth`. */
export const appRoutes: RouteObject[] = [
  { path: "sign-in", element: <PlaceholderPage page="signIn" /> },
  {
    element: (
      <RequireAuth>
        <Outlet />
      </RequireAuth>
    ),
    children: [
      { index: true, element: <PlaceholderPage page="home" /> },
      { path: "programs/:slug", element: <PlaceholderPage page="program" /> },
      {
        path: "programs/:slug/stations/:position",
        element: <PlaceholderPage page="station" />,
      },
      {
        path: "me/credentials",
        element: <PlaceholderPage page="credentials" />,
      },
      {
        path: "me/credentials/:id",
        element: <PlaceholderPage page="credential" />,
      },
      {
        path: "admin/*",
        element: (
          <RequireRole anyOf={ADMIN_ROLES}>
            <PlaceholderPage page="admin" />
          </RequireRole>
        ),
      },
    ],
  },
  { path: "*", element: <NotFoundPage /> },
];

/**
 * The route tree below `root`. The root route catches an error of `root`
 * itself; the pathless route below it catches the errors of every page, so
 * the error page keeps the layout.
 */
export function createRoutes(
  root: ReactNode,
  children: RouteObject[] = appRoutes,
): RouteObject[] {
  return [
    {
      path: "/",
      element: root,
      errorElement: <ErrorPage standalone />,
      children: [{ errorElement: <ErrorPage />, children }],
    },
  ];
}

export function createAppRouter() {
  return createBrowserRouter(
    createRoutes(
      <SessionProvider>
        <Layout />
      </SessionProvider>,
    ),
  );
}

import type { ReactNode } from "react";
import { createBrowserRouter, Outlet, type RouteObject } from "react-router";
import { EmailConfirmPage } from "../account/EmailConfirmPage";
import { SecurityPage } from "../account/SecurityPage";
import { StepUpProvider } from "../account/StepUpProvider";
import type { Role } from "../api/session";
import { EnrollmentWizard } from "../auth/EnrollmentWizard";
import { FinishPage } from "../auth/FinishPage";
import { InvitationPage } from "../auth/InvitationPage";
import { RecoveryPage } from "../auth/RecoveryPage";
import { RequireAuth } from "../auth/RequireAuth";
import { RequireRole } from "../auth/RequireRole";
import { SessionProvider } from "../auth/SessionProvider";
import { SignedOutPage } from "../auth/SignedOutPage";
import { SignInPage } from "../auth/SignInPage";
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

/**
 * The account routes of 0011 that serve sessions before a full sign-in sit
 * outside `RequireAuth`: sign-in, the OIDC finish step, invitation,
 * enrollment, recovery, the e-mail confirmation link and the post-logout
 * page. Every other route sits under `RequireAuth`.
 */
export const appRoutes: RouteObject[] = [
  { path: "sign-in", element: <SignInPage /> },
  { path: "auth/finish", element: <FinishPage /> },
  { path: "invite", element: <InvitationPage /> },
  { path: "enroll", element: <EnrollmentWizard /> },
  { path: "recover", element: <RecoveryPage /> },
  { path: "account/email/confirm", element: <EmailConfirmPage /> },
  { path: "signed-out", element: <SignedOutPage /> },
  {
    element: (
      <RequireAuth>
        <Outlet />
      </RequireAuth>
    ),
    children: [
      { index: true, element: <PlaceholderPage page="home" /> },
      { path: "account/security", element: <SecurityPage /> },
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
        <StepUpProvider>
          <Layout />
        </StepUpProvider>
      </SessionProvider>,
    ),
  );
}

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
import { CredentialListPage } from "../learner/CredentialListPage";
import { CredentialPage } from "../learner/CredentialPage";
import { ProgramListPage } from "../learner/ProgramListPage";
import { ErrorPage } from "./ErrorPage";
import { Layout } from "./Layout";
import {
  GlossaryPage,
  HandbookPage,
  PoliciesPage,
  ProgramPage,
  ProgramRoute,
  StationPage,
} from "./lazyPages";
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
      { index: true, element: <ProgramListPage /> },
      { path: "account/security", element: <SecurityPage /> },
      {
        path: "programs/:slug",
        element: <ProgramRoute />,
        children: [
          { index: true, element: <ProgramPage /> },
          { path: "stations/:position", element: <StationPage /> },
          { path: "glossary", element: <GlossaryPage /> },
          { path: "handbook", element: <HandbookPage /> },
        ],
      },
      { path: "policies", element: <PoliciesPage /> },
      { path: "me/credentials", element: <CredentialListPage /> },
      { path: "me/credentials/:id", element: <CredentialPage /> },
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

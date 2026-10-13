import type { ReactNode } from "react";
import { createBrowserRouter, Outlet, type RouteObject } from "react-router";
import { EmailConfirmPage } from "../account/EmailConfirmPage";
import { SecurityPage } from "../account/SecurityPage";
import { StepUpProvider } from "../account/StepUpProvider";
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
import { AdminHome } from "../admin/AdminHome";
import { AdminLayout } from "../admin/AdminLayout";
import { AdminPasskeyGate } from "../admin/passkeyGate";
import { ADMIN_ROLES } from "../admin/sections";
import {
  AdminPoliciesPage,
  ApiClientsPage,
  ApprovedToolsPage,
  AttendancePage,
  AuditPage,
  ExportsPage,
  GlossaryPage,
  HandbookPage,
  InsightsPage,
  PackPage,
  PackPreviewPage,
  PacksPage,
  PoliciesPage,
  ProgramPage,
  ProgramRoute,
  RegistrarPage,
  RolesPage,
  StationPage,
  UsersPage,
  WebhooksPage,
} from "./lazyPages";
import { NotFoundPage } from "./NotFoundPage";

/** A section of the role `admin` behind its guard and the passkey gate. */
function adminSection(path: string, page: ReactNode): RouteObject {
  return {
    path,
    element: (
      <RequireRole anyOf={["admin"]}>
        <AdminPasskeyGate>{page}</AdminPasskeyGate>
      </RequireRole>
    ),
  };
}

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
        // The guard of the admin area admits every role beyond `learner`;
        // each section below it checks its own role, and the admin sections
        // also show the passkey notice while the passkey gate is closed
        // (task 0015, step 5). The server checks every role (ASVS 8.3.1).
        path: "admin",
        element: (
          <RequireRole anyOf={ADMIN_ROLES}>
            <AdminLayout />
          </RequireRole>
        ),
        children: [
          { index: true, element: <AdminHome /> },
          {
            path: "packs",
            element: (
              <RequireRole anyOf={["author"]}>
                <Outlet />
              </RequireRole>
            ),
            children: [
              { index: true, element: <PacksPage /> },
              { path: ":id", element: <PackPage /> },
              { path: ":id/preview/*", element: <PackPreviewPage /> },
            ],
          },
          {
            path: "exports",
            element: (
              <RequireRole anyOf={["author"]}>
                <ExportsPage />
              </RequireRole>
            ),
          },
          adminSection("users", <UsersPage />),
          adminSection("policies", <AdminPoliciesPage />),
          adminSection("approved-tools", <ApprovedToolsPage />),
          adminSection("roles", <RolesPage />),
          adminSection("api-clients", <ApiClientsPage />),
          adminSection("webhooks", <WebhooksPage />),
          adminSection("audit", <AuditPage />),
          {
            path: "attendance",
            element: (
              <RequireRole anyOf={["facilitator"]}>
                <AttendancePage />
              </RequireRole>
            ),
          },
          {
            path: "insights",
            element: (
              <RequireRole anyOf={["analyst"]}>
                <InsightsPage />
              </RequireRole>
            ),
          },
          {
            path: "registrar",
            element: (
              <RequireRole anyOf={["registrar"]}>
                <RegistrarPage />
              </RequireRole>
            ),
          },
          { path: "*", element: <NotFoundPage /> },
        ],
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

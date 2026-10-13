import { lazy, Suspense, type ReactNode } from "react";
import { LoadingStatus } from "./LoadingStatus";

// The pages of a program and the policies page load with the player and the
// Markdown renderer in chunks of their own, so the sign-in pages stay small.
const ProgramRouteChunk = lazy(() =>
  import("../learner/ProgramRoute").then((m) => ({ default: m.ProgramRoute })),
);
const ProgramPageChunk = lazy(() =>
  import("../learner/ProgramPage").then((m) => ({ default: m.ProgramPage })),
);
const StationPageChunk = lazy(() =>
  import("../learner/StationPage").then((m) => ({ default: m.StationPage })),
);
const GlossaryPageChunk = lazy(() =>
  import("../learner/GlossaryPage").then((m) => ({ default: m.GlossaryPage })),
);
const HandbookPageChunk = lazy(() =>
  import("../learner/HandbookPage").then((m) => ({ default: m.HandbookPage })),
);
const PoliciesPageChunk = lazy(() =>
  import("../learner/PoliciesPage").then((m) => ({ default: m.PoliciesPage })),
);
// The reports page of the analysts (0014) loads in a chunk of its own, so
// learners never load it.
const InsightsPageChunk = lazy(() =>
  import("../admin/insights/InsightsPage").then((m) => ({
    default: m.InsightsPage,
  })),
);

// The pages of the admin area (task 0015) load in chunks of their own, so
// learners never load them.
const PacksPageChunk = lazy(() =>
  import("../admin/packs/PacksPage").then((m) => ({ default: m.PacksPage })),
);
const PackPageChunk = lazy(() =>
  import("../admin/packs/PackPage").then((m) => ({ default: m.PackPage })),
);
const PackPreviewPageChunk = lazy(() =>
  import("../admin/packs/PackPreviewPage").then((m) => ({
    default: m.PackPreviewPage,
  })),
);
// The pages of the pack workbench (task 0016a): the draft page loads the
// editor, so the editor reaches only the authors who open a draft.
const WorkbenchPageChunk = lazy(() =>
  import("../admin/workbench/WorkbenchPage").then((m) => ({
    default: m.WorkbenchPage,
  })),
);
const DraftPageChunk = lazy(() =>
  import("../admin/workbench/DraftPage").then((m) => ({
    default: m.DraftPage,
  })),
);
const ExportsPageChunk = lazy(() =>
  import("../admin/ExportsPage").then((m) => ({ default: m.ExportsPage })),
);
const UsersPageChunk = lazy(() =>
  import("../admin/users/UsersPage").then((m) => ({ default: m.UsersPage })),
);
const AdminPoliciesPageChunk = lazy(() =>
  import("../admin/policies/AdminPoliciesPage").then((m) => ({
    default: m.AdminPoliciesPage,
  })),
);
const ApprovedToolsPageChunk = lazy(() =>
  import("../admin/tools/ApprovedToolsPage").then((m) => ({
    default: m.ApprovedToolsPage,
  })),
);
const RolesPageChunk = lazy(() =>
  import("../admin/roles/RolesPage").then((m) => ({ default: m.RolesPage })),
);
const ApiClientsPageChunk = lazy(() =>
  import("../admin/apiClients/ApiClientsPage").then((m) => ({
    default: m.ApiClientsPage,
  })),
);
const WebhooksPageChunk = lazy(() =>
  import("../admin/webhooks/WebhooksPage").then((m) => ({
    default: m.WebhooksPage,
  })),
);
const AuditPageChunk = lazy(() =>
  import("../admin/audit/AuditPage").then((m) => ({ default: m.AuditPage })),
);
const AttendancePageChunk = lazy(() =>
  import("../admin/attendance/AttendancePage").then((m) => ({
    default: m.AttendancePage,
  })),
);
const RegistrarPageChunk = lazy(() =>
  import("../admin/registrar/RegistrarPage").then((m) => ({
    default: m.RegistrarPage,
  })),
);

function Chunk({ children }: { children: ReactNode }) {
  return <Suspense fallback={<LoadingStatus />}>{children}</Suspense>;
}

export function ProgramRoute() {
  return (
    <Chunk>
      <ProgramRouteChunk />
    </Chunk>
  );
}

export function ProgramPage() {
  return (
    <Chunk>
      <ProgramPageChunk />
    </Chunk>
  );
}

export function StationPage() {
  return (
    <Chunk>
      <StationPageChunk />
    </Chunk>
  );
}

export function GlossaryPage() {
  return (
    <Chunk>
      <GlossaryPageChunk />
    </Chunk>
  );
}

export function HandbookPage() {
  return (
    <Chunk>
      <HandbookPageChunk />
    </Chunk>
  );
}

export function PoliciesPage() {
  return (
    <Chunk>
      <PoliciesPageChunk />
    </Chunk>
  );
}

export function InsightsPage() {
  return (
    <Chunk>
      <InsightsPageChunk />
    </Chunk>
  );
}

export function PacksPage() {
  return (
    <Chunk>
      <PacksPageChunk />
    </Chunk>
  );
}

export function PackPage() {
  return (
    <Chunk>
      <PackPageChunk />
    </Chunk>
  );
}

export function PackPreviewPage() {
  return (
    <Chunk>
      <PackPreviewPageChunk />
    </Chunk>
  );
}

export function WorkbenchPage() {
  return (
    <Chunk>
      <WorkbenchPageChunk />
    </Chunk>
  );
}

export function DraftPage() {
  return (
    <Chunk>
      <DraftPageChunk />
    </Chunk>
  );
}

export function ExportsPage() {
  return (
    <Chunk>
      <ExportsPageChunk />
    </Chunk>
  );
}

export function UsersPage() {
  return (
    <Chunk>
      <UsersPageChunk />
    </Chunk>
  );
}

export function AdminPoliciesPage() {
  return (
    <Chunk>
      <AdminPoliciesPageChunk />
    </Chunk>
  );
}

export function ApprovedToolsPage() {
  return (
    <Chunk>
      <ApprovedToolsPageChunk />
    </Chunk>
  );
}

export function RolesPage() {
  return (
    <Chunk>
      <RolesPageChunk />
    </Chunk>
  );
}

export function ApiClientsPage() {
  return (
    <Chunk>
      <ApiClientsPageChunk />
    </Chunk>
  );
}

export function WebhooksPage() {
  return (
    <Chunk>
      <WebhooksPageChunk />
    </Chunk>
  );
}

export function AuditPage() {
  return (
    <Chunk>
      <AuditPageChunk />
    </Chunk>
  );
}

export function AttendancePage() {
  return (
    <Chunk>
      <AttendancePageChunk />
    </Chunk>
  );
}

export function RegistrarPage() {
  return (
    <Chunk>
      <RegistrarPageChunk />
    </Chunk>
  );
}

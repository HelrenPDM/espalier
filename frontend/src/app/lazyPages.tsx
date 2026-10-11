import { lazy, Suspense, type ReactNode } from "react";
import { LoadingStatus } from "./LoadingStatus";

// The pages of a program load with the player and the Markdown renderer in
// chunks of their own, so the sign-in pages stay small.
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

import { useState } from "react";
import { Outlet, useParams } from "react-router";
import { useApiClient } from "../api/apiClientContext";
import { PlayerProvider } from "../player/PlayerProvider";
import { RuntimeContext } from "../player/RuntimeContext";
import { PlatformRuntime } from "../runtimes/platform";
import { TestNotesProvider } from "./test-notes/TestNotesProvider";

function ProgramRuntime({ slug }: { slug: string }) {
  const client = useApiClient();
  const [runtime] = useState(() => new PlatformRuntime(slug, { client }));
  return (
    <TestNotesProvider>
      <RuntimeContext.Provider value={runtime}>
        <PlayerProvider slug={slug}>
          <Outlet />
        </PlayerProvider>
      </RuntimeContext.Provider>
    </TestNotesProvider>
  );
}

/**
 * The parent route of `/programs/:slug`, its stations, its glossary and its
 * handbook. It creates one `PlatformRuntime` per slug and provides it
 * through `RuntimeContext`, so the four pages share one player. With
 * `TEST_NOTES=true`, the pages record the test session notes, and the
 * "Test notes" panel follows them (task 0014, step 11).
 */
export function ProgramRoute() {
  const { slug = "" } = useParams();
  return <ProgramRuntime key={slug} slug={slug} />;
}

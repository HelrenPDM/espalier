import { useState } from "react";
import { Outlet, useParams } from "react-router";
import { useApiClient } from "../api/apiClientContext";
import { PlayerProvider } from "../player/PlayerProvider";
import { RuntimeContext } from "../player/RuntimeContext";
import { PlatformRuntime } from "../runtimes/platform";

function ProgramRuntime({ slug }: { slug: string }) {
  const client = useApiClient();
  const [runtime] = useState(() => new PlatformRuntime(slug, { client }));
  return (
    <RuntimeContext.Provider value={runtime}>
      <PlayerProvider slug={slug}>
        <Outlet />
      </PlayerProvider>
    </RuntimeContext.Provider>
  );
}

/**
 * The parent route of `/programs/:slug`, its stations, its glossary and its
 * handbook. It creates one `PlatformRuntime` per slug and provides it
 * through `RuntimeContext`, so the four pages share one player.
 */
export function ProgramRoute() {
  const { slug = "" } = useParams();
  return <ProgramRuntime key={slug} slug={slug} />;
}

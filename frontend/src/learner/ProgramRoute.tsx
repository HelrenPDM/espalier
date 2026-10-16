import { useState } from "react";
import { useParams } from "react-router";
import { useApiClient } from "../api/apiClientContext";
import { useSession } from "../auth/SessionProvider";
import { EmbedConsentContext } from "../player/embedConsent";
import { PlayerProvider } from "../player/PlayerProvider";
import { RuntimeContext } from "../player/RuntimeContext";
import { PlatformRuntime } from "../runtimes/platform";
import { ProgramShell } from "./ProgramShell";
import { TestNotesProvider } from "./test-notes/TestNotesProvider";

function ProgramRuntime({ slug }: { slug: string }) {
  const client = useApiClient();
  const { flags } = useSession();
  const [runtime] = useState(() => new PlatformRuntime(slug, { client }));
  return (
    <TestNotesProvider>
      <EmbedConsentContext.Provider value={flags.mediaEmbedConsent}>
        <RuntimeContext.Provider value={runtime}>
          <PlayerProvider slug={slug}>
            <ProgramShell />
          </PlayerProvider>
        </RuntimeContext.Provider>
      </EmbedConsentContext.Provider>
    </TestNotesProvider>
  );
}

/**
 * The parent route of `/programs/:slug`, its stations, its glossary and its
 * handbook. It creates one `PlatformRuntime` per slug and provides it
 * through `RuntimeContext`, so the four pages share one player, and renders
 * them inside `ProgramShell` with the breadcrumbs and the program
 * navigation. With `TEST_NOTES=true`, the pages record the test session
 * notes, and the "Test notes" panel follows them (task 0014, step 11).
 * An embed player in a lesson loads after the consent that
 * `MEDIA_EMBED_CONSENT` asks for (`session.flags.mediaEmbedConsent`, task
 * 0018).
 */
export function ProgramRoute() {
  const { slug = "" } = useParams();
  return <ProgramRuntime key={slug} slug={slug} />;
}

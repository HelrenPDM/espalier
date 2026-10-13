import { useEffect, useRef, useState, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import {
  createMemoryRouter,
  Navigate,
  Outlet,
  useLocation,
  useParams,
} from "react-router";
import { RouterProvider } from "react-router/dom";
import { LoadingStatus } from "../app/LoadingStatus";
import { BackToProgram } from "../learner/BackToProgram";
import { GlossaryPage } from "../learner/GlossaryPage";
import { ModuleStation } from "../learner/ModuleStation";
import { useContentLang } from "../player/contentLang";
import { ExternalLinkTargetContext } from "../player/externalLinks";
import { PlayerProvider } from "../player/PlayerProvider";
import { RuntimeContext } from "../player/RuntimeContext";
import type { Runtime } from "../player/runtime";
import { useCurrentPlayer } from "../player/usePlayer";
import type { ScormContent } from "../runtimes/content";

/** The page frame of the package: one `<main>` without header or navigation. */
export function ScormFrame({ children }: { children: ReactNode }) {
  return <main className="mx-auto w-full max-w-3xl px-4 py-8">{children}</main>;
}

/** The status line while the package loads `content.json`. */
export function ScormLoading() {
  const { t } = useTranslation();
  return (
    <ScormFrame>
      <LoadingStatus text={t("scorm.loading")} />
    </ScormFrame>
  );
}

/** Why the package shows a notice in place of the player. */
export type ScormNoticeReason =
  "noLms" | "contentFailed" | "startFailed" | "sessionEnded";

/**
 * The notice in place of the player: no LMS API in reach (`noLms`), a
 * missing or invalid `content.json` (`contentFailed`), a runtime whose
 * start failed (`startFailed`) or a page that the browser restored from
 * the back/forward cache after the runtime ended the LMS session
 * (`sessionEnded`). The page then renders nothing else.
 */
export function ScormNotice({ reason }: { reason: ScormNoticeReason }) {
  const { t } = useTranslation();
  return (
    <ScormFrame>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t(`scorm.${reason}.title`)}
      </h1>
      <p role="alert" className="mt-4 text-gray-700 dark:text-gray-300">
        {t(`scorm.${reason}.text`)}
      </p>
    </ScormFrame>
  );
}

/** The program route: one player for the station and the glossary. */
function ScormProgram({ runtime, slug }: { runtime: Runtime; slug: string }) {
  return (
    <RuntimeContext.Provider value={runtime}>
      <PlayerProvider slug={slug}>
        <Outlet />
      </PlayerProvider>
    </RuntimeContext.Provider>
  );
}

/**
 * `/programs/:slug/stations/:position`: the module title as the page
 * heading and the module station of 0012. A navigation inside the package,
 * such as the way back from the glossary, moves focus to the heading; the
 * first entry of the memory router (key `default`) leaves focus where the
 * LMS put it.
 */
function ScormStation() {
  const { t } = useTranslation();
  const { position } = useParams();
  const { key } = useLocation();
  const { program } = useCurrentPlayer();
  const lang = useContentLang();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const station = program.stations.find(
    (entry) => entry.kind === "module" && String(entry.position) === position,
  );

  useEffect(() => {
    if (key !== "default") headingRef.current?.focus();
  }, [key]);

  if (station === undefined)
    return (
      <section>
        <h1 className="text-2xl font-semibold tracking-tight">
          {t("station.notFound.title")}
        </h1>
        <p className="mt-4">
          <BackToProgram />
        </p>
      </section>
    );

  // `contentPayload` gives the module station the title of the module.
  return (
    <>
      <h1
        ref={headingRef}
        tabIndex={-1}
        lang={lang}
        className="text-2xl font-semibold tracking-tight focus:outline-none"
      >
        {station.title}
      </h1>
      <div className="mt-6">
        <ModuleStation station={station} />
      </div>
    </>
  );
}

/**
 * The player of the package on `runtime`, which the caller has started. A
 * memory router serves the module station at
 * `/programs/<slug>/stations/1` (its initial entry) and the glossary at
 * `/programs/<slug>/glossary`, the target of the glossary terms, so the
 * player never changes the URL of the LMS window. `/programs/<slug>`, the
 * target of the link back from the glossary, redirects to the station. A
 * link that leaves the page, a source link or a link of Markdown text,
 * opens in a new tab (`ExternalLinkTargetContext`), because a navigation
 * of the SCO document ends the LMS session.
 */
export function ScormPlayer({
  content,
  runtime,
}: {
  content: ScormContent;
  runtime: Runtime;
}) {
  const [router] = useState(() => {
    const slug = content.program.slug;
    return createMemoryRouter(
      [
        {
          path: "/programs/:slug",
          element: <ScormProgram runtime={runtime} slug={slug} />,
          children: [
            { index: true, element: <Navigate to="stations/1" replace /> },
            { path: "stations/:position", element: <ScormStation /> },
            { path: "glossary", element: <GlossaryPage /> },
          ],
        },
      ],
      { initialEntries: [`/programs/${encodeURIComponent(slug)}/stations/1`] },
    );
  });

  return (
    <ScormFrame>
      <ExternalLinkTargetContext.Provider value="_blank">
        <RouterProvider router={router} />
      </ExternalLinkTargetContext.Provider>
    </ScormFrame>
  );
}

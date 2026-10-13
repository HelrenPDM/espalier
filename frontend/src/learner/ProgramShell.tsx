import {
  Disclosure,
  DisclosureButton,
  DisclosurePanel,
} from "@headlessui/react";
import { ChevronDownIcon } from "@heroicons/react/20/solid";
import { useId, type MouseEvent } from "react";
import { useTranslation } from "react-i18next";
import { Link, Outlet, useMatch } from "react-router";
import { Breadcrumbs, type BreadcrumbItem } from "../app/Breadcrumbs";
import { buttonClasses, FOCUS_RING } from "../app/formStyles";
import { useContentLang } from "../player/contentLang";
import { sortedStations } from "../player/program";
import { useProgramBase } from "../player/programBase";
import { useCurrentPlayer } from "../player/usePlayer";
import { ProgramChromeContext } from "./programChrome";
import { StationList } from "./StationList";

/** The page of a program that the current path shows. */
type ProgramPlace =
  | { kind: "overview" }
  | { kind: "station"; position: string }
  | { kind: "glossary" }
  | { kind: "handbook" };

/** The place of `rest`, the path below `/programs/:slug`. */
function placeOf(rest: string): ProgramPlace {
  const path = rest.replace(/\/+$/, "");
  if (path === "glossary") return { kind: "glossary" };
  if (path === "handbook") return { kind: "handbook" };
  const station = /^stations\/([^/]+)$/.exec(path);
  if (station !== null) return { kind: "station", position: station[1] };
  return { kind: "overview" };
}

const ENTRY_CLASSES = `block rounded-md px-2 py-1.5 text-sm text-gray-800 hover:bg-gray-100 aria-[current=page]:bg-gray-100 aria-[current=page]:font-semibold aria-[current=page]:text-gray-900 dark:text-gray-200 dark:hover:bg-gray-800 dark:aria-[current=page]:bg-gray-800 dark:aria-[current=page]:text-gray-100 ${FOCUS_RING}`;

/**
 * The program navigation: the program overview, the step list with the
 * visited stations and the current one, the glossary and the handbook.
 * From the `lg` breakpoint up it stands left of the page; below it a
 * "Program menu" button above the page opens it, and it closes again after
 * a navigation and on Escape.
 */
function ProgramMenu({
  place,
  station,
}: {
  place: ProgramPlace;
  /** The position of the current station, if the page shows one. */
  station: number | null;
}) {
  const { t } = useTranslation();
  const programBase = useProgramBase();
  const { program, state } = useCurrentPlayer();
  const lang = useContentLang();
  const stationsId = useId();
  const base = `${programBase}/${program.slug}`;
  const current = (kind: ProgramPlace["kind"]) =>
    place.kind === kind ? ("page" as const) : undefined;

  return (
    <Disclosure as="div" className="no-print min-w-0">
      {({ open, close }) => (
        <div
          onKeyDown={(event) => {
            if (event.key === "Escape" && open) {
              event.stopPropagation();
              close();
            }
          }}
          onClick={(event: MouseEvent<HTMLDivElement>) => {
            // A link of the open panel closes it; the page changes below it.
            if (
              open &&
              event.target instanceof Element &&
              event.target.closest("a") !== null
            )
              close();
          }}
        >
          <DisclosureButton
            className={`inline-flex items-center gap-1 lg:hidden ${buttonClasses("secondary")}`}
          >
            <ChevronDownIcon
              aria-hidden="true"
              className={`size-5 transition-transform ${open ? "rotate-180" : ""}`}
            />
            {t("program.menu")}
          </DisclosureButton>
          <DisclosurePanel
            static
            className={`${open ? "mt-3" : "hidden"} lg:mt-0 lg:block`}
          >
            <nav aria-label={t("program.navLabel")}>
              <p
                lang={lang}
                className="px-2 text-sm font-semibold break-words text-gray-900 dark:text-gray-100"
              >
                {program.title}
              </p>
              <ul className="mt-2 space-y-1">
                <li>
                  <Link
                    to={base}
                    aria-current={current("overview")}
                    className={ENTRY_CLASSES}
                  >
                    {t("program.overview")}
                  </Link>
                </li>
              </ul>
              <p
                id={stationsId}
                className="mt-4 px-2 text-xs font-semibold tracking-wide text-gray-700 uppercase dark:text-gray-300"
              >
                {t("program.stations")}
              </p>
              <div className="mt-1">
                <StationList
                  program={program}
                  state={state}
                  current={station}
                  labelledBy={stationsId}
                />
              </div>
              <ul className="mt-4 space-y-1">
                <li>
                  <Link
                    to={`${base}/glossary`}
                    aria-current={current("glossary")}
                    className={ENTRY_CLASSES}
                  >
                    {t("glossary.title")}
                  </Link>
                </li>
                <li>
                  <Link
                    to={`${base}/handbook`}
                    aria-current={current("handbook")}
                    className={ENTRY_CLASSES}
                  >
                    {t("handbook.title")}
                  </Link>
                </li>
              </ul>
            </nav>
          </DisclosurePanel>
        </div>
      )}
    </Disclosure>
  );
}

/**
 * The frame of the platform routes of a program (`/programs/:slug`, its
 * stations, its glossary and its handbook): the breadcrumbs from the
 * program list to the current page above, the program navigation beside
 * the page, and `ProgramChromeContext`, so that the pages leave out their
 * own step list and back link. Program and station titles are pack text
 * and carry the language of the program. The admin preview and the SCORM
 * package render the pages without this frame.
 */
export function ProgramShell() {
  const { t } = useTranslation();
  const programBase = useProgramBase();
  const { program } = useCurrentPlayer();
  const lang = useContentLang();
  const match = useMatch(`${programBase}/:slug/*`);
  const place = placeOf(match?.params["*"] ?? "");
  const base = `${programBase}/${program.slug}`;
  const station =
    place.kind === "station"
      ? sortedStations(program).find(
          (entry) => String(entry.position) === place.position,
        )
      : undefined;

  const trail: BreadcrumbItem[] = [
    { label: t("programs.title"), to: "/" },
    { label: program.title, to: base, lang },
  ];
  if (place.kind === "station")
    trail.push(
      station === undefined
        ? { label: t("station.notFound.title") }
        : { label: station.title, lang },
    );
  else if (place.kind === "glossary")
    trail.push({ label: t("glossary.title") });
  else if (place.kind === "handbook")
    trail.push({ label: t("handbook.title") });

  return (
    <div className="space-y-6">
      <Breadcrumbs items={trail} />
      <div className="grid gap-6 lg:grid-cols-[16rem_minmax(0,1fr)] lg:gap-8 print:block">
        <ProgramMenu place={place} station={station?.position ?? null} />
        <div className="min-w-0">
          <ProgramChromeContext.Provider value={true}>
            <Outlet />
          </ProgramChromeContext.Provider>
        </div>
      </div>
    </div>
  );
}

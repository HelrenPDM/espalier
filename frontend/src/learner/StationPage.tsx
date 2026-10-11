import { useEffect, useRef } from "react";
import { useTranslation } from "react-i18next";
import { Link, useLocation, useParams } from "react-router";
import { buttonClasses } from "../app/formStyles";
import { jumpTo } from "../player/jump";
import { useContentLang } from "../player/contentLang";
import { sortedStations } from "../player/program";
import { useCurrentPlayer } from "../player/usePlayer";
import { STATION_COMPONENTS } from "./stations";
import { BackToProgram } from "./BackToProgram";
import { StationList } from "./StationList";

/**
 * `/programs/:slug/stations/:position`: the station by its kind, the
 * position ("3 of 7"), the step list and the previous and next buttons.
 * Opening a station adds its position to `visitedStations`, and a station
 * change moves focus to the station heading, or to the element of the URL
 * fragment when a link names one.
 */
export function StationPage() {
  const { t } = useTranslation();
  const { position } = useParams();
  const { hash } = useLocation();
  const { program, state, update } = useCurrentPlayer();
  const lang = useContentLang();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const stations = sortedStations(program);
  const index = stations.findIndex(
    (station) => String(station.position) === position,
  );
  const station = index === -1 ? undefined : stations[index];
  const stationPosition = station?.position;
  // The fragment at the time of a station change, read by the effect below.
  const hashRef = useRef(hash);
  useEffect(() => {
    hashRef.current = hash;
  }, [hash]);

  useEffect(() => {
    if (stationPosition === undefined) return;
    update((current) =>
      current.visitedStations.includes(stationPosition)
        ? current
        : {
            ...current,
            visitedStations: [...current.visitedStations, stationPosition],
          },
    );
    // Only a station change moves focus; the fragment of the URL is read
    // with it.
    let target = "";
    try {
      target = decodeURIComponent(hashRef.current.slice(1));
    } catch {
      // A malformed fragment names no element.
    }
    if (target !== "" && document.getElementById(target)) jumpTo(target);
    else headingRef.current?.focus();
  }, [stationPosition, update]);

  if (station === undefined)
    return (
      <section className="max-w-2xl">
        <h1 className="text-2xl font-semibold tracking-tight">
          {t("station.notFound.title")}
        </h1>
        <p className="mt-4">
          <BackToProgram />
        </p>
      </section>
    );

  const Component = STATION_COMPONENTS[station.kind];
  const previous = stations[index - 1];
  const next = stations[index + 1];

  return (
    <div className="grid gap-8 lg:grid-cols-[16rem_minmax(0,1fr)]">
      <div className="min-w-0 lg:col-start-2">
        <p className="no-print text-sm">
          <BackToProgram />
        </p>
        <p className="mt-4 text-sm text-gray-700 dark:text-gray-300">
          {t("station.position", {
            position: index + 1,
            total: stations.length,
          })}
        </p>
        <h1
          ref={headingRef}
          tabIndex={-1}
          lang={lang}
          className="mt-1 text-2xl font-semibold tracking-tight focus:outline-none"
        >
          {station.title}
        </h1>
        <div className="mt-6">
          <Component key={station.position} station={station} />
        </div>
        <nav
          aria-label={t("station.pagerLabel")}
          className="no-print mt-10 flex flex-wrap justify-between gap-2"
        >
          {previous ? (
            <Link
              to={`/programs/${program.slug}/stations/${previous.position}`}
              className={buttonClasses("secondary")}
            >
              {t("station.previous")} <span lang={lang}>{previous.title}</span>
            </Link>
          ) : (
            <span />
          )}
          {next && (
            <Link
              to={`/programs/${program.slug}/stations/${next.position}`}
              className={buttonClasses("primary")}
            >
              {t("station.next")} <span lang={lang}>{next.title}</span>
            </Link>
          )}
        </nav>
      </div>
      <aside className="no-print min-w-0 lg:col-start-1 lg:row-start-1">
        <StationList
          program={program}
          state={state}
          current={station.position}
        />
      </aside>
    </div>
  );
}

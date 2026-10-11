import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { buttonClasses, linkClasses } from "../app/formStyles";
import { PathSwitch } from "../player/PathSwitch";
import { sortedStations } from "../player/program";
import { useCurrentPlayer } from "../player/usePlayer";
import { StationList } from "./StationList";

/**
 * `/programs/:slug`: the program title, the path switch, the step list and
 * the links to the glossary and the handbook.
 */
export function ProgramPage() {
  const { t } = useTranslation();
  const { program, state } = useCurrentPlayer();
  const stations = sortedStations(program);
  const next =
    stations.find(
      (station) => !state.visitedStations.includes(station.position),
    ) ?? stations[0];

  return (
    <div className="max-w-3xl space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">
          {program.title}
        </h1>
        {next && (
          <p className="mt-4">
            <Link
              to={`/programs/${program.slug}/stations/${next.position}`}
              className={buttonClasses("primary")}
            >
              {state.visitedStations.length === 0
                ? t("program.start")
                : t("program.continue", { title: next.title })}
            </Link>
          </p>
        )}
      </div>
      <PathSwitch />
      <section aria-labelledby="program-stations">
        <h2
          id="program-stations"
          className="text-xl font-semibold tracking-tight"
        >
          {t("program.stations")}
        </h2>
        <div className="mt-3">
          <StationList program={program} state={state} />
        </div>
      </section>
      <nav aria-label={t("program.moreLabel")}>
        <ul className="flex flex-wrap gap-x-6 gap-y-2">
          <li>
            <Link
              to={`/programs/${program.slug}/glossary`}
              className={linkClasses}
            >
              {t("glossary.title")}
            </Link>
          </li>
          <li>
            <Link
              to={`/programs/${program.slug}/handbook`}
              className={linkClasses}
            >
              {t("handbook.title")}
            </Link>
          </li>
        </ul>
      </nav>
    </div>
  );
}

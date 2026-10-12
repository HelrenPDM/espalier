import { CheckIcon } from "@heroicons/react/20/solid";
import { useId, useState } from "react";
import { useTranslation } from "react-i18next";
import { AlertRegion, StatusRegion } from "../../app/forms";
import { FOCUS_RING } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useParticipation, useVoteFormat } from "../../api/insights";
import { useContentLang } from "../../player/contentLang";
import { Markdown } from "../../player/Markdown";
import type { CompanionFormat, Station } from "../../player/runtime";
import { useTestNote } from "../../player/testNotes";
import { useCurrentPlayer } from "../../player/usePlayer";
import { useSaveErrorText } from "./saveError";

/**
 * One format: its title, phases and description, and the "Would use"
 * toggle. The toggle posts the vote once; afterwards it stays pressed and
 * disabled, because a vote cannot be changed.
 */
function FormatCard({
  format,
  voted,
  station,
}: {
  format: CompanionFormat;
  voted: boolean;
  station: Station;
}) {
  const { t } = useTranslation();
  const { program } = useCurrentPlayer();
  const lang = useContentLang();
  const note = useTestNote();
  const vote = useVoteFormat(program.slug);
  const saveErrorText = useSaveErrorText();
  const titleId = useId();
  const [justVoted, setJustVoted] = useState(false);
  const [failure, setFailure] = useState<unknown>(null);
  const pressed = voted || justVoted;

  const submit = async () => {
    if (pressed || vote.isPending) return;
    setFailure(null);
    try {
      await vote.mutateAsync(format.id);
      setJustVoted(true);
      note({ event: "format_voted", station: station.position });
    } catch (error) {
      setFailure(error);
    }
  };

  return (
    <article
      aria-labelledby={titleId}
      data-format={format.key}
      className="rounded-lg border border-gray-300 p-4 dark:border-gray-600"
    >
      <h2
        id={titleId}
        lang={lang}
        className="text-xl font-semibold tracking-tight"
      >
        {format.title}
      </h2>
      {format.phases.length > 0 && (
        <p className="mt-1 text-sm text-gray-700 dark:text-gray-300">
          {t("formatsStation.phases", {
            phases: format.phases
              .map((phase) => t(`formatsStation.phase.${phase}`))
              .join(", "),
          })}
        </p>
      )}
      <p lang={lang} className="mt-2">
        {format.description}
      </p>
      <div className="mt-4 flex flex-wrap items-center gap-3">
        <button
          type="button"
          aria-pressed={pressed}
          aria-describedby={titleId}
          disabled={pressed || vote.isPending}
          onClick={() => void submit()}
          className={`inline-flex min-h-6 items-center gap-1 rounded-md border px-4 py-2 text-sm font-semibold disabled:cursor-not-allowed ${
            pressed
              ? "border-accent-600 bg-accent-600 text-white dark:border-accent-100 dark:bg-accent-100 dark:text-gray-900"
              : "border-gray-500 bg-white text-gray-900 hover:bg-gray-100 disabled:opacity-50 dark:bg-gray-900 dark:text-gray-100 dark:hover:bg-gray-800"
          } ${FOCUS_RING}`}
        >
          {pressed && <CheckIcon aria-hidden="true" className="size-5" />}
          {t("formatsStation.wouldUse")}
        </button>
        <StatusRegion>{justVoted && t("formatsStation.voted")}</StatusRegion>
      </div>
      <div className="mt-2">
        <AlertRegion>
          {failure !== null &&
            saveErrorText(failure, t("formatsStation.voteFailed"))}
        </AlertRegion>
      </div>
    </article>
  );
}

/**
 * The companion formats station (task 0014, step 6): the station intro,
 * a note that a vote is anonymous and cannot be changed afterwards, and one
 * card per format of the program with its phases, its description and a
 * "Would use" toggle. The voted state comes from the participation of the
 * learner, so a second visit shows the earlier votes pressed.
 */
export function CompanionFormatsStation({ station }: { station: Station }) {
  const { t } = useTranslation();
  const { program } = useCurrentPlayer();
  const participation = useParticipation(program.slug);
  const formats = program.companion_formats;
  const votes = participation.data?.format_votes ?? [];

  return (
    <div className="space-y-6">
      {station.intro && <Markdown>{station.intro}</Markdown>}
      {formats.length === 0 ? (
        <p className="text-gray-700 dark:text-gray-300">
          {t("formatsStation.none")}
        </p>
      ) : participation.isPending ? (
        <LoadingStatus text={t("formatsStation.loading")} />
      ) : (
        <>
          <p className="text-sm text-gray-700 dark:text-gray-300">
            {t("formatsStation.anonymous")}
          </p>
          {participation.isError && (
            <p role="alert" className="text-gray-700 dark:text-gray-300">
              {t("formatsStation.loadFailed")}
            </p>
          )}
          <ul className="space-y-4">
            {formats.map((format) => (
              <li key={format.id}>
                <FormatCard
                  format={format}
                  voted={votes.includes(format.id)}
                  station={station}
                />
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}

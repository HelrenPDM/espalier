import { useId, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { AlertRegion } from "../../app/forms";
import { FOCUS_RING, linkClasses } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useParticipation, useRecordSelfAssessment } from "../../api/insights";
import { useContentLang } from "../../player/contentLang";
import { Markdown } from "../../player/Markdown";
import { PathSwitch } from "../../player/PathSwitch";
import { sortedStations } from "../../player/program";
import type { Segment, Station } from "../../player/runtime";
import { useCurrentPlayer } from "../../player/usePlayer";
import { useSaveErrorText } from "./saveError";
import { useProgramBase } from "../../player/programBase";

/**
 * One segment as a button: its label names the button, and its
 * description and the path it suggests describe it.
 */
function SegmentButton({
  segment,
  disabled,
  onChoose,
}: {
  segment: Segment;
  disabled: boolean;
  onChoose: (segment: Segment) => void;
}) {
  const { t } = useTranslation();
  const lang = useContentLang();
  const labelId = useId();
  const descriptionId = useId();
  const pathId = useId();
  return (
    <button
      type="button"
      onClick={() => onChoose(segment)}
      disabled={disabled}
      aria-labelledby={labelId}
      aria-describedby={`${descriptionId} ${pathId}`}
      data-segment={segment.key}
      className={`block w-full rounded-lg border border-gray-300 bg-white p-4 text-left hover:border-accent-600 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-900 dark:hover:border-accent-100 dark:hover:bg-gray-800 ${FOCUS_RING}`}
    >
      <span id={labelId} lang={lang} className="block font-semibold">
        {segment.label}
      </span>
      <span
        id={descriptionId}
        lang={lang}
        className="mt-1 block text-sm text-gray-700 dark:text-gray-300"
      >
        {segment.description}
      </span>
      <span id={pathId} className="mt-2 block text-sm font-medium">
        {t("selfAssessment.suggestedPath", {
          path: t(`path.${segment.default_path}`),
        })}
      </span>
    </button>
  );
}

/**
 * The outcome of a choice on this visit: the server applied the segment's
 * default path (`recorded`), it kept the path that the learner had chosen
 * by hand (`kept`), the player could not load the path that the server set
 * (`reload`), or the server had recorded an answer before (`already`).
 */
type Outcome = "recorded" | "kept" | "reload" | "already";

const OUTCOME_TEXT = {
  recorded: "selfAssessment.recorded",
  kept: "selfAssessment.recordedKept",
  reload: "selfAssessment.recordedReload",
  already: "selfAssessment.alreadyRecorded",
} as const satisfies Record<Outcome, string>;

/**
 * The self-assessment station (task 0014, step 5): the question of the
 * station, one card per segment of the program, a note that the answer is
 * stored without the person's name and only preselects the path, and a
 * link that skips to the next station and leaves the enrollment as it is.
 * Choosing a segment posts the self-assessment; the server applies the
 * segment's default path unless the learner chose a path by hand, and the
 * player takes the path of the enrollment over through `refreshPath()`, so
 * the path switch shows it without sending it as a manual choice. The
 * station states whether the default path was preselected or the path
 * chosen by hand stayed. When `refreshPath()` fails twice, the station says
 * that the path appears after a reload instead; putting the returned path
 * into the player through `update()` would send it as a manual choice.
 * Once the participation says the learner has answered, the station shows
 * the path switch and states that the answer was already recorded.
 */
export function SelfAssessmentStation({ station }: { station: Station }) {
  const { t } = useTranslation();
  const programBase = useProgramBase();
  const { program, refreshPath } = useCurrentPlayer();
  const lang = useContentLang();
  const participation = useParticipation(program.slug);
  const record = useRecordSelfAssessment(program.slug);
  const saveErrorText = useSaveErrorText();
  const questionId = useId();
  const resultRef = useRef<HTMLDivElement>(null);
  const [choosing, setChoosing] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [failure, setFailure] = useState<unknown>(null);

  const next = sortedStations(program).find(
    (entry) => entry.position > station.position,
  );
  const skipTo = next
    ? `${programBase}/${program.slug}/stations/${next.position}`
    : `${programBase}/${program.slug}`;

  const choose = async (segment: Segment) => {
    if (choosing) return;
    setChoosing(true);
    setFailure(null);
    try {
      const result = await record.mutateAsync(segment.key);
      // The path of the enrollment reaches the player through a load of the
      // progress, which is tried once more when it fails.
      const adopted = (await refreshPath()) || (await refreshPath());
      if (result.already_recorded) setOutcome("already");
      else if (!adopted) setOutcome("reload");
      else if (result.path !== null && result.path !== segment.default_path)
        setOutcome("kept");
      else setOutcome("recorded");
      requestAnimationFrame(() => resultRef.current?.focus());
    } catch (error) {
      setFailure(error);
    } finally {
      setChoosing(false);
    }
  };

  // While a choice is saved, the reloaded participation already says
  // "answered"; the segments stay until the outcome of the choice is known.
  const answered =
    outcome !== null ||
    (!choosing && participation.data?.self_assessment === true);

  return (
    <div className="space-y-6">
      {station.intro && <Markdown>{station.intro}</Markdown>}
      {participation.isPending ? (
        <LoadingStatus text={t("selfAssessment.loading")} />
      ) : answered ? (
        <div
          ref={resultRef}
          tabIndex={-1}
          className="space-y-4 rounded-md focus:outline-2 focus:outline-offset-2 focus:outline-accent-500"
        >
          <p data-outcome={outcome ?? "already"}>
            {t(OUTCOME_TEXT[outcome ?? "already"])}
          </p>
          <PathSwitch />
        </div>
      ) : (
        <>
          {participation.isError && (
            <p role="alert" className="text-gray-700 dark:text-gray-300">
              {t("selfAssessment.loadFailed")}
            </p>
          )}
          {station.question && (
            <h2
              id={questionId}
              lang={lang}
              className="text-xl font-semibold tracking-tight"
            >
              {station.question}
            </h2>
          )}
          <p className="text-sm text-gray-700 dark:text-gray-300">
            {t("selfAssessment.privacy")}
          </p>
          {program.segments.length === 0 ? (
            <p>{t("selfAssessment.noSegments")}</p>
          ) : (
            <ul
              aria-labelledby={station.question ? questionId : undefined}
              aria-label={
                station.question ? undefined : t("selfAssessment.segments")
              }
              className="space-y-3"
            >
              {program.segments.map((segment) => (
                <li key={segment.key}>
                  <SegmentButton
                    segment={segment}
                    disabled={choosing}
                    onChoose={(chosen) => void choose(chosen)}
                  />
                </li>
              ))}
            </ul>
          )}
          {choosing && <LoadingStatus text={t("selfAssessment.saving")} />}
          <AlertRegion>
            {failure !== null &&
              saveErrorText(failure, t("selfAssessment.saveFailed"))}
          </AlertRegion>
          <p>
            <Link to={skipTo} className={linkClasses}>
              {t("selfAssessment.skip")}
            </Link>
          </p>
        </>
      )}
    </div>
  );
}

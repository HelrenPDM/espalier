import { useId, useState, useSyncExternalStore } from "react";
import { useTranslation } from "react-i18next";
import { Button, StatusRegion } from "../../app/forms";
import type { TestNote, TestNotesLog } from "./store";

/** The time of a note since the log started, as `+m:ss`. */
function clock(at: number): string {
  const seconds = Math.floor(at / 1000);
  return `+${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

type Status = "copied" | "copyFailed" | "cleared" | null;

/**
 * The "Test notes" panel (task 0014, step 11): the log of the test session
 * as text, one line per event with its time since the log started, and
 * buttons that copy the text to the clipboard and clear the log. Nothing
 * of the log leaves the browser unless the tester pastes it somewhere.
 */
export function TestNotesPanel({ log }: { log: TestNotesLog }) {
  const { t } = useTranslation();
  const headingId = useId();
  const textId = useId();
  const notes = useSyncExternalStore(log.subscribe, log.notes);
  const [status, setStatus] = useState<Status>(null);

  const line = (note: TestNote): string => {
    switch (note.event) {
      case "station_opened":
        return t("testNotes.events.stationOpened", { station: note.station });
      case "path_switched":
        return t("testNotes.events.pathSwitched", {
          path: t(`path.${note.path}`),
        });
      case "item_answered":
        return note.correct === null
          ? t("testNotes.events.itemPoll", { item: note.item })
          : note.correct
            ? t("testNotes.events.itemCorrect", { item: note.item })
            : t("testNotes.events.itemWrong", { item: note.item });
      case "explanation_revealed":
        return t("testNotes.events.explanationRevealed", { item: note.item });
      case "exam_submitted":
        return note.outcome === "passed"
          ? t("testNotes.events.examPassed", { assessment: note.assessment })
          : note.outcome === "failed_core"
            ? t("testNotes.events.examFailedCore", {
                assessment: note.assessment,
              })
            : t("testNotes.events.examFailedErrors", {
                assessment: note.assessment,
              });
      case "format_voted":
        return t("testNotes.events.formatVoted", { station: note.station });
    }
  };
  const text = notes
    .map((note) => `${clock(note.at)} ${line(note)}`)
    .join("\n");

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(text);
      setStatus("copied");
    } catch {
      setStatus("copyFailed");
    }
  };

  const clear = () => {
    log.clear();
    setStatus("cleared");
  };

  return (
    <section
      aria-labelledby={headingId}
      className="no-print mt-12 rounded-lg border border-dashed border-gray-500 p-4 dark:border-gray-400"
    >
      <h2 id={headingId} className="text-lg font-semibold tracking-tight">
        {t("testNotes.title")}
      </h2>
      <p className="mt-1 text-sm text-gray-700 dark:text-gray-300">
        {t("testNotes.intro")}
      </p>
      <label
        htmlFor={textId}
        className="mt-4 block text-sm font-medium text-gray-900 dark:text-gray-100"
      >
        {t("testNotes.logLabel")}
      </label>
      <textarea
        id={textId}
        readOnly
        rows={8}
        value={text}
        placeholder={t("testNotes.empty")}
        className="mt-1 block w-full rounded-md border border-gray-500 bg-white px-3 py-2 font-mono text-sm text-gray-900 placeholder:text-gray-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500 dark:bg-gray-900 dark:text-gray-100 dark:placeholder:text-gray-400"
      />
      <div className="mt-3 flex flex-wrap items-center gap-2">
        <Button
          variant="secondary"
          onClick={() => void copy()}
          disabled={notes.length === 0}
        >
          {t("testNotes.copy")}
        </Button>
        <Button
          variant="secondary"
          onClick={clear}
          disabled={notes.length === 0}
        >
          {t("testNotes.clear")}
        </Button>
      </div>
      <div className="mt-2">
        <StatusRegion>
          {status !== null && t(`testNotes.${status}`)}
        </StatusRegion>
      </div>
    </section>
  );
}

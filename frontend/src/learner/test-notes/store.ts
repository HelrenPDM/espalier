import type { ExamOutcome } from "../../player/runtime";
import type { TestNoteEvent } from "../../player/testNotes";

/**
 * The store of the test session notes (task 0014, step 11, ASVS 14.3.3).
 * With `TEST_NOTES=true` it keeps the events of a usability test in
 * `sessionStorage` under the key `espalier.test_notes`, so the log lives in
 * one browser tab and ends with it. A sign-out and a sign-in end it as
 * well (`resetTestNotes`), so the next test person in the same tab starts
 * with an empty log and a new clock. This module is the only one of the SPA
 * that reads or writes that key, and it wraps every access in `try/catch`:
 * a browser with blocked storage throws on `sessionStorage` itself, and the
 * log then lives in memory for this page only.
 *
 * The entry holds `v` and `notes`. Each note holds an event name, the
 * station position, item id, assessment id, correctness, exam outcome or
 * path of the event, and `at`, the milliseconds since the log started. It
 * holds no user id, display name, e-mail address, session token, CSRF
 * token, answer or clock time, and no module sends it to the server.
 */
export const TEST_NOTES_KEY = "espalier.test_notes";

const ENTRY_VERSION = 1;

/** The most notes the log keeps; the oldest drop out first. */
const MAX_NOTES = 500;

/** An event with its time in milliseconds since the log started. */
export type TestNote = TestNoteEvent & { at: number };

/** The log of the test session notes, or a log that records nothing. */
export interface TestNotesLog {
  /** Whether the log records; false while `flags.testNotes` is false. */
  readonly enabled: boolean;
  /** Appends `event` with its time since the log started. */
  record(event: TestNoteEvent): void;
  /** The notes, oldest first; the same array until the log changes. */
  notes(): readonly TestNote[];
  /** Removes every note and restarts the clock. */
  clear(): void;
  /** Calls `listener` after each change; returns the unsubscribe function. */
  subscribe(listener: () => void): () => void;
}

const OUTCOMES: readonly ExamOutcome[] = [
  "passed",
  "failed_core",
  "failed_errors",
];

const position = (value: unknown): value is number =>
  Number.isInteger(value) && (value as number) >= 0;

/**
 * Copies the members of one stored note that its event knows, or returns
 * `null` for a malformed note, so no other key of the entry passes on.
 */
function parseNote(value: unknown): TestNote | null {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    return null;
  const note = value as Record<string, unknown>;
  const at = note.at;
  if (typeof at !== "number" || !Number.isFinite(at) || at < 0) return null;
  switch (note.event) {
    case "station_opened":
      return position(note.station)
        ? { event: "station_opened", station: note.station, at }
        : null;
    case "path_switched":
      return note.path === "short" || note.path === "full"
        ? { event: "path_switched", path: note.path, at }
        : null;
    case "item_answered":
      return typeof note.item === "string" &&
        (note.correct === null || typeof note.correct === "boolean")
        ? { event: "item_answered", item: note.item, correct: note.correct, at }
        : null;
    case "explanation_revealed":
      return typeof note.item === "string"
        ? { event: "explanation_revealed", item: note.item, at }
        : null;
    case "exam_submitted": {
      const outcome = OUTCOMES.find((entry) => entry === note.outcome);
      return typeof note.assessment === "string" && outcome !== undefined
        ? {
            event: "exam_submitted",
            assessment: note.assessment,
            outcome,
            at,
          }
        : null;
    }
    case "format_voted":
      return position(note.station)
        ? { event: "format_voted", station: note.station, at }
        : null;
    default:
      return null;
  }
}

/**
 * Reads an entry. A missing, unreadable or malformed entry, or one of
 * another version, yields no notes; a malformed note is dropped.
 */
function parseEntry(raw: string | null): TestNote[] {
  if (raw === null) return [];
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return [];
  }
  if (typeof value !== "object" || value === null || Array.isArray(value))
    return [];
  const entry = value as Record<string, unknown>;
  if (entry.v !== ENTRY_VERSION || !Array.isArray(entry.notes)) return [];
  return entry.notes
    .map(parseNote)
    .filter((note): note is TestNote => note !== null)
    .slice(-MAX_NOTES);
}

function read(): string | null {
  try {
    return sessionStorage.getItem(TEST_NOTES_KEY);
  } catch {
    return null;
  }
}

function write(notes: readonly TestNote[]): void {
  try {
    sessionStorage.setItem(
      TEST_NOTES_KEY,
      JSON.stringify({ v: ENTRY_VERSION, notes }),
    );
  } catch {
    // The notes stay in memory for this page.
  }
}

function remove(): void {
  try {
    sessionStorage.removeItem(TEST_NOTES_KEY);
  } catch {
    // Nothing was stored.
  }
}

// The notes of this page, read from the entry on first use, and the clock
// time at which the log started. A reload continues the clock at the time
// of the last note, because the entry holds no clock time.
let loaded: readonly TestNote[] | null = null;
let startedAt: number | null = null;
const listeners = new Set<() => void>();

function current(): readonly TestNote[] {
  loaded ??= parseEntry(read());
  return loaded;
}

function change(notes: readonly TestNote[]): void {
  loaded = notes;
  for (const listener of [...listeners]) listener();
}

/**
 * Ends the log of this browser tab at a session change, a sign-out or a
 * sign-in (ASVS 14.3.1): removes every note from memory and the entry from
 * `sessionStorage`, restarts the clock and notifies the listeners, so an
 * open panel shows the empty log. It removes the entry also while
 * `flags.testNotes` is false, because the flag may have been true when the
 * entry was written.
 */
export function resetTestNotes(): void {
  startedAt = null;
  remove();
  change([]);
}

const enabledLog: TestNotesLog = {
  enabled: true,
  record(event) {
    const notes = current();
    const last = notes.at(-1)?.at ?? 0;
    const now = Date.now();
    startedAt ??= now - last;
    // A clock set back keeps the order of the notes.
    const at = Math.max(last, Math.round(now - startedAt));
    const next = [...notes, { ...event, at }].slice(-MAX_NOTES);
    write(next);
    change(next);
  },
  notes: current,
  clear: resetTestNotes,
  subscribe(listener) {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  },
};

const NO_NOTES: readonly TestNote[] = [];

const disabledLog: TestNotesLog = {
  enabled: false,
  record() {},
  notes: () => NO_NOTES,
  clear() {},
  subscribe: () => () => {},
};

/**
 * The log of this browser tab while `enabled` (`flags.testNotes`) is true,
 * and otherwise a log that neither reads nor writes any storage.
 */
export function testNotesLog(enabled: boolean): TestNotesLog {
  return enabled ? enabledLog : disabledLog;
}

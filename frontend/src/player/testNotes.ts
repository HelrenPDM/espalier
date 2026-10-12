import { createContext, useContext } from "react";
import type { ExamOutcome, Path } from "./runtime";

/**
 * An event of the test session notes (task 0014, step 11). Each event holds
 * only an event name and the station position, item id, assessment id,
 * correctness, exam outcome or path that describes it; never a person's
 * data, an answer or a token.
 */
export type TestNoteEvent =
  | { event: "station_opened"; station: number }
  | { event: "path_switched"; path: Path }
  | { event: "item_answered"; item: string; correct: boolean | null }
  | { event: "explanation_revealed"; item: string }
  | { event: "exam_submitted"; assessment: string; outcome: ExamOutcome }
  | { event: "format_voted"; station: number };

export type RecordTestNote = (event: TestNoteEvent) => void;

const recordNothing: RecordTestNote = () => {};

/**
 * The function that records an event of the test session notes. Its default
 * records nothing, so the player works unchanged in the admin preview, in
 * the SCORM package and whenever `TEST_NOTES` is off; the learner pages
 * provide the store of `src/learner/test-notes/` while the flag is on.
 */
export const TestNotesContext = createContext<RecordTestNote>(recordNothing);

/** The function that records an event of the test session notes. */
export function useTestNote(): RecordTestNote {
  return useContext(TestNotesContext);
}

import type { ReactNode } from "react";
import { useSession } from "../../auth/SessionProvider";
import { TestNotesContext } from "../../player/testNotes";
import { testNotesLog } from "./store";
import { TestNotesPanel } from "./TestNotesPanel";

/**
 * Wires the test session notes of the player and the learner pages to
 * the store of this directory while `flags.testNotes` (`TEST_NOTES`) is
 * true, and shows the "Test notes" panel below `children`. While the flag
 * is false, the components below record into a log that touches no
 * storage, and no panel appears.
 */
export function TestNotesProvider({ children }: { children: ReactNode }) {
  const { flags } = useSession();
  const log = testNotesLog(flags.testNotes);
  return (
    <TestNotesContext.Provider value={log.record}>
      {children}
      {log.enabled && <TestNotesPanel log={log} />}
    </TestNotesContext.Provider>
  );
}

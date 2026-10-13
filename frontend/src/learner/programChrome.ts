import { createContext, useContext } from "react";

/**
 * True below `ProgramShell`, the frame of the platform routes of a program,
 * which renders the breadcrumbs and the program navigation with the step
 * list. The station page, the glossary and the handbook then leave out
 * their own step list and their link back to the program page. The admin
 * preview (0015) and the SCORM package (0016) render the same pages without
 * the shell, so they keep both.
 */
export const ProgramChromeContext = createContext(false);

/** Whether a program shell around the page provides the program navigation. */
export function useProgramChrome(): boolean {
  return useContext(ProgramChromeContext);
}

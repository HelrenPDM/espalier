import { createContext, useContext } from "react";

/**
 * The path below which the pages of a program live: `/programs` for the
 * learner routes, and the program path inside the preview route
 * `/admin/packs/:id/preview` of task 0015. The pages of the player build
 * every link to a program page from it, so that the preview keeps its links
 * below its own route.
 */
export const ProgramBaseContext = createContext("/programs");

/** The base path of the program pages, `/programs` unless a provider sets another. */
export function useProgramBase(): string {
  return useContext(ProgramBaseContext);
}

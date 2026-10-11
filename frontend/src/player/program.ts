import type { ProgramView, Station } from "./runtime";

/** The stations of a program in position order. */
export function sortedStations(
  program: Pick<ProgramView, "stations">,
): Station[] {
  return [...program.stations].sort((a, b) => a.position - b.position);
}

/** The station of the module `moduleId`, if the program has one. */
export function moduleStation(
  program: Pick<ProgramView, "stations">,
  moduleId: string,
): Station | undefined {
  return program.stations.find(
    (station) => station.kind === "module" && station.module_id === moduleId,
  );
}

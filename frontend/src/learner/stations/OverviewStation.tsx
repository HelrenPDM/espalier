import { Markdown } from "../../player/Markdown";
import type { Station } from "../../player/runtime";

/** The overview station: its title (the station heading) and its intro. */
export function OverviewStation({ station }: { station: Station }) {
  if (!station.intro) return null;
  return <Markdown>{station.intro}</Markdown>;
}

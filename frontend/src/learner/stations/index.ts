import type { ComponentType } from "react";
import type { Station, StationKind } from "../../player/runtime";
import { ModuleStation } from "../ModuleStation";
import { OverviewStation } from "./OverviewStation";
import { PendingStation } from "./PendingStation";

/**
 * The component of each station kind. 0013 and 0014 replace the pending
 * panels of `self_assessment`, `credential`, `companion_formats` and
 * `feedback` with their components.
 */
export const STATION_COMPONENTS: Record<
  StationKind,
  ComponentType<{ station: Station }>
> = {
  overview: OverviewStation,
  module: ModuleStation,
  self_assessment: PendingStation,
  credential: PendingStation,
  companion_formats: PendingStation,
  feedback: PendingStation,
};

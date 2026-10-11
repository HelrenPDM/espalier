import type { ComponentType } from "react";
import type { Station, StationKind } from "../../player/runtime";
import { ModuleStation } from "../ModuleStation";
import { CredentialStation } from "./CredentialStation";
import { OverviewStation } from "./OverviewStation";
import { PendingStation } from "./PendingStation";

/**
 * The component of each station kind. 0013 adds the credential station;
 * 0014 replaces the pending panels of `self_assessment`,
 * `companion_formats` and `feedback` with their components.
 */
export const STATION_COMPONENTS: Record<
  StationKind,
  ComponentType<{ station: Station }>
> = {
  overview: OverviewStation,
  module: ModuleStation,
  self_assessment: PendingStation,
  credential: CredentialStation,
  companion_formats: PendingStation,
  feedback: PendingStation,
};

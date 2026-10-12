import type { ComponentType } from "react";
import type { Station, StationKind } from "../../player/runtime";
import { ModuleStation } from "../ModuleStation";
import { CompanionFormatsStation } from "./CompanionFormatsStation";
import { CredentialStation } from "./CredentialStation";
import { FeedbackStation } from "./FeedbackStation";
import { OverviewStation } from "./OverviewStation";
import { SelfAssessmentStation } from "./SelfAssessmentStation";

/**
 * The component of each station kind. 0013 adds the credential station;
 * 0014 adds the self-assessment, the companion formats and the feedback
 * station.
 */
export const STATION_COMPONENTS: Record<
  StationKind,
  ComponentType<{ station: Station }>
> = {
  overview: OverviewStation,
  module: ModuleStation,
  self_assessment: SelfAssessmentStation,
  credential: CredentialStation,
  companion_formats: CompanionFormatsStation,
  feedback: FeedbackStation,
};

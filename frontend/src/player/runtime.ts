import type { components } from "../api/schema";

/**
 * The runtime adapter of README section 9. The player depends on this
 * interface only: the platform build uses `PlatformRuntime`, the admin
 * preview `StandaloneRuntime` (0015) and the SCORM build `Scorm12Runtime` or
 * `Scorm2004Runtime` (0016).
 */
export interface Runtime {
  loadProgram(slug: string): Promise<ProgramView>;
  submitItem(itemId: string, answer: Answer): Promise<ItemFeedback>;
  submitAssessment(
    assessmentId: string,
    answers: Record<string, Answer>,
  ): Promise<AttemptResult>;
  completeModule(moduleId: string): Promise<void>;
  loadState(): Promise<ResumeState | null>;
  saveState(state: ResumeState): Promise<void>;
}

type Schemas = components["schemas"];

/** The program of `GET /api/programs/:slug`, as the API sends it. */
type ProgramPayload = Schemas["ProgramView"];

export type ModuleView = Schemas["ModuleView"];
export type ObjectiveView = Schemas["ObjectiveView"];
export type ObjectiveEvidence = Schemas["ObjectiveEvidence"];
export type ItemView = Schemas["ItemView"];
export type Answer = Schemas["Answer"];
export type ItemFeedback = Schemas["ItemResult"];
export type AttemptResult = Schemas["AttemptResult"];
export type Station = ProgramPayload["stations"][number];
export type StationKind = Station["kind"];
export type Segment = ProgramPayload["segments"][number];
export type CompanionFormat = Schemas["CompanionFormatView"];
export type GlossaryEntry = Schemas["Glossary"]["terms"][number];
export type Lesson = ModuleView["lessons"][number];
export type Block = Lesson["blocks"][number];
export type Citation = Block["citations"][number];
export type Rule = ModuleView["rules"][number];
export type Exam = ModuleView["exams"][number];
export type Provenance = Block["provenance"];
export type Path = Schemas["EnrollmentView"]["path"];
export type ExamOutcome = AttemptResult["outcome"];

/**
 * The media of a `figure` or a `video` block (task 0018, step 12), with
 * URLs that the player sets as they are: `/media/<sha256>.<ext>` on the
 * platform and in the admin preview, `media/<sha256>.<ext>` relative to
 * `index.html` in a SCORM package, and the `https:` URL of an external
 * file or an embed player. `available` is false when a host is not
 * allowlisted or a file is missing; the block then shows a notice.
 */
export type BlockMedia = Schemas["BlockMedia"];
export type MediaImage = NonNullable<BlockMedia["image"]>;
export type MediaVideo = NonNullable<BlockMedia["video"]>;
export type MediaPoster = NonNullable<BlockMedia["poster"]>;
export type EmbedSource = NonNullable<BlockMedia["embed"]>;
export type MediaCaption = BlockMedia["captions"][number];
export type FigureSize = NonNullable<BlockMedia["size"]>;

/**
 * A program with everything the player renders: the program of
 * `GET /api/programs/:slug` with its stations, segments and companion
 * formats, one `ModuleView` of `GET /api/modules/:id` per module in number
 * order in place of the module summaries, and the glossary of
 * `GET /api/programs/:slug/glossary`.
 */
export type ProgramView = Omit<ProgramPayload, "modules"> & {
  modules: ModuleView[];
  glossary: GlossaryEntry[];
};

/**
 * The state of a learner in one program. `answeredItems` records only that
 * an item was answered, never the answer or its correctness.
 * `evidencedObjectives` holds the objective keys whose evidence the runtime
 * reports.
 */
export interface ResumeState {
  path: Path;
  /** Block ids of the explanations the learner opened. */
  openedExplanations: string[];
  /** Station positions. */
  visitedStations: number[];
  /** Item ids. */
  answeredItems: string[];
  /** Module ids. */
  completedModules: string[];
  /** Assessment id to the outcome of the exam. */
  examOutcomes: Record<string, ExamOutcome>;
  evidencedObjectives: string[];
}

/**
 * The status of an objective in the current view. No runtime stores it;
 * `objectiveStatus` derives it from `ResumeState` on every render.
 */
export type ObjectiveStatus = "evidenced" | "practised" | "open";

/** An exam of `AssessmentsOpenError`. */
export type OpenAssessment =
  Schemas["AssessmentsOpenError"]["assessments"][number];

/**
 * `completeModule` rejects with this error while an exam of the module with
 * `counts_for_credential: true` has no passed attempt (the 409
 * `assessments_open` answer of 0009 step 13).
 */
export class AssessmentsOpenError extends Error {
  readonly assessments: OpenAssessment[];

  constructor(assessments: OpenAssessment[]) {
    super("assessments_open");
    this.name = "AssessmentsOpenError";
    this.assessments = assessments;
  }
}

/** The state of a learner without any record. */
export function emptyResumeState(path: Path = "full"): ResumeState {
  return {
    path,
    openedExplanations: [],
    visitedStations: [],
    answeredItems: [],
    completedModules: [],
    examOutcomes: {},
    evidencedObjectives: [],
  };
}

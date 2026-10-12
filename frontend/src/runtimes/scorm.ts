import {
  AssessmentsOpenError,
  type Answer,
  type AttemptResult,
  type Block,
  type ItemFeedback,
  type Path,
  type ProgramView,
  type ResumeState,
  type Runtime,
} from "../player/runtime";
import { contentPayload, type ScormContent } from "./content";
import {
  deriveObjectiveStates,
  type AssessmentProgress,
  type ObjectiveEntry,
  type ObjectiveState,
} from "./objectives";
import { StandaloneRuntime, payloadIds } from "./standalone";
import {
  decodeSuspendData,
  encodeSuspendData,
  explanationBlockIds,
  type SuspendState,
} from "./suspend";

/** A data model element with the value to write. */
export type Assignment = readonly [element: string, value: string];

/** The facts of the module that its status elements follow. */
export interface StatusFacts {
  /**
   * `passed` when every exam of the module has the outcome `passed`,
   * `failed` when an exam has a failed outcome, and `null` while the module
   * has no exam or an exam without an attempt and no failed one.
   */
  success: "passed" | "failed" | null;
  /** The learner completed the module (`completeModule`). */
  completed: boolean;
}

/**
 * What differs between SCORM 1.2 and SCORM 2004 for `ScormRuntime`: the
 * calls of the LMS API object, each returning the string of the LMS, and
 * the data model elements with their vocabularies. `read` gives the value
 * that the session knows for an element (read at start or written since),
 * or `""`.
 */
export interface ScormDialect {
  initialize(): string;
  /**
   * True when the last call failed because the session is already
   * initialized, which `start` counts as an initialized session.
   */
  alreadyInitialized(): boolean;
  terminate(): string;
  getValue(element: string): string;
  setValue(element: string, value: string): string;
  commit(): string;
  /** The status elements that `start` reads. */
  readonly statusElements: readonly string[];
  /** True when the status read at start reports a completed module. */
  completedIn(read: (element: string) => string): boolean;
  /** The status elements and the exit element for `facts`, in writing order. */
  status(facts: StatusFacts, read: (element: string) => string): Assignment[];
  /** The status elements of the entry `index` of `cmi.objectives`. */
  objective(index: number, state: ObjectiveState): Assignment[];
  /** The score elements of an attempt with `raw` correct answers of `max` items. */
  score(raw: number, max: number): Assignment[];
  /** The session time element for a session of `milliseconds`. */
  sessionTime(milliseconds: number): Assignment;
}

const SUSPEND_DATA = "cmi.suspend_data";

/** The position of the module station, the only station of a package. */
const MODULE_STATION = 1;

const byKey = (a: { key: string }, b: { key: string }) =>
  a.key < b.key ? -1 : a.key > b.key ? 1 : 0;

/** `program` with the policy of `policies` on every placeholder block. */
function withPolicies(
  program: ProgramView,
  policies: ScormContent["policies"],
): ProgramView {
  const policyOf = (key: string | null) =>
    key !== null && Object.hasOwn(policies, key) ? policies[key] : null;
  return {
    ...program,
    modules: program.modules.map((module) => ({
      ...module,
      lessons: module.lessons.map((lesson) => ({
        ...lesson,
        blocks: lesson.blocks.map((block): Block =>
          block.kind === "placeholder"
            ? { ...block, policy: policyOf(block.placeholder_key) }
            : block,
        ),
      })),
    })),
  };
}

/**
 * The runtime of a SCORM package (task 0016, step 4), shared by
 * `Scorm12Runtime` and `Scorm2004Runtime`, which supply the dialect of
 * their version. It implements `Runtime` on `content.json`: the program view
 * and the evaluation come from `StandaloneRuntime` on `contentPayload`, the
 * blocks of kind `placeholder` carry the entry of `policies` as their
 * `policy`, and the progress of the learner goes to the LMS.
 *
 * - `start()` initializes the session, reads `cmi.suspend_data` and the
 *   status, restores the progress of earlier sessions, sets the initial
 *   status and exit, writes `cmi.objectives.n.id` and then the status of
 *   the same index for every objective in index order (the position among
 *   the objectives of the module), commits and registers `finish()` for
 *   `pagehide`. `finish()` writes the final values and the session time,
 *   commits and ends the session once.
 * - An item answer, an exam attempt and the completion of the module each
 *   write the score of the latest attempt, the status, the exit, the
 *   objective statuses and the suspend data, in this order, and commit
 *   once. Only the values that changed reach the LMS: an item answer
 *   writes the objective statuses whose state changed and the suspend
 *   data, an exam attempt also the score, the status and the exit, and the
 *   completion the status, the exit and the suspend data. `saveState`
 *   writes the suspend data.
 * - A practice item counts as correct once any answer was correct. An exam
 *   keeps `passed` once an attempt passed, also in an earlier session.
 * - Score: `raw` is the number of correct answers of the latest attempt,
 *   `min` 0 and `max` the number of items of its exam (SCORM 1.2 writes
 *   the percentage with `max` 100 for an exam of more than 100 items,
 *   because its score elements hold 0 to 100). Status: `passed`
 *   once every exam of the module has the outcome `passed`, `failed` while
 *   an exam has a failed outcome, and unchanged while an exam has no
 *   attempt. A module with one exam therefore reports the outcome of that
 *   exam; with several exams the score follows the latest attempt of any
 *   exam and the status all of them.
 * - `completeModule` rejects with `AssessmentsOpenError` while an exam with
 *   `counts_for_credential: true` has no passed attempt in this or an
 *   earlier session, as the platform does (0009 step 13).
 * - `loadState` returns the progress that `start()` restored and the
 *   session added: the path (`full` on the first launch), the opened
 *   explanations, the module station as
 *   visited, the answered practice items, the module when completed, the
 *   outcome per exam with an attempt and the objectives in the state
 *   `passed` as `evidencedObjectives`. `saveState` takes the path, the
 *   opened explanations and the completed module of the player, keeps the
 *   answers and attempts that the runtime recorded itself, and writes the
 *   encoding to `cmi.suspend_data`.
 * - A failing LMS call breaks nothing: `submitItem`, `submitAssessment` and
 *   `completeModule` resolve as without an LMS, and a value that was not
 *   stored is written again by the next operation. Only `saveState`
 *   rejects when `SetValue` or `Commit` fails, so the player shows that the
 *   progress was not saved. LMS calls before `start()` and after `finish()`
 *   are skipped.
 * - `start()` throws when the LMS does not initialize the session; a
 *   session that the LMS reports as already initialized counts as
 *   initialized. The runtime then makes no further LMS call, `Terminate`
 *   or `LMSFinish` included.
 * - `saveState` resolves without an LMS call before `start()`. After
 *   `finish()` and after a failed start it rejects without an LMS call, so
 *   that a page that the browser shows again from its back/forward cache
 *   after `pagehide` reports that the progress was not saved.
 */
export class ScormRuntime implements Runtime {
  readonly #content: ScormContent;
  readonly #dialect: ScormDialect;
  readonly #standalone: StandaloneRuntime;
  readonly #moduleId: string;
  /** Item id to item key. */
  readonly #itemKeys: Map<string, string>;
  readonly #explanations: string[];
  /** The values of the LMS that the session knows: read at start or written since. */
  readonly #values = new Map<string, string>();
  readonly #onPageHide = () => this.finish();
  #program: ProgramView | null = null;
  #phase: "new" | "started" | "failed" | "finished" = "new";
  #startedAt = 0;
  #uncommitted = false;
  /** The score elements of the latest attempt of this session. */
  #score: Assignment[] = [];

  #path: Path = "full";
  #opened = new Set<string>();
  #completed = false;
  readonly #answered = new Set<string>();
  readonly #correct = new Set<string>();
  readonly #assessments = new Map<string, AssessmentProgress>();

  constructor(content: ScormContent, dialect: ScormDialect) {
    this.#content = content;
    this.#dialect = dialect;
    this.#standalone = new StandaloneRuntime(contentPayload(content));
    this.#moduleId = payloadIds.module(content.module.number);
    this.#itemKeys = new Map(
      content.module.items.map((item) => [payloadIds.item(item.key), item.key]),
    );
    this.#explanations = explanationBlockIds(content.module);
  }

  /**
   * Initializes the LMS session and restores the progress of earlier
   * sessions; see the class description. A second call does nothing.
   * Throws when the LMS does not initialize the session; every later LMS
   * call is then skipped.
   */
  start(): void {
    if (this.#phase !== "new") return;
    if (!this.#initialize()) {
      this.#phase = "failed";
      throw new Error("The LMS did not initialize the session.");
    }
    this.#phase = "started";
    this.#startedAt = Date.now();
    for (const element of [SUSPEND_DATA, ...this.#dialect.statusElements])
      this.#values.set(element, this.#get(element));

    const restored = decodeSuspendData(
      this.#content.module,
      this.#values.get(SUSPEND_DATA),
    );
    if (restored !== null) this.#restore(restored);
    if (this.#dialect.completedIn(this.#read)) this.#completed = true;

    this.#write([
      ...this.#statusAssignments(),
      ...this.#objectiveAssignments(),
    ]);
    this.#commit();
    window.addEventListener("pagehide", this.#onPageHide);
  }

  /**
   * Writes the final values, commits and ends the LMS session. Only the
   * first call after `start()` does this.
   */
  finish(): void {
    if (this.#phase !== "started") return;
    this.#phase = "finished";
    window.removeEventListener("pagehide", this.#onPageHide);
    this.#write([
      ...this.#progressAssignments(),
      this.#dialect.sessionTime(Date.now() - this.#startedAt),
    ]);
    this.#commit();
    this.#call(() => this.#dialect.terminate());
  }

  async loadProgram(slug: string): Promise<ProgramView> {
    const program = await this.#standalone.loadProgram(slug);
    this.#program ??= withPolicies(program, this.#content.policies);
    return this.#program;
  }

  async submitItem(itemId: string, answer: Answer): Promise<ItemFeedback> {
    const feedback = await this.#standalone.submitItem(itemId, answer);
    const key = this.#itemKeys.get(itemId);
    if (key !== undefined) {
      this.#answered.add(key);
      if (feedback.correct === true) this.#correct.add(key);
    }
    this.#record();
    return feedback;
  }

  async submitAssessment(
    assessmentId: string,
    answers: Record<string, Answer>,
  ): Promise<AttemptResult> {
    const attempt = await this.#standalone.submitAssessment(
      assessmentId,
      answers,
    );
    const assessment = this.#content.module.assessments.find(
      (entry) => payloadIds.assessment(entry.key) === assessmentId,
    );
    if (assessment === undefined) return attempt;

    const before = this.#assessments.get(assessment.key);
    const number = (before?.attempts ?? 0) + 1;
    this.#assessments.set(assessment.key, {
      attempts: number,
      outcome: before?.outcome === "passed" ? "passed" : attempt.outcome,
    });
    const raw = attempt.results.filter((result) => result.correct === true);
    this.#score = this.#dialect.score(raw.length, attempt.results.length);
    this.#record();
    // The attempts of earlier sessions count on.
    return { ...attempt, id: `${assessmentId}-attempt-${number}`, number };
  }

  async completeModule(moduleId: string): Promise<void> {
    // The payload holds this module only, so StandaloneRuntime answers any
    // other id with 404 `not_found`.
    if (moduleId !== this.#moduleId)
      return this.#standalone.completeModule(moduleId);
    const open = this.#content.module.assessments
      .filter(
        (assessment) =>
          assessment.kind === "exam" &&
          assessment.counts_for_credential &&
          this.#assessments.get(assessment.key)?.outcome !== "passed",
      )
      .sort(byKey);
    if (open.length > 0)
      throw new AssessmentsOpenError(
        open.map((assessment) => ({
          id: payloadIds.assessment(assessment.key),
          key: assessment.key,
          title: assessment.title,
        })),
      );
    this.#completed = true;
    this.#record();
  }

  async loadState(): Promise<ResumeState> {
    const { module } = this.#content;
    return {
      path: this.#path,
      openedExplanations: this.#explanations.filter((id) =>
        this.#opened.has(id),
      ),
      visitedStations: [MODULE_STATION],
      answeredItems: module.items
        .filter((item) => this.#answered.has(item.key))
        .map((item) => payloadIds.item(item.key)),
      completedModules: this.#completed ? [this.#moduleId] : [],
      examOutcomes: Object.fromEntries(
        module.assessments.flatMap((assessment) => {
          const outcome = this.#assessments.get(assessment.key)?.outcome;
          return outcome === undefined || outcome === null
            ? []
            : [[payloadIds.assessment(assessment.key), outcome]];
        }),
      ),
      evidencedObjectives: this.#objectiveStates()
        .filter((entry) => entry.state === "passed")
        .map((entry) => entry.key),
    };
  }

  async saveState(state: ResumeState): Promise<void> {
    this.#path = state.path;
    this.#opened = new Set(state.openedExplanations);
    if (state.completedModules.includes(this.#moduleId)) this.#completed = true;
    if (this.#phase === "new") return;
    if (this.#phase !== "started")
      throw new Error("The LMS session is not open.");
    const data = encodeSuspendData(this.#content.module, this.#suspendState());
    if (!this.#write([[SUSPEND_DATA, data]]) || !this.#commit())
      throw new Error("The LMS did not store the suspend data.");
  }

  #restore(state: SuspendState): void {
    this.#path = state.path;
    this.#opened = new Set(state.openedExplanations);
    this.#completed = state.completed;
    for (const key of state.answeredItems) this.#answered.add(key);
    for (const key of state.correctItems) this.#correct.add(key);
    for (const [key, progress] of Object.entries(state.assessments))
      this.#assessments.set(key, progress);
  }

  #suspendState(): SuspendState {
    return {
      path: this.#path,
      completed: this.#completed,
      openedExplanations: [...this.#opened],
      answeredItems: [...this.#answered],
      correctItems: [...this.#correct],
      assessments: Object.fromEntries(this.#assessments),
    };
  }

  #objectiveStates(): ObjectiveEntry[] {
    return deriveObjectiveStates(this.#content, this.#suspendState());
  }

  #facts(): StatusFacts {
    const outcomes = this.#content.module.assessments
      .filter((assessment) => assessment.kind === "exam")
      .map((exam) => this.#assessments.get(exam.key)?.outcome ?? null);
    return {
      success:
        outcomes.length === 0
          ? null
          : outcomes.every((outcome) => outcome === "passed")
            ? "passed"
            : outcomes.some(
                  (outcome) => outcome !== null && outcome !== "passed",
                )
              ? "failed"
              : null,
      completed: this.#completed,
    };
  }

  #statusAssignments(): Assignment[] {
    return this.#dialect.status(this.#facts(), this.#read);
  }

  /** Per objective in index order: its id, then its status elements. */
  #objectiveAssignments(): Assignment[] {
    return this.#objectiveStates().flatMap(({ key, state }, index) => [
      [`cmi.objectives.${index}.id`, key] as const,
      ...this.#dialect.objective(index, state),
    ]);
  }

  /** The suspend data, or nothing when the encoding exceeds the limit. */
  #suspendAssignments(): Assignment[] {
    try {
      return [
        [
          SUSPEND_DATA,
          encodeSuspendData(this.#content.module, this.#suspendState()),
        ],
      ];
    } catch {
      return [];
    }
  }

  /** The progress in writing order; `#write` skips what did not change. */
  #progressAssignments(): Assignment[] {
    return [
      ...this.#score,
      ...this.#statusAssignments(),
      ...this.#objectiveAssignments(),
      ...this.#suspendAssignments(),
    ];
  }

  readonly #read = (element: string): string => this.#values.get(element) ?? "";

  /** Writes the progress and commits within a started session; skipped otherwise. */
  #record(): void {
    if (this.#phase !== "started") return;
    this.#write(this.#progressAssignments());
    this.#commit();
  }

  /**
   * Sets every value that differs from the known value of its element, in
   * order. Returns false when a `SetValue` call failed; that value stays
   * unknown, so the next operation writes it again.
   */
  #write(assignments: Iterable<Assignment>): boolean {
    let stored = true;
    for (const [element, value] of assignments) {
      if (this.#values.get(element) === value) continue;
      if (this.#call(() => this.#dialect.setValue(element, value))) {
        this.#values.set(element, value);
        this.#uncommitted = true;
      } else stored = false;
    }
    return stored;
  }

  /** Commits when a value was set since the last successful commit. */
  #commit(): boolean {
    if (!this.#uncommitted) return true;
    if (!this.#call(() => this.#dialect.commit())) return false;
    this.#uncommitted = false;
    return true;
  }

  /** True when the LMS initializes the session or reports it as initialized. */
  #initialize(): boolean {
    if (this.#call(() => this.#dialect.initialize())) return true;
    try {
      return this.#dialect.alreadyInitialized();
    } catch {
      return false;
    }
  }

  /** True when the LMS answers `"true"`; an exception counts as `"false"`. */
  #call(call: () => string): boolean {
    try {
      return String(call()) === "true";
    } catch {
      return false;
    }
  }

  /** The value of `element`, or `""` when the call fails. */
  #get(element: string): string {
    try {
      const value: unknown = this.#dialect.getValue(element);
      return typeof value === "string" ? value : "";
    } catch {
      return "";
    }
  }
}

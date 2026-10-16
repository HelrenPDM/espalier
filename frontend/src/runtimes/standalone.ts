import { ApiError } from "../api/errors";
import {
  coreFailed,
  evaluate,
  passRule,
  validateAnswer,
  wrongCount,
  type EvaluableItem,
  type EvaluationContext,
  type PayloadOption,
} from "../player/evaluate";
import {
  AssessmentsOpenError,
  type Answer,
  type AttemptResult,
  type Block,
  type Citation,
  type CompanionFormat,
  type ExamOutcome,
  type GlossaryEntry,
  type ItemFeedback,
  type ItemView,
  type Lesson,
  type ModuleView,
  type ObjectiveView,
  type ProgramView,
  type ResumeState,
  type Rule,
  type Runtime,
  type Segment,
  type Station,
} from "../player/runtime";
import {
  blockMediaResolver,
  type BlockMediaResolver,
  type MediaPolicy,
  type PackMedia,
  type PayloadBlockMedia,
} from "./media";

/**
 * The normalized payload of a content pack (task 0008, step 9), as
 * `GET /api/admin/packs/:id` returns it for a `validated` import and as the
 * SCORM package of 0016 carries it in `content.json`. Every field of an
 * entry is present; the types name the members that the mapping reads.
 */
export interface PackPayload {
  key: string;
  title: string;
  locale: string;
  version: string;
  alignment?: "strict" | "warn";
  sources: Citation["source"][];
  glossary: GlossaryEntry[];
  segments: Segment[];
  stations: PayloadStation[];
  formats: PayloadFormat[];
  modules: PayloadModule[];
}

export interface PayloadStation {
  kind: Station["kind"];
  title: string;
  /** The module number of a module station. */
  module: number | null;
  config: Record<string, unknown> | null;
}

export interface PayloadFormat {
  key: string;
  title: string;
  description: string;
  phases: CompanionFormat["phases"];
  attendance_counts: boolean;
  objectives: string[];
}

export interface PayloadModule {
  number: number;
  title: string;
  summary: string;
  phases: ModuleView["phases"];
  single_path: boolean;
  lessons: PayloadLesson[];
  objectives: PayloadObjective[];
  rules: PayloadRule[];
  items: PayloadItem[];
  assessments: PayloadAssessment[];
}

export interface PayloadLesson {
  key: string;
  title: string;
  position: number;
  blocks: PayloadBlock[];
}

export interface PayloadBlock {
  kind: Block["kind"];
  body: string;
  provenance: Block["provenance"];
  collapsed_on: Block["collapsed_on"];
  placeholder_key: string | null;
  /** `source-key#locator` or `source-key`. */
  cite: string[];
  /**
   * The media attributes of a `figure` or a `video` (task 0018), `null`
   * for the other kinds and in a payload from before that task.
   */
  media: PayloadBlockMedia | null;
}

export interface PayloadObjective {
  key: string;
  statement: string;
  area: ObjectiveView["area"];
  depth: ObjectiveView["depth"];
  phase: ObjectiveView["phase"];
  domain: string | null;
  /** The keys of the teaching lessons of the module. */
  taught_in: string[];
}

export interface PayloadRule {
  number: number;
  statement: string;
  action: string;
  cite: string[];
}

export interface PayloadItem extends EvaluableItem {
  /** The lesson key of a practice item, `null` for an exam item. */
  lesson: string | null;
  stem: string;
  provenance: ItemView["provenance"];
  /** The keys of the objectives that the item serves. */
  objectives: string[];
  cite: string[];
  options: PayloadOption[];
}

export interface PayloadAssessment {
  key: string;
  title: string;
  kind: "practice" | "exam";
  counts_for_credential: boolean;
  max_wrong: number;
  core_required: boolean;
  /** The item keys in exam order. */
  items: string[];
}

/**
 * The ids of the views of a payload. A payload carries keys only, so the
 * mapping derives every id from keys: stable across loads of the same
 * payload, unique within it, and fit for an HTML `id` (keys hold `a-z`,
 * `0-9` and `-` only). Lessons and rules are keyed per module, every other
 * keyed row per pack.
 */
export const payloadIds = {
  program: (key: string) => `program-${key}`,
  module: (number: number) => `module-${number}`,
  lesson: (module: number, key: string) => `lesson-${module}-${key}`,
  block: (module: number, lesson: string, index: number) =>
    `block-${module}-${lesson}-${index + 1}`,
  rule: (module: number, number: number) => `rule-${module}-${number}`,
  item: (key: string) => `item-${key}`,
  assessment: (key: string) => `assessment-${key}`,
  format: (key: string) => `format-${key}`,
};

/** Item kinds with a correct answer: every kind except `poll`. */
const ANSWER_KINDS = new Set<ItemView["kind"]>([
  "single_choice",
  "multiple_choice",
  "slot_builder",
  "classification",
  "checklist_drill",
]);

const byKey = (a: { key: string }, b: { key: string }) =>
  a.key < b.key ? -1 : a.key > b.key ? 1 : 0;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const stringAt = (config: unknown, key: string): string | null => {
  const value = isRecord(config) ? config[key] : undefined;
  return typeof value === "string" ? value : null;
};

const recordsAt = (config: unknown, key: string) => {
  const value = isRecord(config) ? config[key] : undefined;
  return Array.isArray(value) ? value.filter(isRecord) : [];
};

const text = (value: unknown) => (typeof value === "string" ? value : "");

function citations(
  cites: readonly string[],
  sources: ReadonlyMap<string, Citation["source"]>,
): Citation[] {
  return cites
    .flatMap((cite) => {
      const split = cite.indexOf("#");
      const key = split === -1 ? cite : cite.slice(0, split);
      const locator = split === -1 ? null : cite.slice(split + 1);
      const source = sources.get(key);
      return source === undefined ? [] : [{ locator, source }];
    })
    .sort((a, b) =>
      (a.locator ?? "") !== (b.locator ?? "")
        ? (a.locator ?? "") < (b.locator ?? "")
          ? -1
          : 1
        : byKey(a.source, b.source),
    );
}

function stationView(station: PayloadStation, index: number): Station {
  const config = station.config ?? {};
  return {
    position: index + 1,
    kind: station.kind,
    title: station.title,
    module_id:
      station.kind === "module" && station.module !== null
        ? payloadIds.module(station.module)
        : null,
    question: stringAt(config, "question"),
    intro: stringAt(config, "intro"),
    questions: recordsAt(config, "questions").map((question) => ({
      key: text(question.key),
      kind: question.kind as Station["questions"][number]["kind"],
      label: text(question.label),
      options: recordsAt(question, "options").map((option) => ({
        key: text(option.key),
        label: text(option.label),
      })),
    })),
  };
}

function itemView(
  item: PayloadItem,
  module: PayloadModule,
  known: ReadonlySet<string>,
): ItemView {
  const config = item.config;
  const choices = (map: unknown, key: string) =>
    recordsAt(map, key).map((entry) => ({
      key: text(entry.key),
      label: text(entry.label),
    }));
  return {
    id: payloadIds.item(item.key),
    key: item.key,
    kind: item.kind,
    stem: item.stem,
    provenance: item.provenance,
    lesson_id:
      item.lesson === null
        ? null
        : payloadIds.lesson(module.number, item.lesson),
    objective_keys: [...new Set(item.objectives)]
      .filter((key) => known.has(key))
      .sort(),
    options:
      item.kind === "single_choice" ||
      item.kind === "multiple_choice" ||
      item.kind === "poll"
        ? item.options.map(({ key, label }) => ({ key, label: label ?? "" }))
        : [],
    slots:
      item.kind === "slot_builder"
        ? recordsAt(config, "slots").map((slot) => ({
            key: text(slot.key),
            label: text(slot.label),
            options: choices(slot, "options"),
          }))
        : [],
    cases:
      item.kind === "classification"
        ? recordsAt(config, "cases").map((entry) => ({
            key: text(entry.key),
            text: text(entry.text),
          }))
        : [],
    categories:
      item.kind === "classification" ? choices(config, "categories") : [],
    checks:
      item.kind === "checklist_drill"
        ? recordsAt(config, "checks").map((check) => ({
            key: text(check.key),
            label: text(check.label),
            required: check.required === true,
          }))
        : [],
  };
}

/**
 * The evidence of every objective of `payload` by objective key, after the
 * rule of 0008 step 13: every item that names the objective and is listed
 * by an assessment, every other item that names it and whose kind has a
 * correct answer (every kind except `poll`), ordered by item key, and then
 * every companion format with `attendance_counts: true` that names it,
 * ordered by format key. An item may name an objective of another module;
 * its evidence then belongs to that objective.
 */
function evidenceByObjective(
  payload: PackPayload,
): Map<string, ObjectiveView["evidence"]> {
  const listed = new Set(
    payload.modules.flatMap((module) =>
      module.assessments.flatMap((assessment) => assessment.items),
    ),
  );
  const items = payload.modules
    .flatMap((module) => module.items)
    .filter((item) => listed.has(item.key) || ANSWER_KINDS.has(item.kind))
    .sort(byKey);
  const formats = payload.formats
    .filter((format) => format.attendance_counts)
    .sort(byKey);

  const evidence = new Map<string, ObjectiveView["evidence"]>();
  const add = (key: string, entry: ObjectiveView["evidence"][number]) => {
    const entries = evidence.get(key) ?? [];
    if (!entries.some((other) => other.id === entry.id)) entries.push(entry);
    evidence.set(key, entries);
  };
  for (const item of items)
    for (const key of item.objectives)
      add(key, { kind: "item", id: payloadIds.item(item.key) });
  for (const format of formats)
    for (const key of format.objectives)
      add(key, { kind: "format", id: payloadIds.format(format.key) });
  return evidence;
}

function moduleView(
  payload: PackPayload,
  module: PayloadModule,
  sources: ReadonlyMap<string, Citation["source"]>,
  evidence: ReadonlyMap<string, ObjectiveView["evidence"]>,
  known: ReadonlySet<string>,
  resolveMedia: BlockMediaResolver,
): ModuleView {
  const lessons = [...module.lessons].sort((a, b) =>
    a.position !== b.position ? a.position - b.position : byKey(a, b),
  );
  const positions = new Map(
    lessons.map((lesson, index) => [lesson.key, index]),
  );
  const exams = module.assessments
    .filter((assessment) => assessment.kind === "exam")
    .sort(byKey);
  const examItems = new Set(exams.flatMap((exam) => exam.items));
  const items = new Map(module.items.map((item) => [item.key, item]));

  return {
    id: payloadIds.module(module.number),
    program_slug: payload.key,
    number: module.number,
    title: module.title,
    summary: module.summary,
    phases: module.phases,
    single_path: module.single_path,
    lessons: lessons.map((lesson): Lesson => ({
      id: payloadIds.lesson(module.number, lesson.key),
      key: lesson.key,
      position: lesson.position,
      title: lesson.title,
      blocks: lesson.blocks.map((block, index): Block => ({
        id: payloadIds.block(module.number, lesson.key, index),
        kind: block.kind,
        body: block.body,
        provenance: block.provenance,
        collapsed_on: block.collapsed_on,
        placeholder_key: block.placeholder_key,
        media: resolveMedia(block.kind, block.media),
        // The preview reads no policy; a placeholder block keeps its
        // own body with the placeholder badge.
        policy: null,
        citations: citations(block.cite, sources),
      })),
    })),
    rules: [...module.rules]
      .sort((a, b) => a.number - b.number)
      .map((rule): Rule => ({
        id: payloadIds.rule(module.number, rule.number),
        number: rule.number,
        statement: rule.statement,
        action: rule.action,
        citations: citations(rule.cite, sources),
      })),
    practice_items: module.items
      .filter((item) => !examItems.has(item.key))
      .map((item) => itemView(item, module, known)),
    exams: exams.map((exam) => ({
      id: payloadIds.assessment(exam.key),
      key: exam.key,
      title: exam.title,
      max_wrong: exam.max_wrong,
      counts_for_credential: exam.counts_for_credential,
      items: exam.items.flatMap((key) => {
        const item = items.get(key);
        return item === undefined ? [] : [itemView(item, module, known)];
      }),
    })),
    objectives: module.objectives.map((objective): ObjectiveView => ({
      key: objective.key,
      statement: objective.statement,
      area: objective.area,
      depth: objective.depth,
      phase: objective.phase,
      domain: objective.domain,
      lesson_ids: [...new Set(objective.taught_in)]
        .filter((key) => positions.has(key))
        .sort((a, b) => (positions.get(a) ?? 0) - (positions.get(b) ?? 0))
        .map((key) => payloadIds.lesson(module.number, key)),
      evidence: evidence.get(objective.key) ?? [],
    })),
  };
}

/**
 * Maps a pack payload to the `ProgramView` of the player, in the shape of
 * the learner views of 0009 (`EspalierWeb.CatalogJSON`): stations in file
 * order with their positions, segments, companion formats, one
 * `ModuleView` per module in number order and the glossary. Each module
 * view carries its objectives with `lesson_ids` (the teaching lessons in
 * lesson position order) and `evidence` (see `evidenceByObjective`), and
 * each item view its sorted `objective_keys`. Practice items are the items
 * of a module that no exam lists, in file order; exams are the assessments
 * of kind `exam`, by key, with their items in exam order. Blocks carry no
 * policy text. The SCORM runtimes of 0016 reuse this mapping on the module
 * payload of `content.json`, whose `modules` hold one module.
 *
 * A `figure` or a `video` block carries its `BlockMedia` (task 0018): its
 * `media/` paths resolve through `media`, the media object of
 * `GET /api/admin/packs/:id` or of `content.json`, and `policy`, the
 * allowlists of the installation, decides whether an external file or an
 * embed is available; without a policy every host is (see
 * `blockMediaResolver`).
 */
export function payloadToProgramView(
  payload: PackPayload,
  media: PackMedia = {},
  policy: MediaPolicy | null = null,
): ProgramView {
  const resolveMedia = blockMediaResolver(media, policy);
  const sources = new Map(
    payload.sources.map((source) => [source.key, source]),
  );
  const evidence = evidenceByObjective(payload);
  const known = new Set(
    payload.modules.flatMap((module) =>
      module.objectives.map((objective) => objective.key),
    ),
  );
  return {
    id: payloadIds.program(payload.key),
    slug: payload.key,
    title: payload.title,
    locale: payload.locale,
    pack_version: payload.version,
    stations: payload.stations.map(stationView),
    segments: payload.segments.map(
      ({ key, label, description, default_path }) => ({
        key,
        label,
        description,
        default_path,
      }),
    ),
    companion_formats: payload.formats.map((format): CompanionFormat => ({
      id: payloadIds.format(format.key),
      key: format.key,
      title: format.title,
      description: format.description,
      phases: format.phases,
      attendance_counts: format.attendance_counts,
    })),
    modules: [...payload.modules]
      .sort((a, b) => a.number - b.number)
      .map((module) =>
        moduleView(payload, module, sources, evidence, known, resolveMedia),
      ),
    glossary: [...payload.glossary]
      .sort((a, b) => (a.slug < b.slug ? -1 : a.slug > b.slug ? 1 : 0))
      .map(({ slug, label, short_text }) => ({ slug, label, short_text })),
  };
}

/**
 * True when `value` has the members of a pack payload that the mapping
 * needs at the top level. The admin preview checks the `payload` of an
 * import with it before it builds a runtime.
 */
export function isPackPayload(value: unknown): value is PackPayload {
  if (!isRecord(value)) return false;
  return (
    typeof value.key === "string" &&
    typeof value.title === "string" &&
    typeof value.locale === "string" &&
    typeof value.version === "string" &&
    ["sources", "glossary", "segments", "stations", "formats", "modules"].every(
      (member) => Array.isArray(value[member]),
    )
  );
}

/** An error answer in the shape of the platform's, without a request. */
function apiError(status: number, body: Record<string, unknown>): ApiError {
  return new ApiError(
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    }),
    body,
  );
}

const notFound = () => apiError(404, { error: "not_found" });

interface ItemEntry {
  item: PayloadItem;
  context: EvaluationContext;
  exam: boolean;
}

interface ExamEntry {
  assessment: PayloadAssessment;
  module: PayloadModule;
}

const copyState = (state: ResumeState): ResumeState => ({
  path: state.path,
  openedExplanations: [...state.openedExplanations],
  visitedStations: [...state.visitedStations],
  answeredItems: [...state.answeredItems],
  completedModules: [...state.completedModules],
  examOutcomes: { ...state.examOutcomes },
  evidencedObjectives: [...state.evidencedObjectives],
});

/**
 * The runtime of the admin preview (task 0015, step 9; README section 9):
 * it implements `Runtime` on a pack payload in memory and keeps its state in
 * memory, so the preview sends nothing to the server and writes no record.
 * Items are evaluated in the browser with `src/player/evaluate.ts`, the
 * port of the evaluator and the pass rule of 0009. The media of the blocks
 * resolve through `media` and `policy` (see `payloadToProgramView`).
 *
 * - `loadState` returns the state of the last `saveState` call, or `null`
 *   before the first call, always with an empty `evidencedObjectives`: the
 *   platform derives `evidenced` from the learner's records on the server
 *   (README domain rule 15), and the preview has none. A passed exam shows
 *   `evidenced` through `examOutcomes`, and an answered practice item
 *   `practised` through `answeredItems` (`objectiveStatus` of 0012 step 11).
 * - `submitItem` evaluates a practice item and rejects an exam item and an
 *   unknown id with 404 `not_found` and an answer that does not fit the item
 *   with 422 `invalid_answer`, as the platform does.
 * - `submitAssessment` evaluates every item of an exam and applies the pass
 *   rule; an answer set that misses an item or names another answers 422
 *   `validation_failed`.
 * - `completeModule` follows the platform rule of 0009 step 13: while an
 *   exam of the module with `counts_for_credential: true` has no passed
 *   attempt, it rejects with `AssessmentsOpenError`.
 */
export class StandaloneRuntime implements Runtime {
  readonly #payload: PackPayload;
  readonly #program: ProgramView;
  readonly #items = new Map<string, ItemEntry>();
  readonly #exams = new Map<string, ExamEntry>();
  readonly #attempts = new Map<string, number>();
  readonly #passed = new Set<string>();
  #state: ResumeState | null = null;

  constructor(
    payload: PackPayload,
    media: PackMedia = {},
    policy: MediaPolicy | null = null,
  ) {
    this.#payload = payload;
    this.#program = payloadToProgramView(payload, media, policy);
    for (const module of payload.modules) {
      const context: EvaluationContext = {
        rules: module.rules.map((rule) => ({
          id: payloadIds.rule(module.number, rule.number),
          number: rule.number,
          statement: rule.statement,
          action: rule.action,
        })),
        lessons: module.lessons.map((lesson) => ({
          id: payloadIds.lesson(module.number, lesson.key),
          key: lesson.key,
          position: lesson.position,
        })),
      };
      const examItems = new Set(
        module.assessments
          .filter((assessment) => assessment.kind === "exam")
          .flatMap((assessment) => assessment.items),
      );
      for (const item of module.items)
        this.#items.set(payloadIds.item(item.key), {
          item,
          context,
          exam: examItems.has(item.key),
        });
      for (const assessment of module.assessments)
        if (assessment.kind === "exam")
          this.#exams.set(payloadIds.assessment(assessment.key), {
            assessment,
            module,
          });
    }
  }

  async loadProgram(slug: string): Promise<ProgramView> {
    if (slug !== this.#payload.key) throw notFound();
    return this.#program;
  }

  async submitItem(itemId: string, answer: Answer): Promise<ItemFeedback> {
    const entry = this.#items.get(itemId);
    if (entry === undefined || entry.exam) throw notFound();
    if (!validateAnswer(entry.item, answer))
      throw apiError(422, { error: "invalid_answer" });
    return { item_id: itemId, ...evaluate(entry.item, answer, entry.context) };
  }

  async submitAssessment(
    assessmentId: string,
    answers: Record<string, Answer>,
  ): Promise<AttemptResult> {
    const exam = this.#exams.get(assessmentId);
    if (exam === undefined) throw notFound();
    const entries = exam.assessment.items.flatMap((key) => {
      const entry = this.#items.get(payloadIds.item(key));
      return entry === undefined ? [] : [{ id: payloadIds.item(key), entry }];
    });
    const ids = new Set(entries.map(({ id }) => id));
    const given = Object.keys(answers);
    if (given.length !== ids.size || !given.every((id) => ids.has(id)))
      throw apiError(422, {
        error: "validation_failed",
        fields: { answers: ["incomplete"] },
      });
    if (
      !entries.every(({ id, entry }) => validateAnswer(entry.item, answers[id]))
    )
      throw apiError(422, {
        error: "validation_failed",
        fields: { answers: ["invalid"] },
      });

    const results = entries.map(({ id, entry }): ItemFeedback => ({
      item_id: id,
      ...evaluate(entry.item, answers[id], entry.context),
    }));
    const graded = entries.map(({ entry }, index) => ({
      core: entry.item.core === true,
      correct: results[index].correct,
    }));
    const outcome: ExamOutcome = passRule(graded, exam.assessment);
    const number = (this.#attempts.get(assessmentId) ?? 0) + 1;
    this.#attempts.set(assessmentId, number);
    if (outcome === "passed") this.#passed.add(assessmentId);

    return {
      id: `${assessmentId}-attempt-${number}`,
      assessment_id: assessmentId,
      number,
      submitted_at: new Date(Math.floor(Date.now() / 1000) * 1000)
        .toISOString()
        .replace(".000Z", "Z"),
      wrong_count: wrongCount(graded),
      core_failed: coreFailed(graded),
      outcome,
      results,
    };
  }

  async completeModule(moduleId: string): Promise<void> {
    const module = this.#payload.modules.find(
      (entry) => payloadIds.module(entry.number) === moduleId,
    );
    if (module === undefined) throw notFound();
    const open = module.assessments
      .filter(
        (assessment) =>
          assessment.kind === "exam" &&
          assessment.counts_for_credential &&
          !this.#passed.has(payloadIds.assessment(assessment.key)),
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
  }

  async loadState(): Promise<ResumeState | null> {
    if (this.#state === null) return null;
    return { ...copyState(this.#state), evidencedObjectives: [] };
  }

  async saveState(state: ResumeState): Promise<void> {
    this.#state = copyState(state);
  }
}

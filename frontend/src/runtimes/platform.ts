import { api, type ApiClient } from "../api/client";
import { unwrap } from "../api/errors";
import type { components } from "../api/schema";
import {
  AssessmentsOpenError,
  type Answer,
  type AttemptResult,
  type ItemFeedback,
  type OpenAssessment,
  type Path,
  type ProgramView,
  type ResumeState,
  type Runtime,
} from "../player/runtime";

type Progress = components["schemas"]["Progress"];

/** The storage that `PlatformRuntime` uses; the tests pass one in memory. */
export interface PlayerStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

/** The members of the browser entry besides `v`. */
interface Entry {
  openedExplanations: string[];
  visitedStations: number[];
  answeredItems: string[];
}

// Version 2 adds the owner tag `o`. An entry of version 1 carries no owner,
// so it is read as empty and replaced on the next save.
const ENTRY_VERSION = 2;

/** The `localStorage` key of the resume entry of a program. */
export const playerStorageKey = (slug: string) => `espalier.player.${slug}`;

const strings = (value: unknown): string[] =>
  Array.isArray(value)
    ? value.filter((entry): entry is string => typeof entry === "string")
    : [];

const positions = (value: unknown): number[] =>
  Array.isArray(value)
    ? value.filter((entry): entry is number => Number.isInteger(entry))
    : [];

/**
 * The owner tag of the entry of an enrollment: the first 16 hexadecimal
 * digits of the SHA-256 digest of the enrollment id. An enrollment belongs
 * to one person and one program, so the tag tells whose entry it is, and it
 * reveals neither the enrollment nor the person. It is `null` where the
 * browser offers no digest: `crypto.subtle` needs a secure context.
 */
export async function entryOwner(enrollmentId: string): Promise<string | null> {
  try {
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(`espalier.player:${enrollmentId}`),
    );
    return Array.from(new Uint8Array(digest).slice(0, 8), (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");
  } catch {
    return null;
  }
}

/**
 * Reads the entry of `owner`. A missing, unreadable or malformed entry, one
 * of another version, and one of another owner yield empty lists, and so
 * does every entry while the owner is unknown.
 */
function parseEntry(raw: string | null, owner: string | null): Entry {
  const empty = {
    openedExplanations: [],
    visitedStations: [],
    answeredItems: [],
  };
  if (raw === null || owner === null) return empty;
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return empty;
  }
  if (typeof value !== "object" || value === null || Array.isArray(value))
    return empty;
  const entry = value as Record<string, unknown>;
  if (entry.v !== ENTRY_VERSION || entry.o !== owner) return empty;
  return {
    openedExplanations: strings(entry.openedExplanations),
    visitedStations: positions(entry.visitedStations),
    answeredItems: strings(entry.answeredItems),
  };
}

const unique = <T>(list: T[]) => [...new Set(list)];

function isAssessmentsOpen(
  body: unknown,
): body is { error: "assessments_open"; assessments: unknown[] } {
  return (
    typeof body === "object" &&
    body !== null &&
    "error" in body &&
    body.error === "assessments_open" &&
    "assessments" in body &&
    Array.isArray(body.assessments)
  );
}

/** Copies the members of each open exam, so no other key of the body passes on. */
function openAssessments(entries: unknown[]): OpenAssessment[] {
  return entries.flatMap((entry) => {
    if (typeof entry !== "object" || entry === null) return [];
    const { id, key, title } = entry as Record<string, unknown>;
    return typeof id === "string" &&
      typeof key === "string" &&
      typeof title === "string"
      ? [{ id, key, title }]
      : [];
  });
}

/**
 * The runtime of the platform build: it reaches the learner routes of 0009
 * through the API client of 0010 and keeps the browser part of the resume
 * state in the `localStorage` entry `espalier.player.<program slug>`
 * (README section 10). This module is the only one of the SPA that reads or
 * writes that key.
 *
 * The entry holds `v`, the owner tag `o` (`entryOwner`), `openedExplanations`
 * (block ids), `visitedStations` (station positions) and, while the progress
 * answer holds no ids of answered items (`TRACKING_DETAIL=minimal`),
 * `answeredItems` (item ids). The key names the program only, so the people
 * who sign in on one browser share it: the runtime reads an entry only when
 * its owner tag belongs to the enrollment of the signed-in person, and the
 * next save replaces the entry of another person. The entry never holds an
 * answer, a correctness, an exam result, an objective key or status, a
 * person's data or a timestamp, and the runtime sends none of it to the
 * server (ASVS 14.3.3).
 */
export class PlatformRuntime implements Runtime {
  readonly #slug: string;
  readonly #client: ApiClient;
  readonly #storage: PlayerStorage | undefined;
  #enrollment: { id: string; path: Path } | null = null;
  /** The owner tag of the enrollment; `null` before `loadState` or without a digest. */
  #owner: string | null = null;
  /**
   * Whether the last progress answer held the ids of answered items
   * (`TRACKING_DETAIL=standard`); `null` before the first answer.
   */
  #serverTracksAnswers: boolean | null = null;
  /** The saves run one after the other, so a path change cannot overtake another. */
  #saving: Promise<void> = Promise.resolve();

  constructor(
    slug: string,
    {
      client = api,
      storage,
    }: { client?: ApiClient; storage?: PlayerStorage } = {},
  ) {
    this.#slug = slug;
    this.#client = client;
    this.#storage = storage;
  }

  async loadProgram(slug: string): Promise<ProgramView> {
    const client = this.#client;
    const { modules: summaries, ...program } = unwrap(
      await client.GET("/api/programs/{slug}", { params: { path: { slug } } }),
    );
    const [modules, glossary] = await Promise.all([
      Promise.all(
        summaries.map(async ({ id }) =>
          unwrap(
            await client.GET("/api/modules/{id}", { params: { path: { id } } }),
          ),
        ),
      ),
      client
        .GET("/api/programs/{slug}/glossary", { params: { path: { slug } } })
        .then(unwrap),
    ]);
    return { ...program, modules, glossary: glossary.terms };
  }

  async submitItem(itemId: string, answer: Answer): Promise<ItemFeedback> {
    return unwrap(
      await this.#client.POST("/api/items/{id}/responses", {
        params: { path: { id: itemId } },
        body: { answer },
      }),
    );
  }

  async submitAssessment(
    assessmentId: string,
    answers: Record<string, Answer>,
  ): Promise<AttemptResult> {
    return unwrap(
      await this.#client.POST("/api/assessments/{id}/attempts", {
        params: { path: { id: assessmentId } },
        body: { answers },
      }),
    );
  }

  async completeModule(moduleId: string): Promise<void> {
    const result = await this.#client.POST("/api/modules/{id}/completion", {
      params: { path: { id: moduleId } },
    });
    if (result.response.status === 409 && isAssessmentsOpen(result.error))
      throw new AssessmentsOpenError(openAssessments(result.error.assessments));
    unwrap(result);
  }

  /**
   * Reads the progress and creates the enrollment on the full path when the
   * learner has none (0014 adds the self-assessment that preselects the
   * path). Path, completed modules, exam outcomes and evidenced objectives
   * come from the server; opened explanations and visited stations from the
   * entry; answered items from the server with `TRACKING_DETAIL=standard`
   * and from the entry with `minimal`.
   */
  async loadState(): Promise<ResumeState> {
    let progress = await this.#progress();
    let enrollment = progress.enrollment;
    if (enrollment === null) {
      const created = await this.#client.POST("/api/enrollments", {
        body: { program_slug: this.#slug, path: "full" },
      });
      // Two first enrollments at once (two tabs) answer 422 for the
      // second; the enrollment of the first then exists.
      if (created.response.status === 422) {
        progress = await this.#progress();
        if (progress.enrollment === null) unwrap(created);
        enrollment = progress.enrollment;
      } else {
        enrollment = unwrap(created);
      }
    }
    if (enrollment === null) throw new Error("No enrollment");
    this.#enrollment = { id: enrollment.id, path: enrollment.path };
    this.#owner = await entryOwner(enrollment.id);

    // Without an owner tag, the runtime does not touch the entry at all.
    const entry = parseEntry(
      this.#owner === null ? null : this.#read(),
      this.#owner,
    );
    const answeredItems = progress.answered_item_ids;
    return {
      path: enrollment.path,
      openedExplanations: entry.openedExplanations,
      visitedStations: entry.visitedStations,
      answeredItems:
        answeredItems === undefined ? entry.answeredItems : [...answeredItems],
      completedModules: [...progress.completed_module_ids],
      examOutcomes: Object.fromEntries(
        progress.exams.map(({ assessment_id, outcome }) => [
          assessment_id,
          outcome,
        ]),
      ),
      evidencedObjectives: progress.objectives
        .filter(({ status }) => status === "evidenced")
        .map(({ key }) => key),
    };
  }

  /**
   * Writes the entry and, when the path differs from the path of the
   * enrollment, sends `PATCH /api/enrollments/:id`, which marks the choice
   * as manual. `completedModules`, `examOutcomes` and `evidencedObjectives`
   * stay out of the entry. Without an owner tag, nothing is written, and the
   * browser part of the state lasts for this visit only.
   */
  saveState(state: ResumeState): Promise<void> {
    const save = this.#saving.then(() => this.#save(state));
    this.#saving = save.catch(() => undefined);
    return save;
  }

  async #save(state: ResumeState): Promise<void> {
    const owner = this.#owner;
    if (owner !== null) {
      const entry: Record<string, unknown> = {
        v: ENTRY_VERSION,
        o: owner,
        openedExplanations: unique(state.openedExplanations),
        visitedStations: unique(state.visitedStations),
      };
      if (this.#serverTracksAnswers === false)
        entry.answeredItems = unique(state.answeredItems);
      this.#write(JSON.stringify(entry));
    }

    const enrollment = this.#enrollment;
    if (enrollment === null || state.path === enrollment.path) return;
    const updated = unwrap(
      await this.#client.PATCH("/api/enrollments/{id}", {
        params: { path: { id: enrollment.id } },
        body: { path: state.path },
      }),
    );
    this.#enrollment = { id: updated.id, path: updated.path };
  }

  async #progress(): Promise<Progress> {
    const progress = unwrap(
      await this.#client.GET("/api/me/progress", {
        params: { query: { program: this.#slug } },
      }),
    );
    this.#serverTracksAnswers = progress.answered_item_ids !== undefined;
    return progress;
  }

  // Every access sits in try/catch: a browser with blocked storage throws
  // on `localStorage` itself, and the player then keeps its state for this
  // visit only.
  #read(): string | null {
    try {
      return (this.#storage ?? localStorage).getItem(
        playerStorageKey(this.#slug),
      );
    } catch {
      return null;
    }
  }

  #write(value: string): void {
    try {
      (this.#storage ?? localStorage).setItem(
        playerStorageKey(this.#slug),
        value,
      );
    } catch {
      // The state stays in React state for this visit.
    }
  }
}

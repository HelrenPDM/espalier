import { describe, expect, test } from "vitest";
import { IDS, programFixture } from "../../test/player";
import {
  emptyResumeState,
  type ObjectiveView,
  type ProgramView,
  type ResumeState,
} from "../runtime";
import { objectiveStatus, statusCounts } from "./status";

/** The objective `key` of the fixture program. */
function objectiveOf(program: ProgramView, key: string): ObjectiveView {
  const objective = program.modules
    .flatMap((module) => module.objectives)
    .find((entry) => entry.key === key);
  if (objective === undefined) throw new Error(`fixture lacks ${key}`);
  return objective;
}

const state = (overrides: Partial<ResumeState> = {}): ResumeState => ({
  ...emptyResumeState("full"),
  ...overrides,
});

describe("objectiveStatus", () => {
  test("a key in evidencedObjectives gives evidenced", () => {
    const program = programFixture();
    const current = state({ evidencedObjectives: ["m1-subject-evidenced"] });

    expect(
      objectiveStatus(
        objectiveOf(program, "m1-subject-evidenced"),
        program,
        current,
      ),
    ).toBe("evidenced");
    expect(
      objectiveStatus(
        objectiveOf(program, "m1-method-practice"),
        program,
        current,
      ),
    ).toBe("open");
  });

  test("a passed exam that holds an evidence item of the objective gives evidenced, failed_core gives open", () => {
    const program = programFixture();
    const objective = objectiveOf(program, "m1-subject-exam");
    expect(objective.evidence).toContainEqual({
      kind: "item",
      id: IDS.examItem1,
    });

    expect(
      objectiveStatus(
        objective,
        program,
        state({ examOutcomes: { [IDS.exam]: "passed" } }),
      ),
    ).toBe("evidenced");
    expect(
      objectiveStatus(
        objective,
        program,
        state({ examOutcomes: { [IDS.exam]: "failed_core" } }),
      ),
    ).toBe("open");
    expect(
      objectiveStatus(
        objective,
        program,
        state({ examOutcomes: { [IDS.exam]: "failed_errors" } }),
      ),
    ).toBe("open");
  });

  test("a passed exam does not show an objective whose evidence it lacks", () => {
    const program = programFixture();

    expect(
      objectiveStatus(
        objectiveOf(program, "m1-method-practice"),
        program,
        state({ examOutcomes: { [IDS.exam]: "passed" } }),
      ),
    ).toBe("open");
  });

  test("an answered practice item whose objective_keys hold the key gives practised", () => {
    const program = programFixture();

    expect(
      objectiveStatus(
        objectiveOf(program, "m1-method-practice"),
        program,
        state({ answeredItems: [IDS.multipleChoice] }),
      ),
    ).toBe("practised");
  });

  test("an answered practice item of another module gives practised", () => {
    const program = programFixture();
    const [, module2] = program.modules;
    const slotBuilder = module2.practice_items.find(
      (entry) => entry.id === IDS.slotBuilder,
    );
    if (slotBuilder === undefined) throw new Error("fixture lacks the item");
    slotBuilder.objective_keys = ["m2-subject-prompt", "m1-method-practice"];
    const objective = objectiveOf(program, "m1-method-practice");
    expect(program.modules[0].objectives).toContain(objective);

    expect(
      objectiveStatus(
        objective,
        program,
        state({ answeredItems: [IDS.slotBuilder] }),
      ),
    ).toBe("practised");
  });

  test("an answered item that names another objective gives open", () => {
    const program = programFixture();

    expect(
      objectiveStatus(
        objectiveOf(program, "m1-method-practice"),
        program,
        state({ answeredItems: [IDS.singleChoice, IDS.slotBuilder] }),
      ),
    ).toBe("open");
  });

  test("an answered exam item counts as no practice", () => {
    const program = programFixture();

    expect(
      objectiveStatus(
        objectiveOf(program, "m1-subject-exam"),
        program,
        state({ answeredItems: [IDS.examItem1, IDS.examItem2] }),
      ),
    ).toBe("open");
  });

  test("an objective with evidence and an answered practice item gives evidenced", () => {
    const program = programFixture();

    expect(
      objectiveStatus(
        objectiveOf(program, "m1-method-practice"),
        program,
        state({
          evidencedObjectives: ["m1-method-practice"],
          answeredItems: [IDS.multipleChoice],
        }),
      ),
    ).toBe("evidenced");
  });

  test("an objective whose only evidence is a format gives open while evidencedObjectives lacks its key", () => {
    const program = programFixture();
    const objective = objectiveOf(program, "m1-self-format");
    expect(objective.evidence).toEqual([{ kind: "format", id: IDS.workshop }]);
    const busy = state({
      answeredItems: program.modules.flatMap((module) =>
        module.practice_items.map((entry) => entry.id),
      ),
      examOutcomes: { [IDS.exam]: "passed" },
      evidencedObjectives: ["m1-social-format"],
    });

    expect(objectiveStatus(objective, program, busy)).toBe("open");
    expect(
      objectiveStatus(objective, program, {
        ...busy,
        evidencedObjectives: ["m1-self-format"],
      }),
    ).toBe("evidenced");
  });

  test("reads only its arguments and changes none of them", () => {
    const program = Object.freeze(programFixture());
    const current = Object.freeze(
      state({
        answeredItems: [IDS.multipleChoice],
        examOutcomes: { [IDS.exam]: "passed" },
      }),
    );
    const before = structuredClone({ program, current });

    expect(
      program.modules[0].objectives.map((objective) =>
        objectiveStatus(objective, program, current),
      ),
    ).toEqual(["open", "evidenced", "practised", "open", "open"]);
    expect({ program, current }).toEqual(before);
  });
});

describe("statusCounts", () => {
  test("counts the objectives per status", () => {
    const program = programFixture();

    expect(
      statusCounts(
        program.modules[0].objectives,
        program,
        state({
          evidencedObjectives: ["m1-subject-evidenced"],
          examOutcomes: { [IDS.exam]: "passed" },
          answeredItems: [IDS.multipleChoice],
        }),
      ),
    ).toEqual({ evidenced: 2, practised: 1, open: 2 });
  });
});

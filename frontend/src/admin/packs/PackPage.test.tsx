import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type {
  AlignmentMatrixRow,
  PackDiff,
  PackImport,
} from "../../api/admin/packs";
import { AREAS, DEPTHS } from "../../player/objectives/labels";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { PackPage } from "./PackPage";

/**
 * Task 0015 step 11: the section "Alignment" of the pack page from a
 * hand-written answer of `GET /api/admin/packs/:id` with one module, twelve
 * matrix rows, one error and one warning. The tables show every row with
 * the area and depth labels of 0012 step 11 and `-` for an empty list,
 * both findings show file, line and check number, and "Publish" stays
 * disabled with a sentence naming the reason; axe reports no violation.
 * With the error removed and the status `validated`, "Publish" is enabled,
 * and its dialog lists the diff, the changed fields of each changed
 * objective and the number of warnings, and shows the findings of a 409
 * `alignment_errors` answer.
 */
const ID = "00000000-0000-4000-8000-000000000501";
const PATH = `/api/admin/packs/${ID}`;

const author = signedInPayload("mfa", { roles: ["learner", "author"] });

/** Twelve rows of module 1; the first row carries entries in every column. */
function matrix(): AlignmentMatrixRow[] {
  return AREAS.flatMap((area) =>
    DEPTHS.map((depth): AlignmentMatrixRow => ({
      module: 1,
      area,
      depth,
      objectives: [],
      lessons: [],
      evidence: [],
      elsewhere: null,
    })),
  ).map((row, index) =>
    index === 0
      ? {
          ...row,
          objectives: ["m1-subject-know"],
          lessons: ["01-basics", "02-sources"],
          evidence: ["item:m1-exam-1", "format:workshop"],
        }
      : row.area === "self"
        ? { ...row, elsewhere: "format:workshop" }
        : row,
  );
}

const error = {
  file: "modules/01-basics/items.yaml",
  line: 14,
  check: 2,
  module: 1,
  key: "m1-exam-1",
  message: "the exam item `m1-exam-1` names no objective",
};

const warning = {
  file: "modules/01-basics/objectives.yaml",
  line: 9,
  check: 4,
  module: 1,
  key: "m1-method-release",
  message: "no evidence fits the depth `know`; found checklist_drill",
};

function pack(overrides: Partial<PackImport> = {}): PackImport {
  return {
    id: ID,
    status: "failed",
    pack_key: "demo",
    pack_version: "1.4.0",
    inserted_at: "2026-10-12T09:30:00Z",
    published_at: null,
    payload: null,
    report: {
      errors: [
        error,
        {
          file: "modules/01-basics/lessons/01-basics.md",
          line: 3,
          message: "unknown glossary term `missing`",
        },
      ],
      warnings: [warning],
    },
    alignment: {
      mode: "strict",
      matrix: matrix(),
      errors: [error],
      warnings: [warning],
    },
    ...overrides,
  };
}

/** The same pack, publishable: status `validated` and no alignment error. */
const publishable = (): PackImport =>
  pack({
    status: "validated",
    payload: { key: "demo" },
    report: { errors: [], warnings: [warning] },
    alignment: {
      mode: "strict",
      matrix: matrix(),
      errors: [],
      warnings: [warning],
    },
  });

const emptyKind = { added: [], changed: [], archived: [] };

const diff: PackDiff = {
  modules: emptyKind,
  lessons: { added: ["03-new"], changed: [], archived: [] },
  learning_objectives: {
    added: ["m1-new"],
    changed: ["m1-subject-know"],
    archived: ["m1-old"],
    changed_fields: { "m1-subject-know": ["depth", "taught_in"] },
  },
  items: { added: [], changed: ["m1-exam-1"], archived: [] },
  rules: emptyKind,
  assessments: emptyKind,
  qualifications: emptyKind,
  formats: emptyKind,
  sources: emptyKind,
  segments: emptyKind,
  glossary_terms: emptyKind,
};

function renderPage(body: PackImport, responses: StubResponses = {}) {
  return renderWithProviders(<PackPage />, {
    route: `/admin/packs/${ID}`,
    path: "/admin/packs/:id",
    session: author,
    responses: { [`GET ${PATH}`]: { status: 200, body }, ...responses },
  });
}

const matrixTable = () =>
  screen.findByRole("table", { name: "Module 1, mode strict" });

const cellTexts = (row: HTMLElement) =>
  within(row)
    .getAllByRole("cell")
    .map((cell) => cell.textContent);

describe("the section Alignment", () => {
  test("shows twelve rows, both findings with file, line and check, and a disabled Publish button", async () => {
    const { container } = renderPage(pack());

    const table = await matrixTable();
    const [header, ...rows] = within(table).getAllByRole("row");
    expect(
      within(header)
        .getAllByRole("columnheader")
        .map((cell) => cell.textContent),
    ).toEqual([
      "Area",
      "Depth",
      "Objectives",
      "Lessons",
      "Evidence",
      "Elsewhere",
    ]);
    expect(rows).toHaveLength(12);
    expect(cellTexts(rows[0])).toEqual([
      "Subject competence",
      "Know",
      "m1-subject-know",
      "01-basics, 02-sources",
      "item:m1-exam-1, format:workshop",
      "-",
    ]);
    expect(cellTexts(rows[1])).toEqual([
      "Subject competence",
      "Apply",
      "-",
      "-",
      "-",
      "-",
    ]);
    expect(cellTexts(rows[6])).toEqual([
      "Self competence",
      "Know",
      "-",
      "-",
      "-",
      "format:workshop",
    ]);
    expect(rows.map((row) => cellTexts(row).slice(0, 2).join(", "))).toEqual(
      [
        "Subject competence",
        "Method competence",
        "Self competence",
        "Social competence",
      ].flatMap((area) =>
        ["Know", "Apply", "Judge"].map((depth) => `${area}, ${depth}`),
      ),
    );

    const errors = screen.getByRole("region", {
      name: "Alignment errors (1)",
    });
    const [errorItem] = within(errors).getAllByRole("listitem");
    expect(
      within(errorItem).getByText("modules/01-basics/items.yaml"),
    ).toBeInTheDocument();
    expect(within(errorItem).getByText("line 14")).toBeInTheDocument();
    expect(within(errorItem).getByText("check 2")).toBeInTheDocument();
    expect(within(errorItem).getByText("m1-exam-1")).toBeInTheDocument();
    expect(errorItem).toHaveTextContent(error.message);

    const warnings = screen.getByRole("region", {
      name: "Alignment warnings (1)",
    });
    const [warningItem] = within(warnings).getAllByRole("listitem");
    expect(
      within(warningItem).getByText("modules/01-basics/objectives.yaml"),
    ).toBeInTheDocument();
    expect(within(warningItem).getByText("line 9")).toBeInTheDocument();
    expect(within(warningItem).getByText("check 4")).toBeInTheDocument();

    // The validation report lists the entries without `check` only.
    const report = screen.getByRole("region", { name: "Validation report" });
    const [reportItem] = within(report).getAllByRole("listitem");
    expect(within(report).getAllByRole("listitem")).toHaveLength(1);
    expect(
      within(reportItem).getByText("modules/01-basics/lessons/01-basics.md"),
    ).toBeInTheDocument();
    expect(within(reportItem).getByText("line 3")).toBeInTheDocument();

    const publish = screen.getByRole("button", { name: "Publish" });
    expect(publish).toBeDisabled();
    expect(publish).toHaveAccessibleDescription(
      "The import failed validation and cannot be published.",
    );
    expect(screen.queryByRole("link", { name: "Preview" })).toBeNull();

    await expectNoAxeViolations(container);
  });

  test("names the alignment errors as the reason for a validated import that has them", async () => {
    renderPage(pack({ status: "validated", payload: { key: "demo" } }));

    const publish = await screen.findByRole("button", { name: "Publish" });
    expect(publish).toBeDisabled();
    expect(publish).toHaveAccessibleDescription(
      "The alignment checks report errors. Correct the pack and upload it again.",
    );
  });

  test("with the error removed and the status validated, Publish is enabled", async () => {
    const { container } = renderPage(publishable());

    await matrixTable();
    expect(
      screen.getByRole("heading", { name: "Alignment errors (0)" }),
    ).toBeInTheDocument();
    const publish = screen.getByRole("button", { name: "Publish" });
    expect(publish).toBeEnabled();
    expect(publish).not.toHaveAttribute("aria-describedby");
    expect(screen.getByRole("link", { name: "Preview" })).toHaveAttribute(
      "href",
      `/admin/packs/${ID}/preview`,
    );

    await expectNoAxeViolations(container);
  });

  test("without a stored payload, states that the import holds no matrix and lists the findings alone", async () => {
    renderPage(
      pack({
        alignment: {
          mode: null,
          matrix: null,
          errors: [error],
          warnings: [],
        },
      }),
    );

    expect(
      await screen.findByText(/This import holds no alignment matrix/),
    ).toBeInTheDocument();
    expect(screen.queryByRole("table")).toBeNull();
    expect(
      within(
        screen.getByRole("region", { name: "Alignment errors (1)" }),
      ).getAllByRole("listitem"),
    ).toHaveLength(1);
    expect(
      screen.getByRole("heading", { name: "Alignment warnings (0)" }),
    ).toBeInTheDocument();
  });

  test("shows one table per module", async () => {
    renderPage(
      pack({
        alignment: {
          mode: "warn",
          matrix: [
            ...matrix(),
            ...matrix().map((row) => ({ ...row, module: 2 })),
          ],
          errors: [],
          warnings: [],
        },
      }),
    );

    expect(
      await screen.findByRole("table", { name: "Module 1, mode warn" }),
    ).toBeInTheDocument();
    expect(
      within(
        screen.getByRole("table", { name: "Module 2, mode warn" }),
      ).getAllByRole("row"),
    ).toHaveLength(13);
  });
});

describe("the publication", () => {
  test("the dialog lists the diff per kind, the changed fields and the warnings, and publishes", async () => {
    const published = { ...publishable(), status: "published" as const };
    const { user, requests } = renderPage(publishable(), {
      [`GET ${PATH}/diff`]: { status: 200, body: diff },
      [`POST ${PATH}/publish`]: { status: 200, body: published },
    });

    await user.click(await screen.findByRole("button", { name: "Publish" }));
    const dialog = await screen.findByRole("dialog", {
      name: "Publish demo?",
    });
    const objectives = await within(dialog).findByRole("heading", {
      name: "Learning objectives",
    });
    const section = objectives.closest("section");
    if (section === null) throw new Error("no section");
    expect(section).toHaveTextContent("Added (1)m1-new");
    expect(section).toHaveTextContent("Archived (1)m1-old");
    expect(within(section).getByRole("listitem")).toHaveTextContent(
      "m1-subject-know (fields: depth, taught_in)",
    );
    expect(
      within(dialog).getByRole("heading", { name: "Lessons" }),
    ).toBeInTheDocument();
    expect(
      within(dialog).getByRole("heading", { name: "Items" }),
    ).toBeInTheDocument();
    expect(
      within(dialog).queryByRole("heading", { name: "Modules" }),
    ).toBeNull();
    expect(dialog).toHaveTextContent("Alignment warnings: 1.");
    await expectNoAxeViolations(document.body);

    await user.click(within(dialog).getByRole("button", { name: "Publish" }));

    expect(
      await screen.findByText("The pack is published."),
    ).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(requestsTo(requests, "POST", `${PATH}/publish`)).toHaveLength(1);
    expect(screen.getByRole("button", { name: "Publish" })).toBeDisabled();
    expect(
      screen.getByText("This import is already published."),
    ).toBeInTheDocument();
  });

  test("a 409 alignment_errors answer shows its findings in the dialog and leaves the import unpublished", async () => {
    const { user } = renderPage(publishable(), {
      [`GET ${PATH}/diff`]: { status: 200, body: diff },
      [`POST ${PATH}/publish`]: {
        status: 409,
        body: {
          error: "alignment_errors",
          findings: [
            {
              check: 2,
              module: 1,
              file: "items.yaml",
              key: "m1-exam-1",
              message: "the exam item `m1-exam-1` names no objective",
            },
          ],
        },
      },
    });

    await user.click(await screen.findByRole("button", { name: "Publish" }));
    const dialog = await screen.findByRole("dialog");
    await within(dialog).findByRole("heading", { name: "Learning objectives" });
    await user.click(within(dialog).getByRole("button", { name: "Publish" }));

    const alert = await within(dialog).findByText(
      /The publication was refused/,
    );
    const finding = within(dialog)
      .getAllByRole("listitem")
      .find((item) => item.textContent?.startsWith("items.yaml"));
    expect(alert).toBeInTheDocument();
    expect(finding).toHaveTextContent(
      "items.yaml, module 1, check 2, m1-exam-1: the exam item `m1-exam-1` names no objective",
    );
    expect(
      within(dialog).queryByRole("button", { name: "Publish" }),
    ).toBeNull();

    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(screen.getByRole("button", { name: "Publish" })).toBeEnabled();
    expect(screen.queryByText("The pack is published.")).toBeNull();
  });
});

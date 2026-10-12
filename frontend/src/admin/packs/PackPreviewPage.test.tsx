import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type { PackImport } from "../../api/admin/packs";
import type { PackPayload, PayloadItem } from "../../runtimes/standalone";
import { expectNoAxeViolations } from "../../test/axe";
import { renderWithProviders } from "../../test/render";
import { signedInPayload } from "../../test/session";
import { PackPreviewPage } from "./PackPreviewPage";

/**
 * Task 0015 step 11: "Preview" renders the player with `StandaloneRuntime`
 * on the payload of the import, below a visible "Preview" banner with the
 * count of blocks and items per provenance value. The player routes stay
 * below `/admin/packs/:id/preview`, so its links do not leave the preview,
 * and the module station lists the objectives of the topic. The player
 * sends no request to the server.
 */
const ID = "00000000-0000-4000-8000-000000000701";
const BASE = `/admin/packs/${ID}/preview`;
const author = signedInPayload("mfa", { roles: ["learner", "author"] });

const item = (
  overrides: Partial<PayloadItem> & Pick<PayloadItem, "key" | "kind">,
): PayloadItem => ({
  lesson: "intro",
  stem: `Stem of ${overrides.key}`,
  core: false,
  provenance: "invented",
  objectives: [],
  rules: [],
  reveals: [],
  cite: [],
  options: [],
  config: {},
  ...overrides,
});

const payload: PackPayload = {
  key: "preview-demo",
  title: "Working with text tools",
  locale: "en",
  version: "2.0.0",
  alignment: "strict",
  sources: [],
  glossary: [],
  segments: [],
  stations: [
    { kind: "overview", title: "Overview", module: null, config: {} },
    { kind: "module", title: "Checking claims", module: 1, config: {} },
  ],
  formats: [],
  modules: [
    {
      number: 1,
      title: "Checking claims",
      summary: "How to check a claim.",
      phases: ["understand"],
      single_path: false,
      lessons: [
        {
          key: "intro",
          title: "Why claims need checks",
          position: 1,
          blocks: [
            {
              kind: "text",
              body: "A claim needs a source.",
              provenance: "sourced",
              collapsed_on: [],
              placeholder_key: null,
              cite: [],
            },
            {
              kind: "example",
              body: "An invented example.",
              provenance: "invented",
              collapsed_on: [],
              placeholder_key: null,
              cite: [],
            },
            {
              kind: "callout",
              body: "An assumption.",
              provenance: "assumption",
              collapsed_on: [],
              placeholder_key: null,
              cite: [],
            },
          ],
        },
      ],
      objectives: [
        {
          key: "m1-subject-know",
          statement: "Name what makes a claim checkable.",
          area: "subject",
          depth: "know",
          phase: "understand",
          domain: null,
          taught_in: ["intro"],
        },
        {
          key: "m1-method-apply",
          statement: "Check a claim against a source.",
          area: "method",
          depth: "apply",
          phase: "apply",
          domain: null,
          taught_in: ["intro"],
        },
      ],
      rules: [],
      items: [
        item({
          key: "claim-choice",
          kind: "single_choice",
          objectives: ["m1-subject-know"],
          options: [
            { key: "a", label: "A source", correct: true, feedback: "Right." },
            { key: "b", label: "A feeling", correct: false, feedback: "No." },
          ],
        }),
        item({
          key: "claim-drill",
          kind: "checklist_drill",
          provenance: "sourced",
          objectives: ["m1-method-apply"],
          config: {
            checks: [{ key: "source", label: "Source named", required: true }],
          },
        }),
      ],
      assessments: [],
    },
  ],
};

const pack = (overrides: Partial<PackImport> = {}): PackImport => ({
  id: ID,
  status: "validated",
  pack_key: payload.key,
  pack_version: payload.version,
  inserted_at: "2026-10-12T09:30:00Z",
  published_at: null,
  payload: payload as unknown as PackImport["payload"],
  report: { errors: [], warnings: [] },
  alignment: { mode: "strict", matrix: [], errors: [], warnings: [] },
  ...overrides,
});

function renderPreview(body: PackImport, route = BASE) {
  return renderWithProviders(<PackPreviewPage />, {
    route,
    path: "/admin/packs/:id/preview/*",
    session: author,
    responses: { [`GET /api/admin/packs/${ID}`]: { status: 200, body } },
  });
}

describe("PackPreviewPage", () => {
  test("shows the banner with the provenance overview and opens the program below the preview", async () => {
    const { container, location, requests } = renderPreview(pack());

    const banner = await screen.findByRole("region", { name: "Preview" });
    expect(banner).toHaveTextContent(
      "Preview of Working with text tools, version 2.0.0",
    );
    const overview = within(banner).getByRole("table", {
      name: "Provenance overview",
    });
    const counts = within(overview)
      .getAllByRole("row")
      .slice(1)
      .map((row) =>
        [
          within(row).getByRole("rowheader").textContent,
          ...within(row)
            .getAllByRole("cell")
            .map((cell) => cell.textContent),
        ].join(" "),
      );
    expect(counts).toEqual([
      "Invented 1 1",
      "Sourced 1 1",
      "Vendor statement 0 0",
      "Assumption 1 0",
      "Placeholder 0 0",
    ]);

    expect(
      await screen.findByRole("heading", {
        level: 1,
        name: "Working with text tools",
      }),
    ).toBeInTheDocument();
    expect(location()).toBe(`${BASE}/programs/preview-demo`);
    const stations = screen.getByRole("link", { name: /Checking claims/ });
    expect(stations).toHaveAttribute(
      "href",
      `${BASE}/programs/preview-demo/stations/2`,
    );

    await expectNoAxeViolations(container);
    expect(requests.map((request) => request.path)).toEqual([
      `/api/admin/packs/${ID}`,
    ]);
  });

  test("the module station lists the objectives of the topic and evaluates answers in the browser", async () => {
    const { user, location, requests } = renderPreview(pack());

    await user.click(
      await screen.findByRole("link", { name: /Checking claims/ }),
    );
    await waitFor(() =>
      expect(location()).toBe(`${BASE}/programs/preview-demo/stations/2`),
    );
    const panel = await screen.findByRole("region", {
      name: "Objectives of this topic",
    });
    expect(panel).toHaveTextContent("Name what makes a claim checkable.");
    expect(panel).toHaveTextContent("Check a claim against a source.");

    await user.click(screen.getByRole("radio", { name: "A source" }));
    const [check] = screen.getAllByRole("button", { name: "Check answer" });
    await user.click(check);
    expect(await screen.findByText("Correct.")).toBeInTheDocument();

    expect(
      screen.getByRole("link", { name: "Back to Working with text tools" }),
    ).toHaveAttribute("href", `${BASE}/programs/preview-demo`);
    expect(requests.map((request) => request.path)).toEqual([
      `/api/admin/packs/${ID}`,
    ]);
  });

  test("an import without a payload shows a notice", async () => {
    renderPreview(pack({ status: "failed", payload: null }));

    expect(
      await screen.findByText(
        "This import holds no pack to preview. Only a validated import can be previewed.",
      ),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "Back to the import" }),
    ).toHaveAttribute("href", `/admin/packs/${ID}`);
  });
});

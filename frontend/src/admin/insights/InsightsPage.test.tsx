import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import { createMemoryRouter, Outlet, RouterProvider } from "react-router";
import { afterEach, describe, expect, test, vi } from "vitest";
import { ApiClientProvider } from "../../api/ApiClientProvider";
import { createApiClient } from "../../api/client";
import type { ProgramSummary } from "../../api/programs";
import type {
  CompetenceReport,
  CredentialReport,
  FormatReport,
  ItemReport,
  SelfAssessmentReport,
} from "../../api/reports";
import { createRoutes, appRoutes } from "../../app/router";
import { SessionContext } from "../../auth/SessionProvider";
import i18n from "../../i18n";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  stubFetch,
  type StubResponses,
} from "../../test/render";
import { sessionValue, signedInPayload } from "../../test/session";
import { InsightsPage } from "./InsightsPage";

/**
 * Task 0014 step 9 and the Acceptance line on suppressed cells: the reports
 * page `/admin/insights` for analysts. It picks a program from the
 * published programs and keeps the choice in `?program=SLUG`, shows one
 * table per report with the months as columns, renders a suppressed cell
 * as "fewer than N" with N from `min_group_size` of the answer, labels the
 * competence rows with area, depth and org unit, sets the bars from the
 * share or from the largest count of the table, gives pack text the
 * language of the program (from the list of published programs, and for a
 * program that the list lacks from the report), lists free-text answers,
 * and has loading,
 * error, not-found and empty states. The route renders the page for an
 * analyst through both guards; the 403 page for a learner and for an
 * author is covered in `src/app/guards.test.tsx`.
 */
const uuid = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

const programs: ProgramSummary[] = [
  { slug: "demo", title: "Demo-Programm", locale: "de" },
  { slug: "second", title: "Second program", locale: "en" },
];

const selfAssessment: SelfAssessmentReport = {
  locale: "de",
  min_group_size: 5,
  by_org_unit: false,
  months: ["2026-09-01", "2026-10-01"],
  rows: [
    {
      segment_key: "newcomer",
      label: "Einsteigerin oder Einsteiger",
      org_unit: null,
      cells: [{ count: 6, value: 6 }, { suppressed: true }],
    },
    {
      segment_key: "retired-segment",
      label: null,
      org_unit: null,
      cells: [
        { count: 12, value: 12 },
        { count: 9, value: 9 },
      ],
    },
  ],
};

const items: ItemReport = {
  locale: "de",
  min_group_size: 5,
  months: ["2026-10-01"],
  rows: [
    {
      item_id: uuid(31),
      key: "m1-sc-1",
      kind: "single_choice",
      module_number: 1,
      stem: "Welche Angabe gehört nicht in eine Anfrage?",
      cells: [{ count: 40, value: 0.625 }],
    },
    {
      item_id: uuid(32),
      key: "m1-mc-2",
      kind: "multiple_choice",
      module_number: 1,
      stem: "Welche Quellen prüfen Sie?",
      cells: [{ suppressed: true }],
    },
  ],
};

const competence: CompetenceReport = {
  locale: "de",
  min_group_size: 5,
  by_org_unit: true,
  months: ["2026-09-01", "2026-10-01"],
  rows: [
    {
      area: "subject",
      depth: "know",
      org_unit: "Newsroom",
      cells: [
        { count: 20, value: 0.75 },
        { count: 8, value: 0.5 },
      ],
    },
    {
      area: "subject",
      depth: "know",
      org_unit: null,
      cells: [{ suppressed: true }, { count: 5, value: 1 }],
    },
    {
      area: "method",
      depth: "apply",
      org_unit: "Newsroom",
      cells: [{ suppressed: true }, { suppressed: true }],
    },
  ],
};

const formats: FormatReport = {
  locale: "de",
  min_group_size: 5,
  formats: [
    {
      id: uuid(61),
      key: "workshop",
      title: "Praxis-Workshop",
      cell: { count: 7, value: 7 },
    },
    {
      id: uuid(62),
      key: "office-hours",
      title: "Sprechstunde",
      cell: { suppressed: true },
    },
  ],
};

// The body that `EspalierWeb.InsightsJSON.feedback_report/1` renders:
// `locale` and `min_group_size` at the top level and `free_text` with `count` and
// `answers` only. The generated type differs there (see `FeedbackReport` in
// `src/api/reports.ts`), so the fixture carries no type annotation.
const freeTextAnswers = [
  "Mehr Beispiele aus dem Alltag.",
  "Kürzere Module.",
  "Eine Übung mit eigenen Texten.",
  "Mehr Zeit für Fragen.",
  "Kürzere Module.",
];
const feedback = {
  locale: "de",
  min_group_size: 5,
  questions: [
    {
      key: "useful",
      kind: "single_choice",
      label: "Wie nützlich war das Programm?",
      choices: [
        {
          key: "very",
          label: "Sehr nützlich",
          cell: { count: 8, value: 8 },
        },
        { key: "little", label: "Wenig nützlich", cell: { suppressed: true } },
      ],
      free_text: null,
    },
    {
      key: "clarity",
      kind: "scale",
      label: "Wie verständlich waren die Texte?",
      choices: ["1", "2", "3", "4", "5"].map((key) => ({
        key,
        label: null,
        cell: key === "4" ? { count: 6, value: 6 } : { suppressed: true },
      })),
      free_text: null,
    },
    {
      key: "wish",
      kind: "free_text",
      label: "Was wünschen Sie sich?",
      choices: [],
      free_text: { count: 5, answers: freeTextAnswers },
    },
    {
      key: "missing",
      kind: "free_text",
      label: "Was hat gefehlt?",
      choices: [],
      free_text: { suppressed: true },
    },
  ],
};

const credentials: CredentialReport = {
  locale: "de",
  min_group_size: 5,
  qualifications: [
    {
      code: "basic",
      title: "Grundlagen",
      archived: false,
      statuses: [
        { status: "active", cell: { count: 5, value: 5 } },
        { status: "refresh_due", cell: { suppressed: true } },
        { status: "expired", cell: { suppressed: true } },
        { status: "revoked", cell: { suppressed: true } },
      ],
    },
    {
      code: "basic-2025",
      title: "Grundlagen 2025",
      archived: true,
      statuses: [
        { status: "active", cell: { suppressed: true } },
        { status: "refresh_due", cell: { suppressed: true } },
        { status: "expired", cell: { count: 10, value: 10 } },
        { status: "revoked", cell: { suppressed: true } },
      ],
    },
  ],
};

const REPORT_PATHS = [
  "/api/insights/self-assessment",
  "/api/insights/items",
  "/api/insights/competence",
  "/api/insights/formats",
  "/api/insights/feedback",
  "/api/insights/credentials",
] as const;

const responses = (overrides: StubResponses = {}): StubResponses => ({
  "GET /api/programs": { status: 200, body: { programs } },
  "GET /api/insights/self-assessment": { status: 200, body: selfAssessment },
  "GET /api/insights/items": { status: 200, body: items },
  "GET /api/insights/competence": { status: 200, body: competence },
  "GET /api/insights/formats": { status: 200, body: formats },
  "GET /api/insights/feedback": { status: 200, body: feedback },
  "GET /api/insights/credentials": { status: 200, body: credentials },
  ...overrides,
});

const analyst = signedInPayload("mfa", { roles: ["learner", "analyst"] });

function renderPage(route = "/admin/insights", overrides?: StubResponses) {
  return renderWithProviders(<InsightsPage />, {
    route,
    path: "/admin/insights",
    session: analyst,
    responses: responses(overrides),
  });
}

/**
 * Records the URL of every request that the API client builds. The stub
 * fetch of `renderWithProviders` records the path only, and the reports
 * name the program in the query.
 */
function recordRequestUrls(): string[] {
  const urls: string[] = [];
  const Base = globalThis.Request;
  vi.stubGlobal(
    "Request",
    class extends Base {
      constructor(input: RequestInfo | URL, init?: RequestInit) {
        super(input, init);
        urls.push(this.url);
      }
    },
  );
  return urls;
}

const programsOf = (urls: string[], path: string) =>
  urls
    .map((url) => new URL(url))
    .filter((url) => url.pathname === path)
    .map((url) => url.searchParams.get("program"));

const table = (name: string) => screen.findByRole("table", { name });

/** Expects `lang` on the pack text of every section that shows some. */
async function expectPackLang(lang: string) {
  await screen.findByRole("heading", {
    level: 4,
    name: "Was wünschen Sie sich?",
  });
  for (const text of [
    "Einsteigerin oder Einsteiger",
    "Welche Angabe gehört nicht in eine Anfrage?",
    "Praxis-Workshop",
    "Sehr nützlich",
    freeTextAnswers[0],
    "Grundlagen",
  ])
    for (const element of screen.getAllByText(text))
      expect(element, text).toHaveAttribute("lang", lang);
  expect(
    screen.getByRole("heading", { level: 4, name: "Was wünschen Sie sich?" }),
  ).toHaveAttribute("lang", lang);
  expect(
    within(await table("Feedback")).getByRole("rowheader", {
      name: "Wie nützlich war das Programm?",
    }).firstElementChild,
  ).toHaveAttribute("lang", lang);
}

/** The texts of the data cells in the row whose row header is `name`. */
function rowCells(scope: HTMLElement, name: string): string[] {
  const row = within(scope).getByRole("rowheader", { name }).closest("tr");
  if (row === null) throw new Error(`no row for ${name}`);
  return within(row)
    .getAllByRole("cell")
    .map((cell) => cell.textContent ?? "");
}

/** The width class of the bar in the cell at `index` of the row `name`. */
function barOf(scope: HTMLElement, name: string, index: number) {
  const row = within(scope).getByRole("rowheader", { name }).closest("tr");
  const cell = row?.querySelectorAll("td")[index];
  return cell?.querySelector("[data-bar]")?.getAttribute("data-bar") ?? null;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("the reports page", () => {
  test("shows the page title, the program picker and one table per report", async () => {
    renderPage();

    expect(
      screen.getByRole("heading", { level: 1, name: "Reports" }),
    ).toBeInTheDocument();
    const picker = await screen.findByRole("combobox", { name: "Program" });
    expect(picker).toHaveValue("demo");
    expect(
      within(picker)
        .getAllByRole("option")
        .map((option) => [option.textContent, option.getAttribute("lang")]),
    ).toEqual([
      ["Demo-Programm", "de"],
      ["Second program", "en"],
    ]);

    for (const name of [
      "Self-assessment",
      "Practice items",
      "Competence areas",
      "Companion formats",
      "Feedback",
      "Credentials",
    ]) {
      expect(await table(name)).toBeInTheDocument();
      expect(
        screen.getByRole("heading", { level: 2, name }),
      ).toBeInTheDocument();
      expect(screen.getByRole("region", { name })).toHaveAttribute(
        "tabindex",
        "0",
      );
    }
    expect(await table("Self-assessment")).toHaveAccessibleDescription(
      "The number of answers per segment and month.",
    );
  });

  test("renders a suppressed cell as 'fewer than 5' and shows the months as columns", async () => {
    renderPage();

    const segments = await table("Self-assessment");
    expect(
      within(segments)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual(["Segment", "September 2026", "October 2026"]);
    expect(rowCells(segments, "Einsteigerin oder Einsteiger")).toEqual([
      "6",
      "fewer than 5",
    ]);
    // A segment that the program no longer names shows its key.
    expect(rowCells(segments, "retired-segment")).toEqual(["12", "9"]);
    expect(
      within(segments).getByText("Einsteigerin oder Einsteiger"),
    ).toHaveAttribute("lang", "de");
    // The bars of a count report scale to the largest count of the table.
    expect(barOf(segments, "Einsteigerin oder Einsteiger", 0)).toBe("w-10/20");
    expect(barOf(segments, "Einsteigerin oder Einsteiger", 1)).toBeNull();
    expect(barOf(segments, "retired-segment", 0)).toBe("w-full");
    expect(barOf(segments, "retired-segment", 1)).toBe("w-15/20");
    const fill = segments.querySelector('[data-bar="w-15/20"] > div');
    expect(fill).toHaveClass("w-15/20");
    expect(fill?.parentElement).toHaveAttribute("aria-hidden", "true");
    expect(fill?.getAttribute("style")).toBeNull();
  });

  test("shows the share correct and the attempts per item and month", async () => {
    renderPage();

    const itemTable = await table("Practice items");
    expect(
      within(itemTable)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual(["Module", "Item", "October 2026"]);
    const stem = within(itemTable).getByText(
      "Welche Angabe gehört nicht in eine Anfrage?",
    );
    expect(stem).toHaveAttribute("lang", "de");
    const name = "Welche Angabe gehört nicht in eine Anfrage? m1-sc-1";
    expect(rowCells(itemTable, name)).toEqual(["1", "63%40 attempts"]);
    // The bar of a share report takes the width of the share.
    expect(barOf(itemTable, name, 1)).toBe("w-13/20");
    expect(rowCells(itemTable, "Welche Quellen prüfen Sie? m1-mc-2")).toEqual([
      "1",
      "fewer than 5",
    ]);
  });

  test("labels each competence row with its area, depth and org unit", async () => {
    renderPage();

    const areas = await table("Competence areas");
    expect(
      within(areas)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual([
      "Competence area",
      "Depth",
      "Org unit",
      "September 2026",
      "October 2026",
    ]);
    const rows = within(areas).getAllByRole("row").slice(1);
    expect(
      rows.map((row) =>
        within(row)
          .getAllByRole("rowheader")
          .map((header) => header.textContent),
      ),
    ).toEqual([
      ["Subject competence", "Know", "Newsroom"],
      ["Subject competence", "Know", "No org unit"],
      ["Method competence", "Apply", "Newsroom"],
    ]);
    expect(
      rows.map((row) =>
        within(row)
          .getAllByRole("cell")
          .map((cell) => cell.textContent),
      ),
    ).toEqual([
      ["75%20 attempts", "50%8 attempts"],
      ["fewer than 5", "100%5 attempts"],
      ["fewer than 5", "fewer than 5"],
    ]);
  });

  test("leaves out the org unit column when the report does not break down by it", async () => {
    renderPage("/admin/insights", {
      "GET /api/insights/competence": {
        status: 200,
        body: {
          ...competence,
          by_org_unit: false,
          rows: [{ ...competence.rows[0], org_unit: null }],
        } satisfies CompetenceReport,
      },
    });

    const areas = await table("Competence areas");
    expect(
      within(areas)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual(["Competence area", "Depth", "September 2026", "October 2026"]);
    expect(
      within(areas)
        .getAllByRole("rowheader")
        .map((header) => header.textContent),
    ).toEqual(["Subject competence", "Know"]);
  });

  test("shows the votes per format, the feedback answers and the credentials per status", async () => {
    renderPage();

    const formatTable = await table("Companion formats");
    expect(rowCells(formatTable, "Praxis-Workshop")).toEqual(["7"]);
    expect(rowCells(formatTable, "Sprechstunde")).toEqual(["fewer than 5"]);
    expect(within(formatTable).getByText("Praxis-Workshop")).toHaveAttribute(
      "lang",
      "de",
    );

    const feedbackTable = await table("Feedback");
    expect(
      within(feedbackTable)
        .getAllByRole("rowheader")
        .map((header) => [header.textContent, header.getAttribute("scope")]),
    ).toEqual([
      ["Wie nützlich war das Programm?", "rowgroup"],
      ["Sehr nützlich", "row"],
      ["Wenig nützlich", "row"],
      ["Wie verständlich waren die Texte?", "rowgroup"],
      ["1", "row"],
      ["2", "row"],
      ["3", "row"],
      ["4", "row"],
      ["5", "row"],
      ["Was wünschen Sie sich?", "rowgroup"],
      ["Free-text answers", "row"],
      ["Was hat gefehlt?", "rowgroup"],
      ["Free-text answers", "row"],
    ]);
    expect(
      within(feedbackTable)
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual([
      "8",
      "fewer than 5",
      "fewer than 5",
      "fewer than 5",
      "fewer than 5",
      "6",
      "fewer than 5",
      "5",
      "fewer than 5",
    ]);
    expect(within(feedbackTable).getByText("Sehr nützlich")).toHaveAttribute(
      "lang",
      "de",
    );

    // The free-text answers of a question that reached the threshold are
    // listed below the table; those of a suppressed question are not.
    expect(
      screen.getByRole("heading", { level: 3, name: "Free-text answers" }),
    ).toBeInTheDocument();
    const wish = screen.getByRole("heading", {
      level: 4,
      name: "Was wünschen Sie sich?",
    });
    expect(wish).toHaveAttribute("lang", "de");
    const list = wish.nextElementSibling as HTMLElement;
    expect(
      within(list)
        .getAllByRole("listitem")
        .map((entry) => entry.textContent),
    ).toEqual(freeTextAnswers);
    expect(
      screen.queryByRole("heading", { level: 4, name: "Was hat gefehlt?" }),
    ).not.toBeInTheDocument();

    const credentialTable = await table("Credentials");
    expect(
      within(credentialTable)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual([
      "Qualification",
      "Active",
      "Refresher due",
      "Expired",
      "Revoked",
    ]);
    expect(rowCells(credentialTable, "Grundlagen basic")).toEqual([
      "5",
      "fewer than 5",
      "fewer than 5",
      "fewer than 5",
    ]);
    expect(
      rowCells(credentialTable, "Grundlagen 2025 basic-2025 Archived"),
    ).toEqual(["fewer than 5", "fewer than 5", "10", "fewer than 5"]);
    expect(barOf(credentialTable, "Grundlagen basic", 0)).toBe("w-10/20");
  });

  test("takes the threshold of each answer", async () => {
    renderPage("/admin/insights", {
      "GET /api/insights/formats": {
        status: 200,
        body: { ...formats, min_group_size: 3 } satisfies FormatReport,
      },
    });

    expect(rowCells(await table("Companion formats"), "Sprechstunde")).toEqual([
      "fewer than 3",
    ]);
    expect(
      rowCells(await table("Self-assessment"), "Einsteigerin oder Einsteiger"),
    ).toEqual(["6", "fewer than 5"]);
  });

  test("renders in German", async () => {
    await i18n.changeLanguage("de");
    try {
      renderPage();

      const segments = await screen.findByRole("table", {
        name: "Selbsteinschätzung",
      });
      expect(
        within(segments)
          .getAllByRole("columnheader")
          .map((header) => header.textContent),
      ).toEqual(["Segment", "September 2026", "Oktober 2026"]);
      expect(rowCells(segments, "Einsteigerin oder Einsteiger")).toEqual([
        "6",
        "weniger als 5",
      ]);
    } finally {
      await i18n.changeLanguage("en");
    }
  });

  test("has no axe violations", async () => {
    const { container } = renderPage();

    await table("Credentials");
    await screen.findByRole("heading", {
      level: 4,
      name: "Was wünschen Sie sich?",
    });
    await expectNoAxeViolations(container);
  });
});

describe("the program of the reports", () => {
  test("is the first published program without a query, and the URL keeps a chosen one", async () => {
    const urls = recordRequestUrls();
    const { user, location, requests } = renderPage();

    await table("Credentials");
    for (const path of REPORT_PATHS)
      expect(programsOf(urls, path), path).toEqual(["demo"]);

    await user.selectOptions(
      screen.getByRole("combobox", { name: "Program" }),
      "second",
    );

    expect(location()).toBe("/admin/insights?program=second");
    expect(screen.getByRole("combobox", { name: "Program" })).toHaveValue(
      "second",
    );
    await waitFor(() => {
      for (const path of REPORT_PATHS)
        expect(programsOf(urls, path), path).toEqual(["demo", "second"]);
    });
    // The pack text follows the locale of the chosen program.
    await waitFor(() =>
      expect(
        screen.getAllByText("Einsteigerin oder Einsteiger")[0],
      ).toHaveAttribute("lang", "en"),
    );
    expect(requestsTo(requests, "GET", "/api/programs")).toHaveLength(1);
  });

  test("reads the program of the query, also one that the list lacks", async () => {
    const urls = recordRequestUrls();
    renderPage("/admin/insights?program=archived-program");

    const picker = await screen.findByRole("combobox", { name: "Program" });
    await waitFor(() => expect(picker).toHaveValue("archived-program"));
    expect(
      within(picker)
        .getAllByRole("option")
        .map((option) => option.textContent),
    ).toEqual(["archived-program", "Demo-Programm", "Second program"]);
    await table("Credentials");
    for (const path of REPORT_PATHS)
      expect(programsOf(urls, path), path).toEqual(["archived-program"]);
    // The list lacks the locale of the program; every report carries it.
    expect(picker).toHaveAttribute("lang", "de");
    expect(
      within(picker).getByRole("option", { name: "archived-program" }),
    ).toHaveAttribute("lang", "de");
    await expectPackLang("de");
  });

  test("says once that a program does not exist", async () => {
    const notFound = { status: 404, body: { error: "not_found" } };
    renderPage(
      "/admin/insights?program=no-such-program",
      Object.fromEntries(REPORT_PATHS.map((path) => [`GET ${path}`, notFound])),
    );

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No program exists with this address.",
    );
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  test("says when no program is published", async () => {
    renderPage("/admin/insights", {
      "GET /api/programs": { status: 200, body: { programs: [] } },
    });

    expect(
      await screen.findByText("No program is published yet."),
    ).toBeInTheDocument();
    expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
  });

  test("shows an error when the programs fail and still reads a program of the query", async () => {
    renderPage("/admin/insights?program=demo", {
      "GET /api/programs": { status: 500, body: { error: "internal" } },
    });

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "The programs could not be loaded. Please try again later.",
    );
    expect(await table("Credentials")).toBeInTheDocument();
    await expectPackLang("de");
  });
});

describe("the states of a report", () => {
  test("shows the loading state of each report and of the program list", async () => {
    const pending = () => new Promise<never>(() => {});
    renderPage("/admin/insights?program=demo", {
      "GET /api/programs": pending,
      ...Object.fromEntries(
        REPORT_PATHS.map((path) => [`GET ${path}`, pending]),
      ),
    });

    expect(await screen.findByText("Loading the programs…")).toHaveAttribute(
      "role",
      "status",
    );
    expect(await screen.findAllByText("Loading the report…")).toHaveLength(6);
  });

  test("shows an error in the section of a failed report only", async () => {
    renderPage("/admin/insights", {
      "GET /api/insights/items": { status: 500, body: { error: "internal" } },
    });

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "The report could not be loaded. Please try again later.",
    );
    expect(screen.queryByRole("table", { name: "Practice items" })).toBeNull();
    expect(await table("Self-assessment")).toBeInTheDocument();
  });

  test("states an empty report", async () => {
    renderPage("/admin/insights", {
      "GET /api/insights/self-assessment": {
        status: 200,
        body: { ...selfAssessment, months: [], rows: [] },
      },
      "GET /api/insights/items": {
        status: 200,
        body: { ...items, months: [], rows: [] },
      },
      "GET /api/insights/competence": {
        status: 200,
        body: { ...competence, months: [], rows: [] },
      },
      "GET /api/insights/formats": {
        status: 200,
        body: { ...formats, formats: [] },
      },
      "GET /api/insights/feedback": {
        status: 200,
        body: { ...feedback, questions: [] },
      },
      "GET /api/insights/credentials": {
        status: 200,
        body: { ...credentials, qualifications: [] },
      },
    });

    for (const text of [
      "No self-assessment has been recorded yet.",
      "No practice item has been answered yet.",
      "No practice item with a learning objective has been answered yet.",
      "The program offers no companion format.",
      "The program has no feedback station.",
      "The program offers no qualification.",
    ])
      expect(await screen.findByText(text)).toBeInTheDocument();
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });
});

describe("the route /admin/insights", () => {
  test("renders the reports page for an analyst through both guards", async () => {
    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });
    const { fetchImpl } = stubFetch(responses());
    const router = createMemoryRouter(createRoutes(<Outlet />, appRoutes), {
      initialEntries: ["/admin/insights"],
    });
    render(
      <QueryClientProvider client={queryClient}>
        <ApiClientProvider client={createApiClient(queryClient, fetchImpl)}>
          <SessionContext.Provider
            value={sessionValue({ roles: ["learner", "analyst"] })}
          >
            <RouterProvider router={router} />
          </SessionContext.Provider>
        </ApiClientProvider>
      </QueryClientProvider>,
    );

    expect(
      await screen.findByRole("heading", { level: 1, name: "Reports" }),
    ).toBeInTheDocument();
    expect(await table("Credentials")).toBeInTheDocument();
  });
});

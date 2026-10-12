import { act, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { SecuritySummary } from "../api/account";
import type { AdminExport } from "../api/exports";
import type { components } from "../api/schema";
import { expectNoAxeViolations } from "../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type RenderWithProvidersResult,
  type StubResponses,
} from "../test/render";
import { signedInPayload } from "../test/session";
import { ExportsPage } from "./ExportsPage";

/**
 * Task 0016 step 11: the export page `/admin/exports`. The author chooses a
 * module of a published program and a SCORM version; the request goes to
 * `POST /api/admin/exports` with exactly `module_id` and `scorm_version`.
 * The page lists the requested exports in a status region and reads each
 * one every two seconds while it is `queued` or `running`; a `done` export
 * links its download, a `failed` one shows the error text.
 */
type ProgramView = components["schemas"]["ProgramView"];
type ProgramModule = ProgramView["modules"][number];

const EXPORT_ID = "00000000-0000-4000-8000-000000001601";
const MODULE_1 = "00000000-0000-4000-8000-000000001611";
const MODULE_2 = "00000000-0000-4000-8000-000000001612";
const GERMAN_MODULE = "00000000-0000-4000-8000-000000001621";
const SLUG = "ai-assistant-basics-demo";
const GERMAN_SLUG = "ki-grundlagen";
const REQUEST = "/api/admin/exports";
const SHOW = `/api/admin/exports/${EXPORT_ID}`;
const DOWNLOAD = `/api/admin/exports/${EXPORT_ID}/download`;

const author = signedInPayload("mfa", { roles: ["learner", "author"] });

const moduleView = (
  id: string,
  number: number,
  title: string,
): ProgramModule => ({
  id,
  number,
  title,
  summary: "",
  phases: ["understand"],
  single_path: false,
});

const programView = (
  slug: string,
  title: string,
  locale: string,
  modules: ProgramModule[],
): ProgramView => ({
  id: "00000000-0000-4000-8000-000000001600",
  slug,
  title,
  locale,
  pack_version: "1.0.0",
  companion_formats: [],
  segments: [],
  stations: [],
  modules,
});

const demo = programView(SLUG, "AI assistant basics", "en", [
  moduleView(MODULE_1, 1, "What AI assistants do"),
  moduleView(MODULE_2, 2, "Working with sources"),
]);
const german = programView(GERMAN_SLUG, "KI-Grundlagen", "de", [
  moduleView(GERMAN_MODULE, 1, "Was KI-Assistenten tun"),
]);

const exportOf = (overrides: Partial<AdminExport> = {}): AdminExport => ({
  id: EXPORT_ID,
  module: {
    id: MODULE_1,
    number: 1,
    title: "What AI assistants do",
    program: { slug: SLUG, title: "AI assistant basics" },
  },
  scorm_version: "scorm12",
  status: "queued",
  error: null,
  inserted_at: "2026-10-12T09:30:00Z",
  download_path: null,
  ...overrides,
});

const done = exportOf({ status: "done", download_path: DOWNLOAD });

function renderPage(responses: StubResponses = {}) {
  return renderWithProviders(<ExportsPage />, {
    route: "/admin/exports",
    session: author,
    responses: {
      "GET /api/programs": {
        status: 200,
        body: {
          programs: [
            { slug: SLUG, title: "AI assistant basics", locale: "en" },
            { slug: GERMAN_SLUG, title: "KI-Grundlagen", locale: "de" },
          ],
        },
      },
      [`GET /api/programs/${SLUG}`]: { status: 200, body: demo },
      [`GET /api/programs/${GERMAN_SLUG}`]: { status: 200, body: german },
      [`POST ${REQUEST}`]: { status: 202, body: exportOf() },
      ...responses,
    },
  });
}

/** Chooses module 1 of the first program and `version`, and requests the export. */
async function requestExport(
  user: RenderWithProvidersResult["user"],
  version = "SCORM 1.2",
) {
  await user.selectOptions(
    await screen.findByLabelText("Module"),
    "1. What AI assistants do",
  );
  await user.click(screen.getByLabelText(version));
  await user.click(screen.getByRole("button", { name: "Request the export" }));
}

const exportList = () =>
  screen.getByRole("status", { name: "Requested exports" });

/** Moves the clock of the polling by `ms` milliseconds. */
const advance = (ms: number) => act(() => vi.advanceTimersByTimeAsync(ms));

afterEach(() => {
  vi.useRealTimers();
});

describe("the form", () => {
  test("offers the modules of the chosen program in the language of the program", async () => {
    const { user, requests } = renderPage();

    const programField = await screen.findByLabelText("Program");
    expect(programField).toHaveValue(SLUG);
    expect(programField).toHaveAttribute("lang", "en");
    const moduleField = await screen.findByLabelText("Module");
    expect(
      within(moduleField)
        .getAllByRole("option")
        .map((option) => [option.textContent, option.getAttribute("lang")]),
    ).toEqual([
      ["Choose a module", null],
      ["1. What AI assistants do", "en"],
      ["2. Working with sources", "en"],
    ]);

    await user.selectOptions(programField, "KI-Grundlagen");

    expect(programField).toHaveAttribute("lang", "de");
    expect(
      await screen.findByRole("option", { name: "1. Was KI-Assistenten tun" }),
    ).toHaveAttribute("lang", "de");
    expect(
      requestsTo(requests, "GET", `/api/programs/${GERMAN_SLUG}`),
    ).toHaveLength(1);
  });

  test("states that the package holds the answer keys and that the LMS records results per person", async () => {
    renderPage();

    const notice = await screen.findByRole("region", {
      name: "Answer keys and results per person",
    });
    expect(notice).toHaveTextContent(
      "The package contains the answer keys of the module",
    );
    expect(notice).toHaveTextContent(
      "The receiving LMS records the results per person: learner id, status, score, time and the status of each learning objective.",
    );
  });

  test("requests the export with exactly module_id and scorm_version and lists it", async () => {
    const { user, requests } = renderPage({
      [`POST ${REQUEST}`]: {
        status: 202,
        body: exportOf({ scorm_version: "scorm2004" }),
      },
      [`GET ${SHOW}`]: { status: 200, body: exportOf() },
    });
    expect(
      within(exportList()).getByText(
        "No export has been requested on this page.",
      ),
    ).toBeInTheDocument();

    await requestExport(user, "SCORM 2004 4th edition");

    const entry = await within(exportList()).findByRole("listitem");
    const [request] = requestsTo(requests, "POST", REQUEST);
    expect(request.body).toEqual({
      module_id: MODULE_1,
      scorm_version: "scorm2004",
    });
    expect(request.headers.get("x-csrf-token")).toBe("csrf-1");
    expect(
      within(entry).getByRole("heading", {
        level: 3,
        name: "Module 1: What AI assistants do",
      }),
    ).toBeInTheDocument();
    expect(within(entry).getByText("What AI assistants do")).toHaveAttribute(
      "lang",
      "en",
    );
    expect(within(entry).getByText("AI assistant basics")).toHaveAttribute(
      "lang",
      "en",
    );
    expect(entry).toHaveTextContent("VersionSCORM 2004 4th edition");
    expect(entry).toHaveTextContent("StatusQueued");
    expect(within(entry).queryByRole("link")).not.toBeInTheDocument();
    // The answer of the request fills the cache, so no read follows at once.
    expect(requestsTo(requests, "GET", SHOW)).toHaveLength(0);
  });

  test("asks for a module before it sends anything", async () => {
    const { user, requests } = renderPage();
    const moduleField = await screen.findByLabelText("Module");

    await user.click(
      screen.getByRole("button", { name: "Request the export" }),
    );

    expect(moduleField).toHaveAttribute("aria-invalid", "true");
    expect(moduleField).toHaveAccessibleDescription("Choose a module.");
    await waitFor(() => expect(moduleField).toHaveFocus());
    expect(requestsTo(requests, "POST", REQUEST)).toHaveLength(0);
  });

  test.each([
    [
      422,
      { error: "validation_failed" },
      "The server did not accept the request. Choose the module and the version again.",
    ],
    [403, { error: "forbidden" }, "Your account may not make this change."],
    [500, { error: "internal" }, "Something went wrong. Please try again."],
  ])("a %i answer shows its message", async (status, body, message) => {
    const { user } = renderPage({ [`POST ${REQUEST}`]: { status, body } });

    await requestExport(user);

    await waitFor(() =>
      expect(screen.getByRole("alert")).toHaveTextContent(message),
    );
    expect(
      within(exportList()).queryByRole("listitem"),
    ).not.toBeInTheDocument();
  });

  test("a 404 clears the module and loads the modules again", async () => {
    const { user, requests } = renderPage({
      [`POST ${REQUEST}`]: { status: 404, body: { error: "not_found" } },
    });

    await requestExport(user);

    const moduleField = screen.getByLabelText("Module");
    await waitFor(() =>
      expect(moduleField).toHaveAccessibleDescription(
        "The module is no longer published. Choose another module.",
      ),
    );
    expect(moduleField).toHaveValue("");
    await waitFor(() => expect(moduleField).toHaveFocus());
    await waitFor(() =>
      expect(requestsTo(requests, "GET", `/api/programs/${SLUG}`)).toHaveLength(
        2,
      ),
    );
  });
});

describe("the step-up", () => {
  test("a closed step-up dialog requests no export and says why", async () => {
    const { user, requests } = renderPage({
      [`POST ${REQUEST}`]: { status: 403, body: { error: "reauth_required" } },
    });

    await requestExport(user);
    const stepUp = await screen.findByRole("dialog", {
      name: "Confirm it is you",
    });
    await user.click(within(stepUp).getByRole("button", { name: "Cancel" }));

    expect(
      await screen.findByText(
        "The export was not requested, because the confirmation with a second factor was cancelled.",
      ),
    ).toHaveAttribute("role", "alert");
    expect(requestsTo(requests, "POST", REQUEST)).toHaveLength(1);
    expect(
      within(exportList()).queryByRole("listitem"),
    ).not.toBeInTheDocument();
  });

  test("repeats the request once after a step-up with the authenticator app", async () => {
    const security: SecuritySummary = {
      admin_passkey_required: false,
      linked_providers: [],
      passkeys: [],
      password_set: true,
      recent_auth_until: null,
      recovery_codes: { generated_at: "2026-09-01T08:00:00Z", remaining: 10 },
      totp: { enabled: true, enabled_at: "2026-09-03T08:00:00Z" },
    };
    const renewed = signedInPayload("mfa", {
      roles: ["learner", "author"],
      csrf_token: "csrf-2",
      session: { recent_auth_until: "2026-10-12T09:40:00Z" },
    });
    const { user, requests } = renderPage({
      "GET /api/me/security": { status: 200, body: security },
      "POST /api/me/reauth": { status: 200, body: renewed },
      "GET /api/session": { status: 200, body: renewed },
      [`POST ${REQUEST}`]: [
        { status: 403, body: { error: "reauth_required" } },
        { status: 202, body: exportOf() },
      ],
    });

    await requestExport(user);
    const stepUp = await screen.findByRole("dialog", {
      name: "Confirm it is you",
    });
    await user.type(
      await within(stepUp).findByLabelText(
        "Six-digit code of the authenticator app",
      ),
      "123456",
    );
    await user.click(
      within(stepUp).getByRole("button", { name: "Confirm with the code" }),
    );

    expect(await within(exportList()).findByRole("listitem")).toHaveTextContent(
      "StatusQueued",
    );
    const posts = requestsTo(requests, "POST", REQUEST);
    expect(posts).toHaveLength(2);
    expect(posts.map((post) => post.body)).toEqual([
      { module_id: MODULE_1, scorm_version: "scorm12" },
      { module_id: MODULE_1, scorm_version: "scorm12" },
    ]);
    expect(posts[1].headers.get("x-csrf-token")).toBe("csrf-2");
  });
});

describe("the list of exports", () => {
  test("reads an export every two seconds until it is done and links the download", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const { user, requests } = renderPage({
      [`GET ${SHOW}`]: [
        { status: 200, body: exportOf({ status: "running" }) },
        { status: 200, body: done },
      ],
    });

    await requestExport(user);
    const entry = await within(exportList()).findByRole("listitem");
    expect(entry).toHaveTextContent("StatusQueued");
    expect(requestsTo(requests, "GET", SHOW)).toHaveLength(0);

    await advance(2000);
    await waitFor(() => expect(entry).toHaveTextContent("StatusRunning"));
    expect(requestsTo(requests, "GET", SHOW)).toHaveLength(1);
    expect(within(entry).queryByRole("link")).not.toBeInTheDocument();

    await advance(2000);
    const link = await within(entry).findByRole("link", {
      name: "Download the package Module 1: What AI assistants do, SCORM 1.2",
    });
    expect(link).toHaveAttribute("href", DOWNLOAD);
    expect(link).toHaveAttribute("download");
    expect(entry).toHaveTextContent("StatusReady for download");
    expect(requestsTo(requests, "GET", SHOW)).toHaveLength(2);

    // A finished export is not read again.
    await advance(6000);
    expect(requestsTo(requests, "GET", SHOW)).toHaveLength(2);
  });

  test("a failed export shows the error text and no download", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const error =
      "The SCORM player build lacks NOTICE. Run `npm --prefix frontend run build:scorm` and request the export again.";
    const { user, requests } = renderPage({
      [`GET ${SHOW}`]: {
        status: 200,
        body: exportOf({ status: "failed", error }),
      },
    });

    await requestExport(user);
    const entry = await within(exportList()).findByRole("listitem");
    await advance(2000);

    await waitFor(() => expect(entry).toHaveTextContent("StatusFailed"));
    expect(entry).toHaveTextContent(`Reason: ${error}`);
    expect(within(entry).queryByRole("link")).not.toBeInTheDocument();
    await advance(6000);
    expect(requestsTo(requests, "GET", SHOW)).toHaveLength(1);
  });

  test("stops reading an export that answers 404 and says so", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const { user, requests } = renderPage({
      [`GET ${SHOW}`]: { status: 404, body: { error: "not_found" } },
    });

    await requestExport(user);
    const entry = await within(exportList()).findByRole("listitem");
    await advance(2000);

    await waitFor(() =>
      expect(entry).toHaveTextContent(
        "The current status could not be loaded.",
      ),
    );
    expect(entry).toHaveTextContent("StatusQueued");
    await advance(6000);
    expect(requestsTo(requests, "GET", SHOW)).toHaveLength(1);
  });

  test("lists the newest export first", async () => {
    const second = "00000000-0000-4000-8000-000000001602";
    const { user } = renderPage({
      [`POST ${REQUEST}`]: [
        { status: 202, body: exportOf() },
        {
          status: 202,
          body: exportOf({ id: second, scorm_version: "scorm2004" }),
        },
      ],
    });

    await requestExport(user);
    await within(exportList()).findByRole("listitem");
    await user.click(screen.getByLabelText("SCORM 2004 4th edition"));
    await user.click(
      screen.getByRole("button", { name: "Request the export" }),
    );

    await waitFor(() =>
      expect(within(exportList()).getAllByRole("listitem")).toHaveLength(2),
    );
    expect(
      within(exportList())
        .getAllByRole("listitem")
        .map((entry) => within(entry).getByText(/^SCORM /).textContent),
    ).toEqual(["SCORM 2004 4th edition", "SCORM 1.2"]);
  });

  test("has no axe violations with an export ready for download", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const { user, container } = renderPage({
      [`GET ${SHOW}`]: { status: 200, body: done },
    });

    await requestExport(user);
    const entry = await within(exportList()).findByRole("listitem");
    await advance(2000);
    await within(entry).findByRole("link");
    vi.useRealTimers();

    await expectNoAxeViolations(container);
  });
});

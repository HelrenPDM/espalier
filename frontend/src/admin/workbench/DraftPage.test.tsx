import { focusManager } from "@tanstack/react-query";
import { act, screen, waitFor, within } from "@testing-library/react";
import { useEffect } from "react";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { AlignmentMatrixRow, ReportEntry } from "../../api/admin/packs";
import type {
  PackDraft,
  PackDraftCheck,
  PackDraftFile,
} from "../../api/admin/workbench";
import { setStepUpHandler } from "../../api/stepUp";
import { AREAS, DEPTHS } from "../../player/objectives/labels";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type RenderWithProvidersResult,
  type StubAnswer,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { DraftPage } from "./DraftPage";
import type { PackFileEditorProps } from "./PackFileEditor";

/**
 * Task 0016a, step 15: the draft page with a textarea in place of the
 * CodeMirror view, which jsdom cannot drive (the spec allows the stub). The
 * stub honours the props of `PackFileEditor`: the label, the value,
 * `onChange`, `readOnly`, Ctrl+S for `onSave`, and `goTo`, which reports
 * the cursor at the start of the line through `onCursor`.
 */
function EditorStub({
  value,
  onChange,
  language,
  label,
  readOnly,
  onSave,
  onCursor,
  goTo,
}: PackFileEditorProps) {
  useEffect(() => {
    if (goTo !== null) onCursor(goTo.line, 1);
    // goTo is a new object for each request.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [goTo]);
  return (
    <textarea
      aria-label={label}
      data-language={language}
      readOnly={readOnly}
      value={value}
      onChange={(event) => onChange(event.target.value)}
      onKeyDown={(event) => {
        if ((event.ctrlKey || event.metaKey) && event.key === "s") {
          event.preventDefault();
          onSave();
        }
      }}
    />
  );
}

vi.mock("./PackFileEditor", () => ({ PackFileEditor: EditorStub }));

const ID = "00000000-0000-4000-8000-000000000801";
const BASE = `/api/admin/pack-drafts/${ID}`;
const IMPORT_ID = "00000000-0000-4000-8000-000000000501";
const author = signedInPayload("mfa", { roles: ["learner", "author"] });
const TIME = "2026-10-13T09:00:00Z";

const fileId = (n: number) =>
  `00000000-0000-4000-8000-0000000009${String(n).padStart(2, "0")}`;

interface Entry {
  id: string;
  path: string;
}

/** The files in the order of the answer, which is not the path order. */
const FILES: Entry[] = [
  { id: fileId(1), path: "stations.yaml" },
  { id: fileId(2), path: "pack.yaml" },
  { id: fileId(3), path: "modules/01-first-module/module.yaml" },
  { id: fileId(4), path: "modules/01-first-module/lessons/01-first-lesson.md" },
  { id: fileId(5), path: "modules/01-first-module/items.yaml" },
  { id: fileId(6), path: "modules/01-first-module/objectives.yaml" },
];
const [STATIONS, PACK, , , ITEMS, OBJECTIVES] = FILES;

const CONTENT: Record<string, string> = {
  "pack.yaml": "key: demo\ntitle: Demo pack\n",
  "stations.yaml": "- kind: overview\n  title: Overview\n",
  "modules/01-first-module/items.yaml": "- key: m1-first-question\n",
  "modules/01-first-module/objectives.yaml": "- key: m1-subject\n",
};

function draftOf(lockVersion = 3, files: Entry[] = FILES): PackDraft {
  return {
    id: ID,
    title: "Demo pack",
    pack_key: "demo",
    lock_version: lockVersion,
    inserted_at: TIME,
    updated_at: TIME,
    usage: { files: files.length, bytes: 2_048 },
    limits: { files: 2_000, file_bytes: 1_048_576, draft_bytes: 104_857_600 },
    files: files.map((file) => ({ ...file, bytes: 100, updated_at: TIME })),
  };
}

const ok = (body: unknown, status = 200): StubAnswer => ({ status, body });

function fileAnswer(
  entry: Entry,
  content = CONTENT[entry.path] ?? "",
  lockVersion = 3,
): PackDraftFile {
  return {
    ...entry,
    content,
    bytes: content.length,
    updated_at: TIME,
    lock_version: lockVersion,
  };
}

const fileRoutes = (): StubResponses =>
  Object.fromEntries(
    FILES.map((entry) => [
      `GET ${BASE}/files/${entry.id}`,
      ok(fileAnswer(entry)),
    ]),
  );

const stale = (lockVersion: number): StubAnswer => ({
  status: 409,
  body: { error: "stale_draft", lock_version: lockVersion },
});

const notFound: StubAnswer = { status: 404, body: { error: "not_found" } };
const serverError: StubAnswer = { status: 500, body: { error: "internal" } };

/** A gate that holds stubbed answers until `open` runs. */
function gate() {
  let open = () => {};
  const opened = new Promise<void>((resolve) => {
    open = resolve;
  });
  return { opened, open: () => act(open) };
}

function renderPage(responses: StubResponses = {}) {
  return renderWithProviders(<DraftPage />, {
    route: `/admin/workbench/${ID}`,
    path: "/admin/workbench/:id",
    session: author,
    responses: {
      [`GET ${BASE}`]: ok(draftOf()),
      ...fileRoutes(),
      ...responses,
    },
  });
}

const findTree = () =>
  screen.findByRole("navigation", { name: "Files of the draft" });

/** Opens a file through the tree and returns its editor. */
async function openFile(
  { user }: RenderWithProvidersResult,
  name: string,
  path: string,
) {
  await user.click(
    await within(await findTree()).findByRole("button", { name }),
  );
  return screen.findByRole("textbox", { name: `Content of ${path}` });
}

const ITEMS_BUTTON = "items.yaml, modules/01-first-module/";

/** The tree as indented lines: a directory with `/`, a file by its name. */
function outline(nav: HTMLElement): string[] {
  return [...nav.querySelectorAll("li")].map((item) => {
    let depth = 0;
    for (
      let node = item.parentElement;
      node !== nav;
      node = node!.parentElement
    )
      if (node!.tagName === "UL") depth += 1;
    const first = item.firstElementChild!;
    const label =
      first.tagName === "SPAN"
        ? first.textContent
        : first.firstChild?.textContent;
    return `${"  ".repeat(depth - 1)}${label}`;
  });
}

const status = () =>
  screen
    .getAllByRole("status")
    .map((region) => region.textContent)
    .join(" ");

afterEach(() => {
  vi.restoreAllMocks();
});

describe("the file tree", () => {
  test("groups the files by directory in path order and marks the open file", async () => {
    const page = renderPage();

    const nav = await findTree();
    expect(outline(nav)).toEqual([
      "modules/",
      "  01-first-module/",
      "    items.yaml",
      "    lessons/",
      "      01-first-lesson.md",
      "    module.yaml",
      "    objectives.yaml",
      "pack.yaml",
      "stations.yaml",
    ]);
    expect(within(nav).queryByRole("tree")).toBeNull();

    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    expect(editor).toHaveValue(CONTENT["pack.yaml"]);
    expect(editor).toHaveAttribute("data-language", "yaml");
    expect(
      within(nav).getByRole("button", { name: "pack.yaml" }),
    ).toHaveAttribute("aria-current", "true");
    expect(
      within(nav).getByRole("button", { name: "stations.yaml" }),
    ).not.toHaveAttribute("aria-current");
    expect(screen.getByText("Line 1, column 1")).toBeInTheDocument();

    const lesson = await openFile(
      page,
      "01-first-lesson.md, modules/01-first-module/lessons/",
      FILES[3].path,
    );
    expect(lesson).toHaveAttribute("data-language", "markdown");
  });

  test("shows the title, the breadcrumb, the pack key and the usage", async () => {
    renderPage();

    expect(
      await screen.findByRole("heading", { level: 1, name: "Demo pack" }),
    ).toBeInTheDocument();
    const trail = screen.getByRole("navigation", { name: "Breadcrumb" });
    expect(
      within(trail).getByRole("link", { name: "Pack workbench" }),
    ).toHaveAttribute("href", "/admin/workbench");
    expect(screen.getByText("demo")).toBeInTheDocument();
    expect(screen.getByText("6 of 2,000")).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "Download as zip" }),
    ).toHaveAttribute("href", `${BASE}/download`);
  });
});

describe("editing and saving", () => {
  test("an edit sets the marker; Ctrl+S sends PUT with the cached lock_version, clears it and announces", async () => {
    const page = renderPage({
      [`PUT ${BASE}/files/${PACK.id}`]: [ok(draftOf(4)), ok(draftOf(5))],
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");

    await user.type(editor, "version: 2");
    const nav = await findTree();
    expect(
      within(nav).getByRole("button", { name: "pack.yaml, unsaved" }),
    ).toHaveAttribute("aria-current", "true");
    expect(
      screen.getByRole("heading", {
        level: 2,
        name: "Content of pack.yaml Unsaved changes",
      }),
    ).toBeInTheDocument();

    await user.keyboard("{Control>}s{/Control}");
    expect(await screen.findByText("Saved pack.yaml")).toBeInTheDocument();
    expect(status()).toContain("Saved pack.yaml");
    expect(
      within(nav).getByRole("button", { name: "pack.yaml" }),
    ).toBeInTheDocument();
    expect(screen.queryByText("Unsaved changes")).toBeNull();
    const [put] = requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`);
    expect(put.body).toEqual({
      content: `${CONTENT["pack.yaml"]}version: 2`,
      lock_version: 3,
    });

    // The answer of the save is the cached draft, so the next save sends
    // its lock_version.
    await user.type(editor, "!");
    await user.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(
        requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`),
      ).toHaveLength(2),
    );
    expect(
      requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`)[1].body,
    ).toEqual({
      content: `${CONTENT["pack.yaml"]}version: 2!`,
      lock_version: 4,
    });
  });

  test("a 409 stale_draft opens the dialog, and Load the stored version replaces the text", async () => {
    const page = renderPage({
      [`GET ${BASE}`]: [ok(draftOf(3)), ok(draftOf(7))],
      [`GET ${BASE}/files/${PACK.id}`]: [
        ok(fileAnswer(PACK)),
        ok(fileAnswer(PACK, "key: demo\ntitle: Stored title\n", 7)),
      ],
      [`PUT ${BASE}/files/${PACK.id}`]: stale(7),
    });
    const { user } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "mine: true");
    await user.click(screen.getByRole("button", { name: "Save" }));

    const dialog = await screen.findByRole("dialog", {
      name: "The draft changed",
    });
    expect(dialog).toHaveTextContent(
      "The next save replaces the stored version of the file.",
    );
    await user.click(
      within(dialog).getByRole("button", { name: "Load the stored version" }),
    );

    await waitFor(() =>
      expect(editor).toHaveValue("key: demo\ntitle: Stored title\n"),
    );
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.queryByText("Unsaved changes")).toBeNull();
  });

  test("Keep my version keeps the text, and the next save sends the new lock_version", async () => {
    const page = renderPage({
      [`PUT ${BASE}/files/${PACK.id}`]: [stale(7), ok(draftOf(8))],
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "mine: true");
    await user.click(screen.getByRole("button", { name: "Save" }));

    const dialog = await screen.findByRole("dialog", {
      name: "The draft changed",
    });
    await user.click(
      within(dialog).getByRole("button", { name: "Keep my version" }),
    );
    expect(screen.queryByRole("dialog")).toBeNull();
    const text = `${CONTENT["pack.yaml"]}mine: true`;
    expect(editor).toHaveValue(text);
    expect(screen.getByText("Unsaved changes")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Save" }));
    expect(await screen.findByText("Saved pack.yaml")).toBeInTheDocument();
    expect(
      requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`).map(
        (request) => request.body,
      ),
    ).toEqual([
      { content: text, lock_version: 3 },
      { content: text, lock_version: 7 },
    ]);
  });

  test("a 403 reauth_required on a save calls the step-up handler and repeats the PUT once", async () => {
    const page = renderPage({
      [`PUT ${BASE}/files/${PACK.id}`]: [
        { status: 403, body: { error: "reauth_required" } },
        ok(draftOf(4)),
      ],
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    const handler = vi.fn(async () => true);
    const remove = setStepUpHandler(handler);
    try {
      await user.type(editor, "x: 1");
      await user.click(screen.getByRole("button", { name: "Save" }));

      expect(await screen.findByText("Saved pack.yaml")).toBeInTheDocument();
      expect(handler).toHaveBeenCalledTimes(1);
      const puts = requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`);
      expect(puts).toHaveLength(2);
      expect(puts[1].body).toEqual(puts[0].body);
    } finally {
      remove();
    }
  });

  test("a 404 on a save reads the draft again and states that the file was deleted", async () => {
    const page = renderPage({
      [`GET ${BASE}`]: [
        ok(draftOf(3)),
        ok(
          draftOf(
            4,
            FILES.filter((entry) => entry !== PACK),
          ),
        ),
      ],
      [`PUT ${BASE}/files/${PACK.id}`]: {
        status: 404,
        body: { error: "not_found" },
      },
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");
    await user.click(screen.getByRole("button", { name: "Save" }));

    expect(
      await screen.findByText(/The file pack.yaml no longer exists/),
    ).toHaveAttribute("role", "alert");
    expect(requestsTo(requests, "GET", BASE)).toHaveLength(2);
    expect(
      within(await findTree()).queryByRole("button", { name: /^pack.yaml/ }),
    ).toBeNull();
    expect(editor).toHaveValue(`${CONTENT["pack.yaml"]}x: 1`);
  });

  test("a 404 on a save of a draft that another session deleted says so and keeps the text", async () => {
    const page = renderPage({
      [`GET ${BASE}`]: [ok(draftOf(3)), notFound],
      [`PUT ${BASE}/files/${PACK.id}`]: notFound,
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");
    await user.click(screen.getByRole("button", { name: "Save" }));

    expect(
      await screen.findByText(/This draft no longer exists/),
    ).toHaveAttribute("role", "alert");
    expect(requestsTo(requests, "GET", BASE)).toHaveLength(2);
    expect(editor).toHaveValue(`${CONTENT["pack.yaml"]}x: 1`);
    expect(screen.getByText("Unsaved changes")).toBeInTheDocument();
  });

  test("a 404 on a save whose draft still lists the file states that nothing was saved", async () => {
    const page = renderPage({
      [`PUT ${BASE}/files/${PACK.id}`]: notFound,
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");
    await user.click(screen.getByRole("button", { name: "Save" }));

    expect(
      await screen.findByText(
        /The file was not saved, because the draft or the file no longer exists/,
      ),
    ).toHaveAttribute("role", "alert");
    expect(requestsTo(requests, "GET", BASE)).toHaveLength(2);
    expect(editor).toHaveValue(`${CONTENT["pack.yaml"]}x: 1`);
  });

  test("a content above the character limit of the request names the limit of a file", async () => {
    const page = renderPage({
      [`PUT ${BASE}/files/${PACK.id}`]: {
        status: 422,
        body: {
          error: "validation_failed",
          fields: { content: ["max_length"] },
        },
      },
    });
    const { user } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");
    await user.click(screen.getByRole("button", { name: "Save" }));

    expect(
      await screen.findByText(
        "The file is larger than 1 MB, the limit of a file.",
      ),
    ).toHaveAttribute("role", "alert");
  });
});

describe("reading a file", () => {
  test("a failed read of a file that opens again shows no older text", async () => {
    const page = renderPage({
      [`GET ${BASE}/files/${PACK.id}`]: [ok(fileAnswer(PACK)), serverError],
      [`PUT ${BASE}/files/${PACK.id}`]: ok(draftOf(4)),
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");
    await user.keyboard("{Control>}s{/Control}");
    expect(await screen.findByText("Saved pack.yaml")).toBeInTheDocument();
    await openFile(page, "stations.yaml", "stations.yaml");

    await user.click(
      within(await findTree()).getByRole("button", { name: "pack.yaml" }),
    );

    expect(
      await screen.findByText("The file could not be loaded."),
    ).toHaveAttribute("role", "alert");
    expect(
      screen.queryByRole("textbox", { name: "Content of pack.yaml" }),
    ).toBeNull();
    expect(
      requestsTo(requests, "GET", `${BASE}/files/${PACK.id}`),
    ).toHaveLength(2);
  });

  test("when Load the stored version cannot read the file, the text stays and the next save meets the conflict again", async () => {
    const page = renderPage({
      [`GET ${BASE}`]: [ok(draftOf(3)), ok(draftOf(7))],
      [`GET ${BASE}/files/${PACK.id}`]: [ok(fileAnswer(PACK)), serverError],
      [`PUT ${BASE}/files/${PACK.id}`]: stale(7),
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "mine: true");
    await user.click(screen.getByRole("button", { name: "Save" }));
    const dialog = await screen.findByRole("dialog", {
      name: "The draft changed",
    });
    await user.click(
      within(dialog).getByRole("button", { name: "Load the stored version" }),
    );

    expect(
      await screen.findByText(/The stored version could not be loaded/),
    ).toHaveAttribute("role", "alert");
    const text = `${CONTENT["pack.yaml"]}mine: true`;
    expect(editor).toHaveValue(text);
    expect(screen.getByText("Unsaved changes")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Save" }));
    expect(
      await screen.findByRole("dialog", { name: "The draft changed" }),
    ).toBeInTheDocument();
    expect(
      requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`).map(
        (request) => request.body,
      ),
    ).toEqual([
      { content: text, lock_version: 3 },
      { content: text, lock_version: 3 },
    ]);
  });

  test("while Load the stored version reads, the editor takes no input and nothing saves", async () => {
    const fileRead = gate();
    let reads = 0;
    const page = renderPage({
      [`GET ${BASE}`]: [ok(draftOf(3)), ok(draftOf(7))],
      [`GET ${BASE}/files/${PACK.id}`]: async () => {
        reads += 1;
        if (reads === 1) return ok(fileAnswer(PACK));
        await fileRead.opened;
        return ok(fileAnswer(PACK, "key: demo\ntitle: Stored title\n", 7));
      },
      [`PUT ${BASE}/files/${PACK.id}`]: stale(7),
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "mine: true");
    await user.click(screen.getByRole("button", { name: "Save" }));
    const dialog = await screen.findByRole("dialog", {
      name: "The draft changed",
    });
    await user.click(
      within(dialog).getByRole("button", { name: "Load the stored version" }),
    );

    // The draft with lock_version 7 is in, the file not yet.
    await waitFor(() => expect(reads).toBe(2));
    expect(requestsTo(requests, "GET", BASE)).toHaveLength(2);
    expect(editor).toHaveAttribute("readonly");
    expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();
    expect(
      screen.getByRole("button", { name: "Create import" }),
    ).toBeDisabled();
    await user.type(editor, " late");
    await user.keyboard("{Control>}s{/Control}");
    expect(editor).toHaveValue(`${CONTENT["pack.yaml"]}mine: true`);
    expect(
      requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`),
    ).toHaveLength(1);

    fileRead.open();
    await waitFor(() =>
      expect(editor).toHaveValue("key: demo\ntitle: Stored title\n"),
    );
    expect(editor).not.toHaveAttribute("readonly");
    expect(screen.queryByText("Unsaved changes")).toBeNull();
    expect(
      requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`),
    ).toHaveLength(1);
  });

  test("a renamed open file takes the language of its new path", async () => {
    const LESSON_PATH = "modules/01-first-module/lessons/items.md";
    const page = renderPage({
      [`PATCH ${BASE}/files/${ITEMS.id}`]: ok(
        draftOf(4, [
          ...FILES.filter((entry) => entry !== ITEMS),
          { id: ITEMS.id, path: LESSON_PATH },
        ]),
      ),
    });
    const { user } = page;
    const editor = await openFile(page, ITEMS_BUTTON, ITEMS.path);
    expect(editor).toHaveAttribute("data-language", "yaml");

    await user.click(
      within(await findTree()).getByRole("button", {
        name: `Actions for ${ITEMS.path}`,
      }),
    );
    await user.click(await screen.findByRole("menuitem", { name: "Rename" }));
    const dialog = await screen.findByRole("dialog", {
      name: `Rename ${ITEMS.path}`,
    });
    const field = within(dialog).getByRole("textbox", { name: "New path" });
    await user.clear(field);
    await user.type(field, LESSON_PATH);
    await user.click(within(dialog).getByRole("button", { name: "Rename" }));

    expect(
      await screen.findByRole("textbox", { name: `Content of ${LESSON_PATH}` }),
    ).toHaveAttribute("data-language", "markdown");
  });
});

describe("the cached lock_version", () => {
  test("stays when the window regains the focus, so a change elsewhere ends in a conflict", async () => {
    const page = renderPage({
      [`GET ${BASE}`]: [ok(draftOf(3)), ok(draftOf(9))],
      [`PUT ${BASE}/files/${PACK.id}`]: stale(9),
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");

    try {
      act(() => {
        focusManager.setFocused(false);
        focusManager.setFocused(true);
      });
      await user.type(editor, "x: 1");
      await user.click(screen.getByRole("button", { name: "Save" }));

      expect(
        await screen.findByRole("dialog", { name: "The draft changed" }),
      ).toBeInTheDocument();
      expect(requestsTo(requests, "GET", BASE)).toHaveLength(1);
      expect(
        requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`)[0].body,
      ).toEqual({ content: `${CONTENT["pack.yaml"]}x: 1`, lock_version: 3 });
    } finally {
      focusManager.setFocused(undefined);
    }
  });
});

describe("leaving with unsaved changes", () => {
  test("opening another file asks first, and Save saves before it opens", async () => {
    const page = renderPage({
      [`PUT ${BASE}/files/${PACK.id}`]: ok(draftOf(4)),
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");

    await user.click(
      within(await findTree()).getByRole("button", { name: "stations.yaml" }),
    );
    let dialog = await screen.findByRole("dialog", { name: "Unsaved changes" });
    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));
    expect(editor).toHaveValue(`${CONTENT["pack.yaml"]}x: 1`);
    expect(
      requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`),
    ).toHaveLength(0);

    await user.click(
      within(await findTree()).getByRole("button", { name: "stations.yaml" }),
    );
    dialog = await screen.findByRole("dialog", { name: "Unsaved changes" });
    expect(dialog).toHaveTextContent(
      "The file pack.yaml has changes that are not saved yet.",
    );
    await user.click(within(dialog).getByRole("button", { name: "Save" }));

    expect(
      await screen.findByRole("textbox", { name: "Content of stations.yaml" }),
    ).toHaveValue(CONTENT["stations.yaml"]);
    expect(
      requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`),
    ).toHaveLength(1);
  });

  test("Save in the question opens the file when an earlier save ended while it was open", async () => {
    const put = gate();
    const page = renderPage({
      [`PUT ${BASE}/files/${PACK.id}`]: async () => {
        await put.opened;
        return ok(draftOf(4));
      },
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");
    await user.click(screen.getByRole("button", { name: "Save" }));
    await user.click(
      within(await findTree()).getByRole("button", { name: "stations.yaml" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Unsaved changes",
    });

    put.open();
    expect(await screen.findByText("Saved pack.yaml")).toBeInTheDocument();
    await user.click(within(dialog).getByRole("button", { name: "Save" }));

    expect(
      await screen.findByRole("textbox", { name: "Content of stations.yaml" }),
    ).toHaveValue(CONTENT["stations.yaml"]);
    expect(
      requestsTo(requests, "PUT", `${BASE}/files/${PACK.id}`),
    ).toHaveLength(1);
  });

  test("a navigation within the SPA asks first, and Discard leaves", async () => {
    const page = renderPage();
    const { user, location } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");

    const trail = screen.getByRole("navigation", { name: "Breadcrumb" });
    await user.click(
      within(trail).getByRole("link", { name: "Pack workbench" }),
    );
    let dialog = await screen.findByRole("dialog", { name: "Unsaved changes" });
    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));
    expect(location()).toBe(`/admin/workbench/${ID}`);
    expect(editor).toHaveValue(`${CONTENT["pack.yaml"]}x: 1`);

    await user.click(
      within(trail).getByRole("link", { name: "Pack workbench" }),
    );
    dialog = await screen.findByRole("dialog", { name: "Unsaved changes" });
    await user.click(within(dialog).getByRole("button", { name: "Discard" }));
    await waitFor(() => expect(location()).toBe("/admin/workbench"));
  });

  test("a reload or a closed tab asks through beforeunload", async () => {
    const page = renderPage();
    const editor = await openFile(page, "pack.yaml", "pack.yaml");

    const clean = new Event("beforeunload", { cancelable: true });
    window.dispatchEvent(clean);
    expect(clean.defaultPrevented).toBe(false);

    await page.user.type(editor, "x: 1");
    const dirty = new Event("beforeunload", { cancelable: true });
    window.dispatchEvent(dirty);
    expect(dirty.defaultPrevented).toBe(true);
  });
});

describe("the dialogs of the tree", () => {
  test("Add file builds a lesson with front matter and one text block and opens it", async () => {
    const LESSON = {
      id: fileId(7),
      path: "modules/01-first-module/lessons/02-second-lesson.md",
    };
    const created = draftOf(4, [...FILES, LESSON]);
    const page = renderPage({
      [`POST ${BASE}/files`]: ok(created, 201),
      [`GET ${BASE}/files/${LESSON.id}`]: ok(
        fileAnswer(LESSON, "---\ntitle: Second lesson\n", 4),
      ),
    });
    const { user, requests } = page;
    const nav = await findTree();
    const add = within(nav).getByRole("button", { name: "Add file" });
    await user.click(add);

    const dialog = await screen.findByRole("dialog", { name: "Add a file" });
    await user.click(
      within(dialog).getByRole("radio", {
        name: "Lesson of a module directory",
      }),
    );
    expect(
      within(dialog).getByRole("combobox", { name: "Module directory" }),
    ).toHaveValue("01-first-module");
    await user.type(
      within(dialog).getByRole("textbox", { name: "Lesson key" }),
      "02-second-lesson",
    );
    await user.type(
      within(dialog).getByRole("textbox", { name: "Lesson title" }),
      "Second lesson",
    );
    expect(within(dialog).getByRole("textbox", { name: "Path" })).toHaveValue(
      LESSON.path,
    );
    await user.click(within(dialog).getByRole("button", { name: "Add file" }));

    expect(
      await screen.findByRole("textbox", { name: `Content of ${LESSON.path}` }),
    ).toHaveValue("---\ntitle: Second lesson\n");
    const [post] = requestsTo(requests, "POST", `${BASE}/files`);
    expect(post.body).toEqual({
      path: LESSON.path,
      content:
        "---\ntitle: Second lesson\nposition: 2\n---\n\n:::text{provenance=invented}\nReplace this text with the content of the lesson.\n:::\n",
      lock_version: 3,
    });
    expect(status()).toContain(`Added ${LESSON.path}`);
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  test("Add file starts a YAML file empty and shows path_taken and invalid_path at the path field", async () => {
    const page = renderPage({
      [`POST ${BASE}/files`]: [
        { status: 409, body: { error: "path_taken" } },
        {
          status: 422,
          body: {
            error: "validation_failed",
            fields: { path: ["invalid_path"] },
          },
        },
      ],
    });
    const { user, requests } = page;
    await user.click(
      within(await findTree()).getByRole("button", { name: "Add file" }),
    );
    const dialog = await screen.findByRole("dialog", { name: "Add a file" });
    const path = within(dialog).getByRole("textbox", { name: "Path" });

    // The first free name of the layout.
    expect(path).toHaveValue("sources.yaml");
    await user.selectOptions(
      within(dialog).getByRole("combobox", { name: "File name" }),
      "pack.yaml",
    );
    await user.click(within(dialog).getByRole("button", { name: "Add file" }));
    expect(
      await within(dialog).findByText(
        "The draft holds a file with this path already.",
      ),
    ).toBeInTheDocument();
    expect(path).toHaveAttribute("aria-invalid", "true");
    expect(path).toHaveAccessibleDescription(
      expect.stringContaining("The draft holds a file with this path already."),
    );
    expect(requestsTo(requests, "POST", `${BASE}/files`)[0].body).toEqual({
      path: "pack.yaml",
      content: "",
      lock_version: 3,
    });

    await user.selectOptions(
      within(dialog).getByRole("combobox", { name: "File name" }),
      "glossary.yaml",
    );
    expect(path).not.toHaveAttribute("aria-invalid");
    await user.click(within(dialog).getByRole("button", { name: "Add file" }));
    expect(
      await within(dialog).findByText(/This path is outside the pack layout/),
    ).toBeInTheDocument();
    expect(path).toHaveAttribute("aria-invalid", "true");

    // A key outside the key format never reaches the server.
    await user.click(
      within(dialog).getByRole("radio", { name: "File of a module directory" }),
    );
    const dir = within(dialog).getByRole("combobox", {
      name: "Module directory",
    });
    await user.clear(dir);
    await user.type(dir, "First Module");
    await user.click(within(dialog).getByRole("button", { name: "Add file" }));
    expect(
      await within(dialog).findByText(/This path is outside the pack layout/),
    ).toBeInTheDocument();
    expect(requestsTo(requests, "POST", `${BASE}/files`)).toHaveLength(2);

    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(
      within(await findTree()).getByRole("button", { name: "Add file" }),
    ).toHaveFocus();
  });

  test("Rename sends PATCH and shows path_taken and invalid_path at the field", async () => {
    const renamed = draftOf(4, [
      ...FILES.filter((entry) => entry !== STATIONS),
      { id: STATIONS.id, path: "formats.yaml" },
    ]);
    const page = renderPage({
      [`PATCH ${BASE}/files/${STATIONS.id}`]: [
        { status: 409, body: { error: "path_taken" } },
        {
          status: 422,
          body: {
            error: "validation_failed",
            fields: { path: ["invalid_path"] },
          },
        },
        ok(renamed),
      ],
    });
    const { user, requests } = page;
    const nav = await findTree();
    await user.click(
      within(nav).getByRole("button", { name: "Actions for stations.yaml" }),
    );
    await user.click(await screen.findByRole("menuitem", { name: "Rename" }));

    const dialog = await screen.findByRole("dialog", {
      name: "Rename stations.yaml",
    });
    const field = within(dialog).getByRole("textbox", { name: "New path" });
    expect(field).toHaveValue("stations.yaml");

    await user.clear(field);
    await user.type(field, "notes.yaml");
    await user.click(within(dialog).getByRole("button", { name: "Rename" }));
    expect(
      await within(dialog).findByText(/This path is outside the pack layout/),
    ).toBeInTheDocument();
    expect(
      requestsTo(requests, "PATCH", `${BASE}/files/${STATIONS.id}`),
    ).toHaveLength(0);

    await user.clear(field);
    await user.type(field, "pack.yaml");
    await user.click(within(dialog).getByRole("button", { name: "Rename" }));
    expect(
      await within(dialog).findByText(
        "The draft holds a file with this path already.",
      ),
    ).toBeInTheDocument();
    expect(field).toHaveAttribute("aria-invalid", "true");

    await user.clear(field);
    await user.type(field, "formats.yaml");
    await user.click(within(dialog).getByRole("button", { name: "Rename" }));
    expect(
      await within(dialog).findByText(/This path is outside the pack layout/),
    ).toBeInTheDocument();

    await user.click(within(dialog).getByRole("button", { name: "Rename" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(
      within(nav).getByRole("button", { name: "formats.yaml" }),
    ).toBeInTheDocument();
    expect(
      requestsTo(requests, "PATCH", `${BASE}/files/${STATIONS.id}`).map(
        (request) => request.body,
      ),
    ).toEqual([
      { path: "pack.yaml", lock_version: 3 },
      { path: "formats.yaml", lock_version: 3 },
      { path: "formats.yaml", lock_version: 3 },
    ]);
    expect(status()).toContain("Renamed stations.yaml to formats.yaml");
  });

  test("Delete sends DELETE with the lock_version and closes the open file", async () => {
    const page = renderPage({
      [`DELETE ${BASE}/files/${STATIONS.id}`]: ok(
        draftOf(
          4,
          FILES.filter((entry) => entry !== STATIONS),
        ),
      ),
    });
    const { user, client, requests } = page;
    const remove = vi.spyOn(client, "DELETE");
    await openFile(page, "stations.yaml", "stations.yaml");
    const nav = await findTree();
    await user.click(
      within(nav).getByRole("button", { name: "Actions for stations.yaml" }),
    );
    await user.click(await screen.findByRole("menuitem", { name: "Delete" }));

    const dialog = await screen.findByRole("dialog", {
      name: "Delete stations.yaml?",
    });
    await user.click(within(dialog).getByRole("button", { name: "Delete" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(remove).toHaveBeenCalledWith(
      "/api/admin/pack-drafts/{id}/files/{file_id}",
      {
        params: {
          path: { id: ID, file_id: STATIONS.id },
          query: { lock_version: 3 },
        },
      },
    );
    expect(
      requestsTo(requests, "DELETE", `${BASE}/files/${STATIONS.id}`),
    ).toHaveLength(1);
    expect(
      within(nav).queryByRole("button", { name: "stations.yaml" }),
    ).toBeNull();
    expect(screen.queryByRole("textbox", { name: /^Content of/ })).toBeNull();
    expect(status()).toContain("Deleted stations.yaml");
  });
});

/** Twelve rows of module 1. */
const matrix = (): AlignmentMatrixRow[] =>
  AREAS.flatMap((area) =>
    DEPTHS.map((depth) => ({
      module: 1,
      area,
      depth,
      objectives: area === "subject" && depth === "know" ? ["m1-subject"] : [],
      lessons: [],
      evidence: [],
      elsewhere: null,
    })),
  );

const alignmentError = {
  file: OBJECTIVES.path,
  line: 9,
  check: 2,
  module: 1,
  key: "m1-subject",
  message: "the objective `m1-subject` has no evidence",
};

function checkAnswer(lockVersion = 3): PackDraftCheck {
  const errors: ReportEntry[] = [
    { file: ITEMS.path, line: 14, message: "unknown objective `m1-x`" },
    { file: ".", line: null, message: "sources.yaml is missing" },
    {
      file: "modules/01-first-module",
      line: null,
      message: "the module directory holds no lesson",
    },
    alignmentError,
    { file: ".", line: 1, message: "and 3 further errors", omitted: 3 },
  ];
  return {
    lock_version: lockVersion,
    report: {
      errors,
      warnings: [{ file: PACK.path, line: 2, message: "the title is long" }],
    },
    alignment: {
      mode: "strict",
      matrix: matrix(),
      errors: [alignmentError],
      warnings: [],
    },
  };
}

describe("the check", () => {
  test("sends the overlay of an unsaved file and lists the entries with their counts", async () => {
    const page = renderPage({
      [`POST ${BASE}/check`]: ok(checkAnswer()),
    });
    const { user, requests } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");
    await user.click(screen.getByRole("button", { name: "Check" }));

    const report = await screen.findByRole("region", { name: "Check report" });
    expect(requestsTo(requests, "POST", `${BASE}/check`)[0].body).toEqual({
      file_id: PACK.id,
      content: `${CONTENT["pack.yaml"]}x: 1`,
    });
    expect(status()).toContain("Check finished: 7 errors, 1 warning");

    // Every line of mix espalier.validate, the alignment finding included,
    // with the count of the announcement.
    const errors = within(report).getByRole("region", { name: "Errors (7)" });
    const items = within(errors).getAllByRole("listitem");
    expect(items.map((item) => item.textContent)).toEqual([
      `${ITEMS.path}, line 14: unknown objective \`m1-x\``,
      "., no line: sources.yaml is missing",
      "modules/01-first-module, no line: the module directory holds no lesson",
      `${OBJECTIVES.path}, line 9: ${alignmentError.message}`,
      "and 3 further errors",
    ]);
    // Entries on "." and on a directory keep their path as text.
    expect(within(items[0]).getByRole("button")).toHaveAccessibleName(
      `${ITEMS.path}, line 14`,
    );
    expect(within(items[3]).getByRole("button")).toHaveAccessibleName(
      `${OBJECTIVES.path}, line 9`,
    );
    for (const item of [items[1], items[2], items[4]])
      expect(within(item).queryByRole("button")).toBeNull();
    expect(
      within(report).getByRole("region", { name: "Warnings (1)" }),
    ).toHaveTextContent(`${PACK.path}, line 2: the title is long`);

    // A later edit of the open file makes the report one of an earlier state.
    expect(
      screen.queryByText(/This report belongs to an earlier state/),
    ).toBeNull();
    await user.type(editor, "y");
    expect(
      within(report).getByText(/This report belongs to an earlier state/),
    ).toBeInTheDocument();
  });

  test("without unsaved changes it sends no overlay, and an entry opens its file at its line", async () => {
    const page = renderPage({
      [`POST ${BASE}/check`]: ok(checkAnswer()),
    });
    const { user, requests } = page;
    await openFile(page, "pack.yaml", "pack.yaml");
    await user.click(screen.getByRole("button", { name: "Check" }));

    const report = await screen.findByRole("region", { name: "Check report" });
    expect(requestsTo(requests, "POST", `${BASE}/check`)[0].body).toEqual({});
    await user.click(
      within(report).getByRole("button", { name: `${ITEMS.path}, line 14` }),
    );

    expect(
      await screen.findByRole("textbox", { name: `Content of ${ITEMS.path}` }),
    ).toHaveValue(CONTENT[ITEMS.path]);
    expect(await screen.findByText("Line 14, column 1")).toBeInTheDocument();
    expect(
      within(await findTree()).getByRole("button", { name: ITEMS_BUTTON }),
    ).toHaveAttribute("aria-current", "true");
    expect(
      screen.queryByText(/This report belongs to an earlier state/),
    ).toBeNull();
  });

  test("the alignment section renders the matrix, and its findings open their file", async () => {
    const page = renderPage({
      [`POST ${BASE}/check`]: ok(checkAnswer()),
    });
    const { user } = page;
    await findTree();
    await user.click(screen.getByRole("button", { name: "Check" }));

    const table = await screen.findByRole("table", {
      name: "Module 1, mode strict",
    });
    expect(within(table).getAllByRole("row")).toHaveLength(13);
    expect(within(table).getByText("m1-subject")).toBeInTheDocument();

    const findings = screen.getByRole("region", {
      name: "Alignment errors (1)",
    });
    await user.click(
      within(findings).getByRole("button", {
        name: `${OBJECTIVES.path}, line 9`,
      }),
    );
    expect(
      await screen.findByRole("textbox", {
        name: `Content of ${OBJECTIVES.path}`,
      }),
    ).toBeInTheDocument();
    expect(await screen.findByText("Line 9, column 1")).toBeInTheDocument();
  });

  test("a check without a matrix says why and lists the alignment findings", async () => {
    const answer = checkAnswer();
    const { user } = renderPage({
      [`POST ${BASE}/check`]: ok({
        ...answer,
        alignment: { ...answer.alignment, matrix: null },
      }),
    });
    await findTree();
    await user.click(screen.getByRole("button", { name: "Check" }));

    expect(
      await screen.findByText(/The check gives no alignment matrix/),
    ).toBeInTheDocument();
    expect(screen.queryByRole("table")).toBeNull();
    expect(
      screen.getByRole("region", { name: "Alignment errors (1)" }),
    ).toHaveTextContent(alignmentError.message);
  });

  test("a report of a lower lock_version belongs to an earlier state", async () => {
    const { user } = renderPage({ [`POST ${BASE}/check`]: ok(checkAnswer(2)) });
    await findTree();
    await user.click(screen.getByRole("button", { name: "Check" }));

    const report = await screen.findByRole("region", { name: "Check report" });
    expect(
      within(report).getByText(/This report belongs to an earlier state/),
    ).toBeInTheDocument();
  });
});

describe("the import", () => {
  test("Create import is disabled with unsaved changes and moves to the pack page", async () => {
    const page = renderPage({
      [`PUT ${BASE}/files/${PACK.id}`]: ok(draftOf(4)),
      [`POST ${BASE}/imports`]: ok({ id: IMPORT_ID, status: "validated" }, 201),
    });
    const { user, requests, location } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");

    const create = screen.getByRole("button", { name: "Create import" });
    expect(create).toBeDisabled();
    expect(create).toHaveAccessibleDescription(
      /Save the open file before you create an import/,
    );

    await user.keyboard("{Control>}s{/Control}");
    await waitFor(() => expect(create).toBeEnabled());
    await user.click(create);

    await waitFor(() => expect(location()).toBe(`/admin/packs/${IMPORT_ID}`));
    expect(requestsTo(requests, "POST", `${BASE}/imports`)[0].body).toEqual({
      lock_version: 4,
    });
  });

  test("a 409 stale_draft on the import opens the conflict dialog", async () => {
    const page = renderPage({
      [`GET ${BASE}`]: [ok(draftOf(3)), ok(draftOf(5))],
      [`POST ${BASE}/imports`]: [stale(5), ok({ id: IMPORT_ID }, 201)],
    });
    const { user, requests, location } = page;
    await findTree();
    await user.click(screen.getByRole("button", { name: "Create import" }));

    const dialog = await screen.findByRole("dialog", {
      name: "The draft changed",
    });
    // Without unsaved changes there is no text to keep.
    expect(
      within(dialog).queryByRole("button", { name: "Keep my version" }),
    ).toBeNull();
    await user.click(
      within(dialog).getByRole("button", { name: "Load the stored version" }),
    );
    await waitFor(() =>
      expect(requestsTo(requests, "GET", BASE)).toHaveLength(2),
    );

    await user.click(screen.getByRole("button", { name: "Create import" }));
    await waitFor(() => expect(location()).toBe(`/admin/packs/${IMPORT_ID}`));
    expect(
      requestsTo(requests, "POST", `${BASE}/imports`).map(
        (request) => request.body,
      ),
    ).toEqual([{ lock_version: 3 }, { lock_version: 5 }]);
  });
});

describe("accessibility", () => {
  test("axe reports no violation with an open file, a report and the matrix", async () => {
    const page = renderPage({
      [`POST ${BASE}/check`]: ok(checkAnswer()),
    });
    const { user, container } = page;
    const editor = await openFile(page, "pack.yaml", "pack.yaml");
    await user.type(editor, "x: 1");
    await user.click(screen.getByRole("button", { name: "Check" }));
    await screen.findByRole("region", { name: "Check report" });

    await expectNoAxeViolations(container);
  });

  test("axe reports no violation in the dialog Add file", async () => {
    const { user } = renderPage();
    await user.click(
      within(await findTree()).getByRole("button", { name: "Add file" }),
    );
    const dialog = await screen.findByRole("dialog", { name: "Add a file" });
    await user.click(
      within(dialog).getByRole("radio", {
        name: "Lesson of a module directory",
      }),
    );

    // The page around the dialog is inert; its own scan is the test above.
    await expectNoAxeViolations(dialog);
  });
});

describe("loading", () => {
  test("an unknown draft says so", async () => {
    renderWithProviders(<DraftPage />, {
      route: `/admin/workbench/${ID}`,
      path: "/admin/workbench/:id",
      session: author,
    });

    expect(
      await screen.findByText("This draft does not exist."),
    ).toHaveAttribute("role", "alert");
    expect(
      screen.getByRole("link", { name: "Back to the workbench" }),
    ).toHaveAttribute("href", "/admin/workbench");
  });
});

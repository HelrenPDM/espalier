import { AxeBuilder } from "@axe-core/playwright";
import { expect, test, type Locator, type Page } from "@playwright/test";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "vite";

// The editor spike of task 0016a, step 1. The Vite dev server sends no CSP
// and injects style elements, so the spec builds the harness with the
// configuration of vite.config.ts and serves the build with the two policy
// headers that Phoenix sends on GET /health (EspalierWeb.Plugs.SecurityHeaders).
// Both editors then run under `style-src 'self'` and the report-only header
// `require-trusted-types-for 'script'` of README section 6.5.

const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

const FRONTEND = fileURLToPath(new URL("../..", import.meta.url));
const HARNESS = fileURLToPath(new URL("harness", import.meta.url));

const YAML_PATH = "modules/01-first-module/objectives.yaml";
const MARKDOWN_PATH = "modules/01-first-module/lessons/01-first-lesson.md";
// A file taller than the frame, whose Ctrl+S opens a dialog.
const TALL_PATH = "modules/01-first-module/items.yaml";

const CONTENT_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
};

// The browser globals that the functions below use inside the page; the
// specs compile without the DOM library.
declare const getComputedStyle: (element: unknown) => { color: string };

/** Collects every `securitypolicyviolation` event of the page. */
const COLLECT_VIOLATIONS = `
  window.__violations = [];
  document.addEventListener(
    "securitypolicyviolation",
    (event) => {
      window.__violations.push({
        directive: event.violatedDirective,
        effectiveDirective: event.effectiveDirective,
        disposition: event.disposition,
        blockedURI: event.blockedURI,
        sample: event.sample,
      });
    },
    true,
  );
`;

interface Violation {
  directive: string;
  effectiveDirective: string;
  disposition: string;
  blockedURI: string;
  sample: string;
}

let outDir: string;
let server: Server;
let origin: string;

test.beforeAll(async ({ playwright }, testInfo) => {
  test.setTimeout(120_000);

  // The policy headers as Phoenix sends them through the Vite proxy.
  const api = await playwright.request.newContext({
    baseURL: testInfo.project.use.baseURL,
  });
  const health = await api.get("/health");
  expect(health.ok()).toBe(true);
  const policy = health.headers()["content-security-policy"];
  const reportOnly = health.headers()["content-security-policy-report-only"];
  await api.dispose();
  // The checks of the spike rest on these two directives.
  expect(policy).toContain("style-src 'self'");
  expect(reportOnly).toContain("require-trusted-types-for 'script'");

  outDir = await mkdtemp(join(tmpdir(), "espalier-editor-harness-"));
  await build({
    configFile: join(FRONTEND, "vite.config.ts"),
    root: HARNESS,
    base: "/",
    logLevel: "warn",
    // The harness is one chunk with React and every language of the editor.
    build: { outDir, emptyOutDir: true, chunkSizeWarningLimit: 2048 },
  });

  server = createServer((request, response) => {
    const { pathname } = new URL(request.url ?? "/", "http://127.0.0.1");
    const path = resolve(
      outDir,
      `.${decodeURIComponent(pathname === "/" ? "/index.html" : pathname)}`,
    );
    const headers = {
      "content-security-policy": policy,
      "content-security-policy-report-only": reportOnly,
    };
    if (!path.startsWith(outDir + sep)) {
      response.writeHead(404, headers).end();
      return;
    }
    readFile(path).then(
      (body) =>
        response
          .writeHead(200, {
            ...headers,
            "content-type":
              CONTENT_TYPES[extname(path)] ?? "application/octet-stream",
          })
          .end(body),
      () => response.writeHead(404, headers).end(),
    );
  });
  await new Promise<void>((listening) =>
    server.listen(0, "127.0.0.1", listening),
  );
  origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

test.afterAll(async () => {
  await new Promise((closed) => server?.close(closed));
  if (outDir) await rm(outDir, { recursive: true, force: true });
});

interface Harness {
  /** The violation events and the console messages about a policy. */
  policyFindings: () => Promise<{ events: Violation[]; console: string[] }>;
}

async function openHarness(page: Page): Promise<Harness> {
  const messages: string[] = [];
  page.on("console", (message) => messages.push(message.text()));
  page.on("pageerror", (error) => messages.push(error.message));
  await page.addInitScript({ content: COLLECT_VIOLATIONS });
  await page.goto(`${origin}/`);
  await expect(
    page.getByRole("heading", { name: "Editor harness" }),
  ).toBeVisible();
  return {
    policyFindings: async () => {
      // Violation events are queued as tasks; let them run first.
      await page.evaluate(
        "new Promise((done) => requestAnimationFrame(() => setTimeout(done, 100)))",
      );
      const events = (await page.evaluate(
        "window.__violations",
      )) as Violation[];
      return {
        events,
        console: messages.filter((text) =>
          /content security policy|trusted ?type|policy/i.test(text),
        ),
      };
    },
  };
}

const editorOf = (page: Page, path: string): Locator =>
  page.getByRole("textbox", { name: `Content of ${path}` });

const linesOf = (editor: Locator): Promise<string[]> =>
  editor.locator(".cm-line").allTextContents();

/** The text that the spec types at the end of each editor. */
const TYPED = "\nadded: line\nsecond: line\nthird: line";

const lengthOf = async (page: Page, id: string): Promise<number> => {
  const text = await page.getByTestId(`${id}-length`).textContent();
  return Number(/(\d+)/.exec(text ?? "")?.[1]);
};

test("both editors run under the CSP with no violation and highlight the YAML text", async ({
  page,
}) => {
  const harness = await openHarness(page);

  for (const [id, path] of [
    ["yaml", YAML_PATH],
    ["markdown", MARKDOWN_PATH],
  ] as const) {
    const editor = editorOf(page, path);
    await expect(editor).toBeVisible();
    const initial = await lengthOf(page, id);
    const lines = await linesOf(editor);

    // Type lines at the end of the document, at the speed of Playwright:
    // every key arrives in the editor and the cursor stays at its place.
    await editor.click();
    await page.keyboard.press("ControlOrMeta+End");
    await page.keyboard.type(TYPED);
    await expect(page.getByTestId(`${id}-length`)).toHaveText(
      `Characters: ${initial + TYPED.length}`,
    );
    await expect
      .poll(() => linesOf(editor))
      .toEqual([...lines, ...TYPED.split("\n").slice(1)]);

    // Select the last typed line and undo the typing.
    await page.keyboard.press("Shift+Home");
    await page.keyboard.press("ControlOrMeta+z");
    await expect
      .poll(() => lengthOf(page, id))
      .toBeLessThan(initial + TYPED.length);

    // Move through the lines: the cursor status follows.
    await page.keyboard.press("ControlOrMeta+Home");
    await expect(page.getByTestId(`${id}-cursor`)).toHaveText(
      "Line 1, column 1",
    );
    for (let line = 2; line <= 4; line++) {
      await page.keyboard.press("ArrowDown");
      await expect(page.getByTestId(`${id}-cursor`)).toHaveText(
        `Line ${line}, column 1`,
      );
    }
    await page.keyboard.press("End");
    await expect(page.getByTestId(`${id}-cursor`)).not.toHaveText(
      "Line 4, column 1",
    );

    // Mod-s saves.
    await page.keyboard.press("ControlOrMeta+s");
    await expect(page.getByTestId(`${id}-saves`)).toHaveText("Saves: 1");
  }

  // A highlighted token of the YAML text has a color of its own.
  const yaml = editorOf(page, YAML_PATH);
  const plain = await yaml
    .locator(".cm-line")
    .first()
    .evaluate((element) => getComputedStyle(element).color);
  const key = yaml.locator(".cm-line span", { hasText: /^key$/ }).first();
  await expect(key).toBeVisible();
  const keyColor = await key.evaluate(
    (element) => getComputedStyle(element).color,
  );
  expect(keyColor).not.toBe(plain);

  const findings = await harness.policyFindings();
  expect(findings.events).toEqual([]);
  expect(
    findings.events.filter(
      (event) => event.directive === "require-trusted-types-for",
    ),
  ).toEqual([]);
  expect(findings.console).toEqual([]);
});

test("the editor is a named multi-line textbox that Tab and Shift+Tab leave", async ({
  page,
}) => {
  const harness = await openHarness(page);

  for (const path of [YAML_PATH, MARKDOWN_PATH, TALL_PATH]) {
    const editor = editorOf(page, path);
    await expect(editor).toHaveAttribute("role", "textbox");
    await expect(editor).toHaveAttribute("aria-multiline", "true");
    await expect(editor).toHaveAccessibleName(`Content of ${path}`);

    // One tab stop: Tab from the control before the editor lands on its
    // content, and the next Tab leaves it; Shift+Tab walks back the same way.
    const before = page.getByRole("button", {
      name: `Go to line 4 of ${path}`,
    });
    const after = page.getByRole("button", { name: `Reset ${path}` });
    await before.focus();
    await page.keyboard.press("Tab");
    await expect(editor).toBeFocused();
    await page.keyboard.press("Tab");
    await expect(after).toBeFocused();
    await page.keyboard.press("Shift+Tab");
    await expect(editor).toBeFocused();
    await page.keyboard.press("Shift+Tab");
    await expect(before).toBeFocused();

    const lines = await linesOf(editor);
    await editor.click();
    await page.keyboard.press("Tab");
    await expect(
      page.getByRole("button", { name: `Reset ${path}` }),
    ).toBeFocused();
    expect(await linesOf(editor)).toEqual(lines);

    await editor.click();
    await page.keyboard.press("Shift+Tab");
    await expect(
      page.getByRole("button", { name: `Go to line 4 of ${path}` }),
    ).toBeFocused();
    expect(await linesOf(editor)).toEqual(lines);
  }

  expect((await harness.policyFindings()).events).toEqual([]);
});

test("a dialog that Ctrl+S opens returns the focus to the editor content", async ({
  page,
}) => {
  const harness = await openHarness(page);
  const editor = editorOf(page, TALL_PATH);
  const dialog = page.getByRole("dialog", { name: `Saved ${TALL_PATH}` });
  const closeButton = dialog.getByRole("button", { name: "Close" });
  await editor.click();
  await page.keyboard.press("ControlOrMeta+End");

  // Headless UI records the frame, the host of the shadow root, as the
  // focused element and focuses it again when the dialog closes.
  for (const close of ["Escape", "button"] as const) {
    await page.keyboard.press("ControlOrMeta+s");
    // The root of the dialog has no size of its own; its panel is fixed.
    await expect(closeButton).toBeFocused();
    if (close === "Escape") await page.keyboard.press("Escape");
    else await closeButton.click();
    await expect(dialog).toHaveCount(0);
    await expect(editor).toBeFocused();

    // The keyboard goes on in the editor.
    const length = await lengthOf(page, "tall");
    await page.keyboard.type("x");
    await expect(page.getByTestId("tall-length")).toHaveText(
      `Characters: ${length + 1}`,
    );
  }

  expect((await harness.policyFindings()).events).toEqual([]);
});

test("Mod-] indents and Mod-[ dedents the selected lines", async ({ page }) => {
  const harness = await openHarness(page);
  const editor = editorOf(page, YAML_PATH);
  const lines = await linesOf(editor);

  await editor.click();
  await page.keyboard.press("ControlOrMeta+Home");
  // Select from the start of line 2 to the end of line 3.
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Shift+ArrowDown");
  await page.keyboard.press("Shift+End");
  await page.keyboard.press("ControlOrMeta+]");
  await expect
    .poll(() => linesOf(editor))
    .toEqual([lines[0], `  ${lines[1]}`, `  ${lines[2]}`, ...lines.slice(3)]);

  await page.keyboard.press("ControlOrMeta+[");
  await expect.poll(() => linesOf(editor)).toEqual(lines);

  expect((await harness.policyFindings()).events).toEqual([]);
});

test("goTo moves the cursor to the start of the line and focuses the editor", async ({
  page,
}) => {
  await openHarness(page);
  for (const [id, path] of [
    ["yaml", YAML_PATH],
    ["markdown", MARKDOWN_PATH],
  ] as const) {
    await page.getByRole("button", { name: `Go to line 4 of ${path}` }).click();
    await expect(page.getByTestId(`${id}-cursor`)).toHaveText(
      "Line 4, column 1",
    );
    await expect(editorOf(page, path)).toBeFocused();
  }
});

test("axe reports no violation on the harness, light and dark", async ({
  page,
}) => {
  const harness = await openHarness(page);
  const light = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
  expect(light.violations).toEqual([]);

  await page.evaluate("document.documentElement.classList.add('dark')");
  const dark = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
  expect(dark.violations).toEqual([]);

  expect((await harness.policyFindings()).events).toEqual([]);
});

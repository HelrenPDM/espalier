import { afterEach, beforeEach, expect, test, vi } from "vitest";

/** A media query list whose `matches` the test changes. */
function fakeMediaQuery(matches: boolean) {
  const listeners = new Set<() => void>();
  return {
    matches,
    addEventListener: (_type: string, listener: () => void) =>
      listeners.add(listener),
    removeEventListener: (_type: string, listener: () => void) =>
      listeners.delete(listener),
    change(next: boolean) {
      this.matches = next;
      for (const listener of listeners) listener();
    },
  };
}

let media: ReturnType<typeof fakeMediaQuery>;

// A fresh module per test, because the module keeps the choice of the page.
const loadTheme = () => import("./theme");

beforeEach(() => {
  vi.resetModules();
  media = fakeMediaQuery(false);
  vi.stubGlobal("matchMedia", () => media);
  // Blocked storage: every read and write of the Storage API throws.
  const blocked = () => {
    throw new DOMException("The storage is blocked.", "SecurityError");
  };
  vi.spyOn(Storage.prototype, "getItem").mockImplementation(blocked);
  vi.spyOn(Storage.prototype, "setItem").mockImplementation(blocked);
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  document.documentElement.classList.remove("dark");
});

test("with blocked storage, the setting starts as system", async () => {
  const { readTheme } = await loadTheme();

  expect(readTheme()).toBe("system");
});

test.each(["light", "dark"] as const)(
  "with blocked storage, a chosen %s holds against a change of the system preference",
  async (setting) => {
    const { applyTheme, followSystemTheme, readTheme, storeTheme } =
      await loadTheme();
    const stop = followSystemTheme();
    storeTheme(setting);
    applyTheme(setting);

    media.change(setting === "light");

    expect(readTheme()).toBe(setting);
    expect(document.documentElement.classList.contains("dark")).toBe(
      setting === "dark",
    );
    stop();
  },
);

test("with blocked storage, a chosen system follows the system preference", async () => {
  const { applyTheme, followSystemTheme, storeTheme } = await loadTheme();
  const stop = followSystemTheme();
  storeTheme("dark");
  storeTheme("system");
  applyTheme("system");

  media.change(true);
  expect(document.documentElement).toHaveClass("dark");
  media.change(false);
  expect(document.documentElement).not.toHaveClass("dark");
  stop();
});

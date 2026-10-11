// The color theme: `light`, `dark` or `system` under the localStorage key
// `theme`. `system` follows `prefers-color-scheme`. Storage can be blocked,
// so every access sits in try/catch and falls back to `system`.

export type ThemeSetting = "system" | "light" | "dark";

const STORAGE_KEY = "theme";
const SETTINGS: readonly ThemeSetting[] = ["system", "light", "dark"];
const DARK_QUERY = "(prefers-color-scheme: dark)";

export function readTheme(): ThemeSetting {
  try {
    const value = localStorage.getItem(STORAGE_KEY);
    return SETTINGS.find((setting) => setting === value) ?? "system";
  } catch {
    return "system";
  }
}

export function storeTheme(setting: ThemeSetting): void {
  try {
    localStorage.setItem(STORAGE_KEY, setting);
  } catch {
    // The setting then lasts until the page reloads.
  }
}

export function nextTheme(setting: ThemeSetting): ThemeSetting {
  return SETTINGS[(SETTINGS.indexOf(setting) + 1) % SETTINGS.length];
}

function systemPrefersDark(): boolean {
  return (
    typeof window.matchMedia === "function" &&
    window.matchMedia(DARK_QUERY).matches
  );
}

/** Sets the `dark` class on `<html>`, which the `dark:` variant reads. */
export function applyTheme(setting: ThemeSetting = readTheme()): void {
  const dark =
    setting === "dark" || (setting === "system" && systemPrefersDark());
  document.documentElement.classList.toggle("dark", dark);
}

/** Follows a change of the system preference while the setting is `system`. */
export function followSystemTheme(): () => void {
  if (typeof window.matchMedia !== "function") return () => {};
  const media = window.matchMedia(DARK_QUERY);
  const onChange = () => {
    if (readTheme() === "system") applyTheme("system");
  };
  media.addEventListener("change", onChange);
  return () => media.removeEventListener("change", onChange);
}

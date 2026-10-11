/**
 * The path to open after sign-in. Only a path on the application's own
 * origin passes (ASVS 1.2.2, 3.7.2): it starts with `/`, its second
 * character is no `/`, and it holds no backslash and no character below
 * U+0020. Browsers read `//host` and `/\host` as another host and drop tabs
 * and line breaks from URLs. Every other value, among them `javascript:` and
 * every other scheme, yields `/`.
 */
export function safeReturnTo(value: string | null): string {
  if (value === null || !value.startsWith("/") || value.charAt(1) === "/")
    return "/";
  if (value.includes("\\")) return "/";
  for (let index = 0; index < value.length; index++) {
    if (value.charCodeAt(index) < 0x20) return "/";
  }
  return value;
}

/**
 * The `sessionStorage` key of the return path across an OIDC redirect
 * (ASVS 14.3.3). It holds a path and nothing else.
 */
const RETURN_TO_KEY = "espalier.return_to";

/** Keeps `path`, checked by `safeReturnTo`, until `takeReturnTo()` reads it. */
export function rememberReturnTo(path: string): void {
  try {
    sessionStorage.setItem(RETURN_TO_KEY, safeReturnTo(path));
  } catch {
    // Blocked storage: the flow ends on the start page.
  }
}

/** Returns and deletes the remembered path, or `null` when none is stored. */
export function takeReturnTo(): string | null {
  try {
    const value = sessionStorage.getItem(RETURN_TO_KEY);
    sessionStorage.removeItem(RETURN_TO_KEY);
    return value === null ? null : safeReturnTo(value);
  } catch {
    return null;
  }
}

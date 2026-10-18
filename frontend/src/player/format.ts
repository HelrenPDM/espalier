/** A date of the API (`YYYY-MM-DD`) in the date format of `language`. */
export function formatDay(value: string, language: string): string {
  const date = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(language, {
    dateStyle: "medium",
    timeZone: "UTC",
  }).format(date);
}

/**
 * The URL of an external video file or an embed player, which the player
 * sets as the `src` of a `<source>` or an `<iframe>` (ASVS 1.2.2): an
 * absolute `https:` URL without user info, in its parsed form. Every other
 * value, a relative URL, `http:`, `javascript:` or `data:` among them,
 * gives `null`, and the block shows its notice in place of the video.
 */
export function safeMediaUrl(url: string | null | undefined): string | null {
  if (url === null || url === undefined) return null;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" &&
      parsed.username === "" &&
      parsed.password === "" &&
      parsed.host !== ""
      ? parsed.href
      : null;
  } catch {
    return null;
  }
}

/** Only an `http` or `https` URL of a source becomes a link (ASVS 1.2.2). */
export function safeSourceUrl(url: string | null): string | null {
  if (url === null) return null;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" || parsed.protocol === "http:"
      ? parsed.href
      : null;
  } catch {
    return null;
  }
}

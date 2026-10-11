/** A date of the API (`YYYY-MM-DD`) in the date format of `language`. */
export function formatDay(value: string, language: string): string {
  const date = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(language, {
    dateStyle: "medium",
    timeZone: "UTC",
  }).format(date);
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

/** A timestamp of the API in the date and time format of `language`. */
export function formatDateTime(value: string, language: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(language, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

/** A timestamp of the API as a date in the format of `language`. */
export function formatDate(value: string | Date, language: string): string {
  const date = typeof value === "string" ? new Date(value) : value;
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat(language, { dateStyle: "medium" }).format(
    date,
  );
}

import { ArrowUpTrayIcon } from "@heroicons/react/24/outline";
import { useEffect, useId, useRef, useState, type DragEvent } from "react";
import { useTranslation } from "react-i18next";
import { isApiError } from "../../api/admin/fieldErrors";
import {
  acceptFor,
  useUploadMedia,
  type MediaKind,
  type UploadedMedia,
} from "../../api/admin/media";
import {
  ENROLLMENT_ERROR_CODE,
  RECENT_AUTH_ERROR_CODE,
} from "../../api/errors";
import { FOCUS_RING } from "../../app/formStyles";
import { useUploadErrorText } from "./mediaText";

/** One file of the upload list and its state. */
interface UploadEntry {
  key: number;
  name: string;
  state: "waiting" | "sending" | "done" | "failed";
  loaded: number;
  total: number;
  result: UploadedMedia | null;
  error: string | null;
}

const MUTED = "text-gray-700 dark:text-gray-300";

/**
 * The text key of the waiting files after a failure that ends the queue, or
 * `null` when the next file goes out: a closed step-up dialog, an ended
 * session (401, after which the app shows the sign-in) and an account
 * without a second factor (403 `enrollment_required`, after which the app
 * shows the enrollment) send none of them.
 */
function notSentKey(error: unknown) {
  if (isApiError(error, 403, RECENT_AUTH_ERROR_CODE))
    return "admin.media.upload.notSent" as const;
  if (isApiError(error, 401))
    return "admin.media.upload.notSentSignedOut" as const;
  if (isApiError(error, 403, ENROLLMENT_ERROR_CODE))
    return "admin.media.upload.notSentEnrollment" as const;
  return null;
}

/**
 * The upload of files to the media library (task 0018, step 19): a file
 * input with a visible label inside a zone that also takes dropped files,
 * and a list with a progress bar and the outcome per file. The files go
 * out one after the other through `uploadMedia`, so the step-up dialog
 * opens at most once before the first body; when the person closes it,
 * when the session has ended, or when the account still needs a second
 * factor, the files that wait are not sent either (`notSentKey`). A zone
 * that leaves the page sends no further file. File names render as text.
 *
 * The list is a status region whose entries are atomic each, so a new
 * state of a file announces that file only; the progress bar carries the
 * sent bytes without announcing them.
 */
export function UploadZone({
  kinds,
  multiple = true,
  onUploaded,
}: {
  /** The kinds that the file input offers (`accept`). */
  kinds: readonly MediaKind[];
  multiple?: boolean;
  /** Called with each finished upload, a new or an existing asset. */
  onUploaded?: (uploaded: UploadedMedia) => void;
}) {
  const { t } = useTranslation();
  const inputId = useId();
  const hintId = useId();
  const listLabelId = useId();
  const upload = useUploadMedia();
  const errorText = useUploadErrorText();
  const [entries, setEntries] = useState<UploadEntry[]>([]);
  const [dragging, setDragging] = useState(false);
  const queue = useRef<{ key: number; file: File }[]>([]);
  const running = useRef(false);
  const mounted = useRef(false);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);
  const nextKey = useRef(0);
  const latestUploaded = useRef(onUploaded);
  useEffect(() => {
    latestUploaded.current = onUploaded;
  });

  const update = (key: number, change: Partial<UploadEntry>) =>
    setEntries((current) =>
      current.map((entry) =>
        entry.key === key ? { ...entry, ...change } : entry,
      ),
    );

  const run = async () => {
    if (running.current) return;
    running.current = true;
    try {
      for (
        let next = queue.current.shift();
        next;
        next = queue.current.shift()
      ) {
        // A zone that has left the page, such as for the sign-in, sends
        // none of the files that wait.
        if (!mounted.current) {
          queue.current = [];
          break;
        }
        const { key, file } = next;
        update(key, { state: "sending" });
        try {
          const result = await upload(file, (loaded, total) =>
            update(key, { loaded, total }),
          );
          update(key, { state: "done", result, loaded: file.size });
          latestUploaded.current?.(result);
        } catch (error) {
          update(key, { state: "failed", error: errorText(error) });
          const notSent = notSentKey(error);
          if (notSent !== null) {
            const skipped = new Set(queue.current.map((entry) => entry.key));
            queue.current = [];
            setEntries((current) =>
              current.map((entry) =>
                skipped.has(entry.key)
                  ? { ...entry, state: "failed", error: t(notSent) }
                  : entry,
              ),
            );
          }
        }
      }
    } finally {
      running.current = false;
    }
  };

  const add = (files: readonly File[]) => {
    const chosen = multiple ? files : files.slice(0, 1);
    if (chosen.length === 0) return;
    const added = chosen.map((file) => ({ key: nextKey.current++, file }));
    queue.current.push(...added);
    setEntries((current) => [
      ...current,
      ...added.map(({ key, file }): UploadEntry => ({
        key,
        name: file.name,
        state: "waiting",
        loaded: 0,
        total: file.size,
        result: null,
        error: null,
      })),
    ]);
    void run();
  };

  const drop = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setDragging(false);
    add(Array.from(event.dataTransfer.files));
  };

  const entryText = (entry: UploadEntry) => {
    switch (entry.state) {
      case "waiting":
        return t("admin.media.upload.waiting");
      case "sending":
        return t("admin.media.upload.sending");
      case "done":
        return entry.result?.created
          ? t("admin.media.upload.created")
          : t("admin.media.upload.existing", {
              title: entry.result?.asset.title ?? "",
            });
      case "failed":
        return entry.error ?? "";
    }
  };

  return (
    <div className="space-y-4">
      <div
        onDragOver={(event) => {
          event.preventDefault();
          setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={drop}
        className={`flex flex-col items-start gap-3 rounded-lg border-2 border-dashed p-4 sm:flex-row sm:items-center ${
          dragging
            ? "border-accent-600 bg-accent-50 dark:border-accent-500 dark:bg-gray-800"
            : "border-gray-400 dark:border-gray-600"
        }`}
      >
        <ArrowUpTrayIcon
          aria-hidden="true"
          className="size-8 shrink-0 text-gray-500 dark:text-gray-400"
        />
        <div className="min-w-0 space-y-1">
          <label
            htmlFor={inputId}
            className="block text-sm font-medium text-gray-900 dark:text-gray-100"
          >
            {multiple
              ? t("admin.media.upload.label")
              : t("admin.media.upload.labelOne")}
          </label>
          <input
            id={inputId}
            type="file"
            multiple={multiple}
            accept={acceptFor(kinds)}
            aria-describedby={hintId}
            onChange={(event) => {
              add(Array.from(event.target.files ?? []));
              // The same file can be chosen again after a failure.
              event.target.value = "";
            }}
            className={`block w-full text-sm text-gray-900 file:mr-3 file:rounded-md file:border file:border-gray-500 file:bg-white file:px-3 file:py-1.5 file:text-sm file:font-semibold file:text-gray-900 dark:text-gray-100 dark:file:bg-gray-900 dark:file:text-gray-100 ${FOCUS_RING}`}
          />
          <p id={hintId} className={`text-sm ${MUTED}`}>
            {t("admin.media.upload.hint", {
              extensions: acceptFor(kinds).split(",").join(", "),
            })}
          </p>
        </div>
      </div>
      <div
        role="status"
        aria-labelledby={listLabelId}
        aria-atomic="false"
        className={entries.length === 0 ? "sr-only" : undefined}
      >
        <p id={listLabelId} className="sr-only">
          {t("admin.media.upload.listLabel")}
        </p>
        {entries.length > 0 && (
          <ul className="space-y-2">
            {entries.map((entry) => (
              <li
                key={entry.key}
                aria-atomic="true"
                data-state={entry.state}
                className="rounded-md border border-gray-300 px-3 py-2 text-sm dark:border-gray-700"
              >
                <p className="font-mono text-xs break-all text-gray-900 dark:text-gray-100">
                  {entry.name}
                </p>
                <progress
                  max={Math.max(entry.total, 1)}
                  value={
                    entry.state === "done"
                      ? Math.max(entry.total, 1)
                      : entry.loaded
                  }
                  aria-label={t("admin.media.upload.progressLabel", {
                    name: entry.name,
                  })}
                  className="mt-1 h-2 w-full accent-accent-600"
                />
                <p
                  className={
                    entry.state === "failed"
                      ? "mt-1 text-red-700 dark:text-red-300"
                      : `mt-1 ${MUTED}`
                  }
                >
                  {entryText(entry)}
                </p>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

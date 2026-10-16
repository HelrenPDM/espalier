import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { ApiError, unwrap } from "../errors";
import type { components } from "../schema";
import { mediaPollInterval } from "./media";

/**
 * The pack routes of the role `author` (task 0015, steps 7 and 11):
 * upload, the import with its report, payload and alignment, the diff
 * against the live program, and the publication. The packs pages under
 * `src/admin/packs/` read them through these hooks.
 */
export type PackImport = components["schemas"]["AdminPackImport"];
export type PackDiff = components["schemas"]["AdminPackDiff"];
export type AlignmentMatrixRow =
  components["schemas"]["AdminAlignmentMatrixRow"];
export type AlignmentFinding = components["schemas"]["AdminAlignmentFinding"];
export type AlignmentCheckFinding =
  components["schemas"]["AdminAlignmentCheckFinding"];
export type ReportEntry = components["schemas"]["AdminReportEntry"];
export type ArchiveRejected = components["schemas"]["AdminArchiveRejected"];
export type AlignmentErrors = components["schemas"]["AdminAlignmentErrors"];
/** A media file of an import, keyed by its `media/` path (task 0018, step 10). */
export type PackMedia = components["schemas"]["AdminPackMedia"];
export type PackMediaStatus = PackMedia["status"];
export type MediaNotReady = components["schemas"]["AdminMediaNotReady"];
export type MediaNotReadyEntry = MediaNotReady["media"][number];

export const packsQueryKey = ["admin", "packs"] as const;

export const packQueryKey = (id: string) => [...packsQueryKey, id] as const;

const packDiffQueryKey = (id: string) => [...packQueryKey(id), "diff"] as const;

/**
 * `GET /api/admin/packs/:id`: status, report, payload, alignment and media
 * of an import. It reads the import again every two seconds while one of
 * its media files is `queued` or `processing` (task 0018, step 10), so the
 * media section and the publish button follow the conversion.
 */
export function usePackImport(id: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: packQueryKey(id),
    queryFn: async (): Promise<PackImport> =>
      unwrap(
        await client.GET("/api/admin/packs/{id}", {
          params: { path: { id } },
        }),
      ),
    refetchInterval: (query) =>
      mediaPollInterval(
        query.state.data === undefined
          ? undefined
          : Object.values(query.state.data.media).map((entry) => entry.status),
        query.state.error,
      ),
  });
}

/**
 * `GET /api/admin/packs/:id/diff`: the added, changed and archived keys per
 * kind against the live program. It loads only while `enabled`, so the
 * publish dialog reads it when it opens, and it is never cached as fresh.
 */
export function usePackDiff(id: string, { enabled }: { enabled: boolean }) {
  const client = useApiClient();
  return useQuery({
    enabled,
    staleTime: 0,
    gcTime: 0,
    queryKey: packDiffQueryKey(id),
    queryFn: async (): Promise<PackDiff> =>
      unwrap(
        await client.GET("/api/admin/packs/{id}/diff", {
          params: { path: { id } },
        }),
      ),
  });
}

/**
 * `POST /api/admin/packs`: sends the archive as `multipart/form-data` with
 * the field `file` through the typed client, so the CSRF header and the
 * step-up of a `reauth_required` answer apply. A rejected archive throws an
 * `ApiError` whose body is the `AdminArchiveRejected` answer.
 */
export function useUploadPack() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (file: File): Promise<PackImport> =>
      unwrap(
        await client.POST("/api/admin/packs", {
          // The schema types the binary field as a string; the serializer
          // below sends the file itself.
          body: { file: file.name },
          bodySerializer: () => {
            const form = new FormData();
            form.append("file", file, file.name);
            return form;
          },
        }),
      ),
    onSuccess: (pack) => queryClient.setQueryData(packQueryKey(pack.id), pack),
  });
}

/**
 * `POST /api/admin/packs/:id/publish`. A 409 throws an `ApiError` whose body
 * is the `AdminAlignmentErrors` answer (`not_publishable`, or
 * `alignment_errors` with its findings) or the `AdminMediaNotReady` answer
 * of task 0018 with the media files that are not ready.
 */
export function usePublishPack(id: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (): Promise<PackImport> =>
      unwrap(
        await client.POST("/api/admin/packs/{id}/publish", {
          params: { path: { id } },
          body: {},
        }),
      ),
    onSuccess: (pack) => {
      queryClient.setQueryData(packQueryKey(id), pack);
      queryClient.removeQueries({ queryKey: packDiffQueryKey(id) });
    },
    // The media states of the page are older than the refusal; reading
    // the import again shows them and restarts the polling.
    onError: (error) => {
      if (
        error instanceof ApiError &&
        mediaNotReadyEntries(error.body) !== null
      )
        void queryClient.invalidateQueries({
          queryKey: packQueryKey(id),
          exact: true,
        });
    },
  });
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The report of an `archive_rejected` body, or `null` for any other body. */
export function archiveReport(body: unknown): ReportEntry[] | null {
  if (!isRecord(body) || body.error !== "archive_rejected") return null;
  const report = body.report;
  if (!isRecord(report) || !Array.isArray(report.errors)) return null;
  return report.errors.filter(isRecord) as ReportEntry[];
}

/**
 * The entries of a 409 `media_not_ready` body, or `null` for any other
 * body. Each entry keeps its path, status and failure as the server sent
 * them; the dialog renders them as text.
 */
export function mediaNotReadyEntries(
  body: unknown,
): MediaNotReadyEntry[] | null {
  if (!isRecord(body) || body.error !== "media_not_ready") return null;
  return Array.isArray(body.media)
    ? (body.media.filter(
        (entry) => isRecord(entry) && typeof entry.path === "string",
      ) as MediaNotReadyEntry[])
    : [];
}

/** The findings of an `alignment_errors` body, or `null` for any other body. */
export function alignmentErrorFindings(
  body: unknown,
): AlignmentCheckFinding[] | null {
  if (!isRecord(body) || body.error !== "alignment_errors") return null;
  return Array.isArray(body.findings)
    ? (body.findings.filter(isRecord) as AlignmentCheckFinding[])
    : [];
}

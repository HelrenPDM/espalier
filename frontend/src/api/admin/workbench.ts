import {
  queryOptions,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { useCallback } from "react";
import { useApiClient } from "../apiClientContext";
import type { ApiClient } from "../client";
import { ApiError, unwrap } from "../errors";
import type { components } from "../schema";
import {
  invalidateMediaLists,
  MEDIA_POLL_INTERVAL,
  mediaAssetQueryKey,
  mediaInProgress,
  mediaPollInterval,
} from "./media";
import { packQueryKey, type PackImport } from "./packs";

/**
 * The routes of the pack workbench for the role `author` (task 0016a,
 * steps 9 and 11): the drafts, their files, the check, the import and the
 * download. The pages under `src/admin/workbench/` read them through these
 * hooks. Every change hook writes the returned draft into the cache of
 * `useDraft(id)`, so the page always holds the newest `lock_version`.
 *
 * The changes run in `:author_write`: the API client of task 0011 opens the
 * step-up dialog on a 403 `reauth_required` and repeats the request once.
 */
export type PackDraft = components["schemas"]["AdminPackDraft"];
export type PackDraftFile = components["schemas"]["AdminPackDraftFile"];
export type PackDraftCheck = components["schemas"]["AdminPackDraftCheck"];
export type PackDraftRequest = components["schemas"]["AdminPackDraftRequest"];
export type PackAlignment = components["schemas"]["AdminPackAlignment"];
export type DraftFileEntry = NonNullable<PackDraft["files"]>[number];
/** A media entry of a draft with its library asset (task 0018, step 16). */
export type DraftMediaEntry = NonNullable<PackDraft["media"]>[number];

export const draftsQueryKey = ["admin", "pack-drafts"] as const;

export const draftQueryKey = (id: string) => [...draftsQueryKey, id] as const;

export const draftFileQueryKey = (id: string, fileId: string) =>
  [...draftQueryKey(id), "files", fileId] as const;

/** `GET /api/admin/pack-drafts`: the drafts without files, newest change first. */
export function useDrafts() {
  const client = useApiClient();
  return useQuery({
    queryKey: draftsQueryKey,
    queryFn: async (): Promise<PackDraft[]> =>
      unwrap(await client.GET("/api/admin/pack-drafts")).data,
  });
}

/** The read of `GET /api/admin/pack-drafts/:id`. */
function draftQuery(client: ApiClient, id: string) {
  return queryOptions({
    queryKey: draftQueryKey(id),
    queryFn: async (): Promise<PackDraft> =>
      unwrap(
        await client.GET("/api/admin/pack-drafts/{id}", {
          params: { path: { id } },
        }),
      ),
  });
}

/**
 * `GET /api/admin/pack-drafts/:id`: the draft with its files, without
 * content. The page sends the cached `lock_version` with every change, so
 * the draft is not read again when the window regains the focus or the
 * network returns: such a read would take the `lock_version` of a change
 * in another tab or session without its content, and the next save would
 * replace that change without the 409 `stale_draft` (task 0016a, step
 * 13). The change hooks and the conflict dialog update the cache instead,
 * and `useFollowDraftMedia` writes only the assets of the media entries
 * into it.
 */
export function useDraft(id: string) {
  const client = useApiClient();
  return useQuery({
    ...draftQuery(client, id),
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
  });
}

/** The key of the reads of `useFollowDraftMedia`, below the key of the draft. */
const draftMediaQueryKey = (id: string) =>
  [...draftQueryKey(id), "media"] as const;

/**
 * `draft` with the assets that `read` holds for its media entries. The
 * entries themselves, the files, the `lock_version` and every other member
 * stay those of `draft`.
 */
function withAssetsOf(draft: PackDraft, read: PackDraft): PackDraft {
  if (draft.media === undefined) return draft;
  const assets = new Map(
    (read.media ?? []).map((entry) => [entry.asset.id, entry.asset]),
  );
  return {
    ...draft,
    media: draft.media.map((entry) => ({
      ...entry,
      asset: assets.get(entry.asset.id) ?? entry.asset,
    })),
  };
}

/**
 * Follows the conversions of the media entries of `draft` on the draft
 * page (task 0018): while an entry is `queued` or `processing`, it reads
 * `GET /api/admin/pack-drafts/:id` every two seconds, one request for all
 * entries, and writes the assets of the answer into the cache of
 * `useDraft`. The `lock_version`, the files and the entries of the cache
 * stay as they are, so the editor keeps its text and the next save sends
 * the version that the text belongs to: a newer `lock_version` without the
 * content of its change would let that save replace the change without the
 * 409 `stale_draft` (see `useDraft`). An answer to a read that started
 * before the cache last changed stays out, because that change can hold
 * newer assets; the next read follows two seconds later. An `ApiError`
 * below 500 ends the reads, as `mediaPollInterval` decides.
 */
export function useFollowDraftMedia(draft: PackDraft) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { id } = draft;
  const statuses = (draft.media ?? []).map((entry) => entry.asset.status);
  useQuery({
    queryKey: draftMediaQueryKey(id),
    enabled: statuses.some(mediaInProgress),
    // The draft of the page counts as the first read, so the page reads
    // the draft again two seconds after it loaded, and not twice at once.
    initialData: draft.media ?? [],
    initialDataUpdatedAt: () =>
      queryClient.getQueryState(draftQueryKey(id))?.dataUpdatedAt,
    staleTime: MEDIA_POLL_INTERVAL,
    queryFn: async (): Promise<DraftMediaEntry[]> => {
      const started = Date.now();
      const read = unwrap(
        await client.GET("/api/admin/pack-drafts/{id}", {
          params: { path: { id } },
        }),
      );
      const changed =
        queryClient.getQueryState(draftQueryKey(id))?.dataUpdatedAt ?? 0;
      if (changed <= started)
        queryClient.setQueryData<PackDraft>(draftQueryKey(id), (current) =>
          current === undefined ? current : withAssetsOf(current, read),
        );
      return read.media ?? [];
    },
    refetchInterval: (query) => mediaPollInterval(statuses, query.state.error),
  });
}

/**
 * Reads the draft `id` as `useDraft` reads it, for a check at the moment of
 * an action: the list of drafts reads the states of the media entries
 * before a download (task 0018). The answer is always read anew and goes
 * into the cache of `useDraft`.
 */
export function useReadDraft() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useCallback(
    (id: string): Promise<PackDraft> =>
      queryClient.fetchQuery({ ...draftQuery(client, id), staleTime: 0 }),
    [client, queryClient],
  );
}

/**
 * `GET /api/admin/pack-drafts/:id/files/:file_id`: the content of a file
 * and the `lock_version` of its draft. It loads only while `fileId` is set
 * and is never cached as fresh, so opening a file reads its stored content.
 *
 * The content leaves the cache as soon as the file is closed (`gcTime` 0).
 * A cached content is the one of the last read, which a save, a rename or
 * a change in another session makes old; TanStack Query keeps it as `data`
 * when the next read fails or waits for the network. Without it, a file
 * that opens again has no content until a read after the opening returns
 * one, so the editor never takes an older text, and the next save cannot
 * replace the stored file with it.
 */
export function useDraftFile(id: string, fileId: string | null) {
  const client = useApiClient();
  return useQuery({
    enabled: fileId !== null,
    staleTime: 0,
    gcTime: 0,
    queryKey: draftFileQueryKey(id, fileId ?? ""),
    queryFn: async (): Promise<PackDraftFile> =>
      unwrap(
        await client.GET("/api/admin/pack-drafts/{id}/files/{file_id}", {
          params: { path: { id, file_id: fileId ?? "" } },
        }),
      ),
  });
}

/** Writes a draft of a change into the cache of `useDraft` and marks the list stale. */
function useStoreDraft() {
  const queryClient = useQueryClient();
  return (draft: PackDraft) => {
    queryClient.setQueryData(draftQueryKey(draft.id), draft);
    void queryClient.invalidateQueries({
      queryKey: draftsQueryKey,
      exact: true,
    });
  };
}

/**
 * `POST /api/admin/pack-drafts`: a start from an empty pack, a published
 * program or an import with a payload.
 */
export function useCreateDraft() {
  const client = useApiClient();
  const storeDraft = useStoreDraft();
  return useMutation({
    mutationFn: async (body: PackDraftRequest): Promise<PackDraft> =>
      unwrap(await client.POST("/api/admin/pack-drafts", { body })),
    onSuccess: storeDraft,
  });
}

/**
 * `POST /api/admin/pack-draft-uploads`: sends the archive as
 * `multipart/form-data` with the field `file`, as `useUploadPack` does. The
 * answer carries `skipped`; a rejected archive throws an `ApiError` whose
 * body is the `AdminArchiveRejected` answer.
 */
export function useUploadDraft() {
  const client = useApiClient();
  const storeDraft = useStoreDraft();
  return useMutation({
    mutationFn: async (file: File): Promise<PackDraft> =>
      unwrap(
        await client.POST("/api/admin/pack-draft-uploads", {
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
    onSuccess: storeDraft,
  });
}

/** `DELETE /api/admin/pack-drafts/:id`. */
export function useDeleteDraft() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string): Promise<string> => {
      unwrap(
        await client.DELETE("/api/admin/pack-drafts/{id}", {
          params: { path: { id } },
        }),
      );
      return id;
    },
    onSuccess: (id) => {
      queryClient.removeQueries({ queryKey: draftQueryKey(id) });
      void queryClient.invalidateQueries({
        queryKey: draftsQueryKey,
        exact: true,
      });
    },
  });
}

/** `POST /api/admin/pack-drafts/:id/files`: a new file of the draft. */
export function useCreateFile(id: string) {
  const client = useApiClient();
  const storeDraft = useStoreDraft();
  return useMutation({
    mutationFn: async (body: {
      path: string;
      content: string;
      lock_version: number;
    }): Promise<PackDraft> =>
      unwrap(
        await client.POST("/api/admin/pack-drafts/{id}/files", {
          params: { path: { id } },
          body,
        }),
      ),
    onSuccess: storeDraft,
  });
}

/** `PUT /api/admin/pack-drafts/:id/files/:file_id`: saves the content of a file. */
export function useSaveFile(id: string) {
  const client = useApiClient();
  const storeDraft = useStoreDraft();
  return useMutation({
    mutationFn: async ({
      fileId,
      content,
      lock_version,
    }: {
      fileId: string;
      content: string;
      lock_version: number;
    }): Promise<PackDraft> =>
      unwrap(
        await client.PUT("/api/admin/pack-drafts/{id}/files/{file_id}", {
          params: { path: { id, file_id: fileId } },
          body: { content, lock_version },
        }),
      ),
    onSuccess: storeDraft,
  });
}

/** `PATCH /api/admin/pack-drafts/:id/files/:file_id`: moves a file to a new path. */
export function useRenameFile(id: string) {
  const client = useApiClient();
  const storeDraft = useStoreDraft();
  return useMutation({
    mutationFn: async ({
      fileId,
      path,
      lock_version,
    }: {
      fileId: string;
      path: string;
      lock_version: number;
    }): Promise<PackDraft> =>
      unwrap(
        await client.PATCH("/api/admin/pack-drafts/{id}/files/{file_id}", {
          params: { path: { id, file_id: fileId } },
          body: { path, lock_version },
        }),
      ),
    onSuccess: storeDraft,
  });
}

/** `DELETE /api/admin/pack-drafts/:id/files/:file_id?lock_version=<n>`. */
export function useDeleteFile(id: string) {
  const client = useApiClient();
  const storeDraft = useStoreDraft();
  return useMutation({
    mutationFn: async ({
      fileId,
      lock_version,
    }: {
      fileId: string;
      lock_version: number;
    }): Promise<PackDraft> =>
      unwrap(
        await client.DELETE("/api/admin/pack-drafts/{id}/files/{file_id}", {
          params: { path: { id, file_id: fileId }, query: { lock_version } },
        }),
      ),
    onSuccess: storeDraft,
  });
}

/**
 * After a change of the media entries of a draft: the uses of the assets
 * changed, so the lists of the library and the cached assets are stale.
 */
function useMediaChanged() {
  const queryClient = useQueryClient();
  return (assetIds: readonly string[]) => {
    void invalidateMediaLists(queryClient);
    for (const assetId of assetIds)
      void queryClient.invalidateQueries({
        queryKey: mediaAssetQueryKey(assetId),
      });
  };
}

/**
 * `POST /api/admin/pack-drafts/:id/media` (task 0018, step 16): a library
 * asset for the draft `draftId`. An image, SVG or video asset becomes a
 * media entry at `path` with the delivery extension of the asset; for a
 * `ready` captions asset the server copies its content into a text file
 * at a `.vtt` path, so the browser sends no file. The answer is the draft.
 */
export function useAttachMedia() {
  const client = useApiClient();
  const storeDraft = useStoreDraft();
  const mediaChanged = useMediaChanged();
  return useMutation({
    mutationFn: async ({
      draftId,
      ...body
    }: {
      draftId: string;
      media_asset_id: string;
      path: string;
      lock_version: number;
    }): Promise<PackDraft> =>
      unwrap(
        await client.POST("/api/admin/pack-drafts/{id}/media", {
          params: { path: { id: draftId } },
          body,
        }),
      ),
    onSuccess: (draft, { media_asset_id }) => {
      storeDraft(draft);
      mediaChanged([media_asset_id]);
    },
  });
}

/** `PATCH /api/admin/pack-drafts/:id/media/:media_id`: moves a media entry. */
export function useRenameMedia(id: string) {
  const client = useApiClient();
  const storeDraft = useStoreDraft();
  const mediaChanged = useMediaChanged();
  return useMutation({
    mutationFn: async ({
      entry,
      path,
      lock_version,
    }: {
      entry: DraftMediaEntry;
      path: string;
      lock_version: number;
    }): Promise<PackDraft> =>
      unwrap(
        await client.PATCH("/api/admin/pack-drafts/{id}/media/{media_id}", {
          params: { path: { id, media_id: entry.id } },
          body: { path, lock_version },
        }),
      ),
    onSuccess: (draft, { entry }) => {
      storeDraft(draft);
      mediaChanged([entry.asset.id]);
    },
  });
}

/**
 * `DELETE /api/admin/pack-drafts/:id/media/:media_id?lock_version=<n>`:
 * the entry leaves the draft, and the asset stays in the library.
 */
export function useDeleteDraftMedia(id: string) {
  const client = useApiClient();
  const storeDraft = useStoreDraft();
  const mediaChanged = useMediaChanged();
  return useMutation({
    mutationFn: async ({
      entry,
      lock_version,
    }: {
      entry: DraftMediaEntry;
      lock_version: number;
    }): Promise<PackDraft> =>
      unwrap(
        await client.DELETE("/api/admin/pack-drafts/{id}/media/{media_id}", {
          params: { path: { id, media_id: entry.id }, query: { lock_version } },
        }),
      ),
    onSuccess: (draft, { entry }) => {
      storeDraft(draft);
      mediaChanged([entry.asset.id]);
    },
  });
}

/**
 * `POST /api/admin/pack-drafts/:id/check`: runs the loader and the
 * validator on the draft without saving it, with the unsaved content of
 * one file as overlay. A 429 `checks_busy` throws an `ApiError` with
 * `retryAfter`.
 */
export function useCheckDraft(id: string) {
  const client = useApiClient();
  return useMutation({
    mutationFn: async (
      overlay: { file_id: string; content: string } | null,
    ): Promise<PackDraftCheck> =>
      unwrap(
        await client.POST("/api/admin/pack-drafts/{id}/check", {
          params: { path: { id } },
          body: overlay ?? {},
        }),
      ),
  });
}

/**
 * `POST /api/admin/pack-drafts/:id/imports`: turns the saved draft into an
 * import, which the pack page of task 0015 shows.
 */
export function useImportDraft(id: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (lock_version: number): Promise<PackImport> =>
      unwrap(
        await client.POST("/api/admin/pack-drafts/{id}/imports", {
          params: { path: { id } },
          body: { lock_version },
        }),
      ),
    onSuccess: (pack) => queryClient.setQueryData(packQueryKey(pack.id), pack),
  });
}

/** The URL of `GET /api/admin/pack-drafts/:id/download`. */
export const draftDownloadUrl = (id: string) =>
  `/api/admin/pack-drafts/${encodeURIComponent(id)}/download`;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/**
 * The stored `lock_version` of a 409 `stale_draft` answer, or `null` for any
 * other error.
 */
export function staleDraft(error: unknown): number | null {
  if (!(error instanceof ApiError) || error.status !== 409) return null;
  const body = error.body;
  if (!isRecord(body) || body.error !== "stale_draft") return null;
  return typeof body.lock_version === "number" ? body.lock_version : null;
}

/** The members of a 422 `validation_failed` answer with their codes, or `null`. */
export function fieldErrors(error: unknown): Record<string, string[]> | null {
  if (!(error instanceof ApiError) || error.status !== 422) return null;
  const body = error.body;
  if (!isRecord(body) || !isRecord(body.fields)) return null;
  return Object.fromEntries(
    Object.entries(body.fields).filter((entry): entry is [string, string[]] =>
      Array.isArray(entry[1]),
    ),
  );
}

import {
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
  type QueryClient,
} from "@tanstack/react-query";
import { useCallback } from "react";
import { useApiClient } from "../apiClientContext";
import {
  api,
  CSRF_HEADER,
  handleUnauthenticated,
  type ApiClient,
} from "../client";
import {
  ApiError,
  CSRF_ERROR_CODE,
  ENROLLMENT_ERROR_CODE,
  RECENT_AUTH_ERROR_CODE,
  errorCode,
  unwrap,
} from "../errors";
import { queryClient as appQueryClient } from "../queryClient";
import type { components } from "../schema";
import { sessionQueryKey, sessionQueryOptions, type Session } from "../session";
import { requestStepUp } from "../stepUp";

/**
 * The media library of the role `author` (task 0018, steps 15 and 19): the
 * list with its filters, an asset with its uses, the title, the deletion
 * and the upload. The pages under `src/admin/media/`, the media entries of
 * the workbench and the pack page read them through these functions.
 */
export type MediaAsset = components["schemas"]["AdminMediaAsset"];
export type MediaAssetList = components["schemas"]["AdminMediaAssetList"];
export type MediaUses = components["schemas"]["AdminMediaUses"];
export type MediaKind = MediaAsset["kind"];
export type MediaStatus = MediaAsset["status"];
export type MediaFailure = NonNullable<MediaAsset["failure"]>;
export type MediaFailureDetail = NonNullable<MediaAsset["failure_detail"]>;

/** The kinds of the library in the order of the filter. */
export const MEDIA_KINDS = [
  "image",
  "svg",
  "video",
  "captions",
] as const satisfies readonly MediaKind[];

/** The states of an asset in the order of the filter. */
export const MEDIA_STATUSES = [
  "queued",
  "processing",
  "ready",
  "failed",
] as const satisfies readonly MediaStatus[];

/** The filters of `GET /api/admin/media`; `null` and `""` leave one out. */
export interface MediaFilters {
  kind: MediaKind | null;
  status: MediaStatus | null;
  /** Only assets that no program, draft or validated import uses. */
  unused: boolean;
  /** A part of the title. */
  q: string;
}

export const NO_MEDIA_FILTERS: MediaFilters = {
  kind: null,
  status: null,
  unused: false,
  q: "",
};

/** The milliseconds between two reads while an asset is converted. */
export const MEDIA_POLL_INTERVAL = 2000;

/** True while the worker has not finished an asset. */
export const mediaInProgress = (status: string): boolean =>
  status === "queued" || status === "processing";

/**
 * The interval of the next read of media states, as `exportPollInterval`
 * of 0016 decides it: every two seconds while one of `statuses` is
 * `queued` or `processing`, no further read otherwise. An `ApiError` below
 * 500 ends the reads, because a repeat gets the same answer; a network
 * error or a 5xx answer keeps them going.
 */
export function mediaPollInterval(
  statuses: readonly string[] | undefined,
  error: unknown,
): number | false {
  if (error instanceof ApiError && error.status < 500) return false;
  return statuses !== undefined && statuses.some(mediaInProgress)
    ? MEDIA_POLL_INTERVAL
    : false;
}

export const mediaQueryKey = ["admin", "media"] as const;

const mediaListsKey = [...mediaQueryKey, "list"] as const;

export const mediaListQueryKey = (filters: MediaFilters, limit: number) =>
  [...mediaListsKey, filters, limit] as const;

export const mediaAssetQueryKey = (id: string) =>
  [...mediaQueryKey, "asset", id] as const;

/** Marks every list of the library stale, after an upload or a change. */
export function invalidateMediaLists(queryClient: QueryClient) {
  return queryClient.invalidateQueries({ queryKey: mediaListsKey });
}

/** The largest page of `GET /api/admin/media`. */
export const MEDIA_MAX_PAGE = 100;

/**
 * `GET /api/admin/media` with `filters`, newest first, page by page through
 * the cursor `next`, `limit` assets per page. Every loaded page is read
 * again every two seconds while one of its assets is `queued` or
 * `processing`. It loads only while `enabled`.
 */
export function useMediaLibrary(
  filters: MediaFilters,
  { limit = 50, enabled = true }: { limit?: number; enabled?: boolean } = {},
) {
  const client = useApiClient();
  return useInfiniteQuery({
    enabled,
    queryKey: mediaListQueryKey(filters, limit),
    initialPageParam: null as string | null,
    queryFn: async ({ pageParam }): Promise<MediaAssetList> => {
      const q = filters.q.trim();
      return unwrap(
        await client.GET("/api/admin/media", {
          params: {
            query: {
              ...(filters.kind === null ? {} : { kind: filters.kind }),
              ...(filters.status === null ? {} : { status: filters.status }),
              ...(filters.unused ? { unused: true } : {}),
              ...(q === "" ? {} : { q }),
              limit,
              ...(pageParam === null ? {} : { after: pageParam }),
            },
          },
        }),
      );
    },
    getNextPageParam: (page) => page.next,
    refetchInterval: (query) =>
      mediaPollInterval(
        query.state.data?.pages.flatMap((page) =>
          page.items.map((asset) => asset.status),
        ),
        query.state.error,
      ),
  });
}

/**
 * `GET /api/admin/media/:id`: an asset with its uses. It loads only while
 * `id` is set, and again every two seconds while the asset is `queued` or
 * `processing`.
 */
export function useMediaAsset(id: string | null) {
  const client = useApiClient();
  return useQuery({
    enabled: id !== null,
    queryKey: mediaAssetQueryKey(id ?? ""),
    queryFn: async (): Promise<MediaAsset> =>
      unwrap(
        await client.GET("/api/admin/media/{id}", {
          params: { path: { id: id ?? "" } },
        }),
      ),
    refetchInterval: (query) =>
      mediaPollInterval(
        query.state.data === undefined ? undefined : [query.state.data.status],
        query.state.error,
      ),
  });
}

/** `PATCH /api/admin/media/:id` with a new title. */
export function useUpdateMediaTitle() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id,
      title,
    }: {
      id: string;
      title: string;
    }): Promise<MediaAsset> =>
      unwrap(
        await client.PATCH("/api/admin/media/{id}", {
          params: { path: { id } },
          body: { title },
        }),
      ),
    onSuccess: (asset) => {
      // The answer holds no uses; the cached detail keeps its own.
      queryClient.setQueryData<MediaAsset>(
        mediaAssetQueryKey(asset.id),
        (current) => (current === undefined ? asset : { ...current, ...asset }),
      );
      void invalidateMediaLists(queryClient);
    },
  });
}

/**
 * `DELETE /api/admin/media/:id`. A 409 `asset_in_use` throws an `ApiError`
 * whose body names the uses (`assetInUse`).
 */
export function useDeleteMedia() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string): Promise<string> => {
      unwrap(
        await client.DELETE("/api/admin/media/{id}", {
          params: { path: { id } },
        }),
      );
      return id;
    },
    onSuccess: (id) => {
      queryClient.removeQueries({ queryKey: mediaAssetQueryKey(id) });
      void invalidateMediaLists(queryClient);
    },
  });
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const records = (value: unknown): Record<string, unknown>[] =>
  Array.isArray(value) ? value.filter(isRecord) : [];

/**
 * The uses of a 409 `asset_in_use` answer, or `null` for any other error.
 * Each list keeps the entries that are objects; the page renders their
 * members as text.
 */
export function assetInUse(error: unknown): MediaUses | null {
  if (!(error instanceof ApiError) || error.status !== 409) return null;
  const body = error.body;
  if (!isRecord(body) || body.error !== "asset_in_use") return null;
  const uses = isRecord(body.uses) ? body.uses : {};
  return {
    programs: records(uses.programs) as MediaUses["programs"],
    drafts: records(uses.drafts) as MediaUses["drafts"],
    imports: records(uses.imports) as MediaUses["imports"],
  };
}

/** The asset of a finished upload, and whether the library made it now. */
export interface UploadedMedia {
  asset: MediaAsset;
  /** `true` for 201 (a new asset), `false` for 200 (the same file existed). */
  created: boolean;
}

/** The bytes sent so far and the size of the body. */
export type UploadProgress = (loaded: number, total: number) => void;

/** The query cache of the session and the client that refetches it. */
export interface UploadContext {
  queryClient: QueryClient;
  client: ApiClient;
}

const MEDIA_UPLOAD_PATH = "/api/admin/media";

/** An answer of `XMLHttpRequest` as a `Response`, with its status and headers. */
function toResponse(request: XMLHttpRequest): Response {
  const headers = new Headers();
  for (const line of request.getAllResponseHeaders().split(/\r?\n/)) {
    const colon = line.indexOf(":");
    if (colon <= 0) continue;
    try {
      headers.append(line.slice(0, colon).trim(), line.slice(colon + 1).trim());
    } catch {
      // A header that a Response cannot hold is left out.
    }
  }
  const empty = request.status === 204 || request.responseText === "";
  return new Response(empty ? null : request.responseText, {
    status: request.status,
    headers,
  });
}

/**
 * Sends `file` as the part `file` of a `multipart/form-data` body with
 * `XMLHttpRequest`, whose upload events report the progress, which `fetch`
 * does not. The browser sets the content type with its boundary; the
 * request sends the cookies of the origin, as every same-origin request
 * does.
 */
function send(
  file: File,
  csrfToken: string | undefined,
  onProgress: UploadProgress,
): Promise<Response> {
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest();
    request.open("POST", MEDIA_UPLOAD_PATH);
    request.setRequestHeader("accept", "application/json");
    if (csrfToken) request.setRequestHeader(CSRF_HEADER, csrfToken);
    request.upload.addEventListener("progress", (event) =>
      onProgress(
        event.loaded,
        event.lengthComputable ? event.total : file.size,
      ),
    );
    request.addEventListener("load", () => {
      if (request.status < 200 || request.status > 599)
        reject(new TypeError(`The upload answered ${request.status}.`));
      else resolve(toResponse(request));
    });
    request.addEventListener("error", () =>
      reject(new TypeError("The upload failed.")),
    );
    request.addEventListener("abort", () =>
      reject(new DOMException("The upload was aborted.", "AbortError")),
    );
    const body = new FormData();
    body.append("file", file, file.name);
    request.send(body);
  });
}

/** True while the window of the last second factor is open. */
function recentAuth(session: Session | undefined): boolean {
  const until = session?.recentAuthUntil ?? null;
  if (until === null) return false;
  const end = Date.parse(until);
  return Number.isFinite(end) && end > Date.now();
}

/**
 * The answer of a step-up that the person closed before a body was sent:
 * a 403 `reauth_required`, as the route would answer, so the page shows
 * the message of a cancelled confirmation.
 */
const stepUpCancelled = () =>
  new ApiError(new Response(null, { status: 403 }), {
    error: RECENT_AUTH_ERROR_CODE,
  });

async function readBody(response: Response): Promise<unknown> {
  try {
    return await response.clone().json();
  } catch {
    return null;
  }
}

/**
 * `POST /api/admin/media`: uploads one file to the media library with the
 * `x-csrf-token` of the cached session and reports the progress of the
 * body through `onProgress`. It follows the rules of the middleware of the
 * API client (`createApiClient`):
 *
 * - Before it sends a body, it opens the step-up dialog when the window of
 *   the last second factor (`recentAuthUntil`) is closed, so a large file
 *   is rarely sent twice; a closed dialog sends nothing and throws the
 *   `ApiError` of a 403 `reauth_required`.
 * - A 403 `reauth_required` asks for a step-up and, after a successful
 *   one, repeats the upload once with the CSRF token of the refetched
 *   session.
 * - A 403 `csrf` refetches the session and repeats the upload once with
 *   the new token.
 * - A 403 `enrollment_required` invalidates the session query.
 * - A 401, also as the answer to a repeat, goes to
 *   `handleUnauthenticated`.
 *
 * Only one repeat follows an answer; the answer of the repeat reaches the
 * caller. It resolves with the asset of a 201 or a 200 and throws an
 * `ApiError` for every other answer, and a `TypeError` when the network
 * fails.
 */
export async function uploadMedia(
  file: File,
  onProgress: UploadProgress,
  { queryClient, client }: UploadContext = {
    queryClient: appQueryClient,
    client: api,
  },
): Promise<UploadedMedia> {
  const cachedSession = () =>
    queryClient.getQueryData<Session>(sessionQueryKey);

  if (!recentAuth(cachedSession()) && !(await requestStepUp()))
    throw stepUpCancelled();

  const repeat = async (csrfToken: string | undefined) => {
    onProgress(0, file.size);
    const repeated = await send(file, csrfToken, onProgress);
    if (repeated.status === 401)
      await handleUnauthenticated(queryClient, repeated);
    return repeated;
  };

  let response = await send(file, cachedSession()?.csrfToken, onProgress);
  if (response.status === 401) {
    await handleUnauthenticated(queryClient, response);
  } else if (response.status === 403) {
    const code = await errorCode(response);
    if (code === ENROLLMENT_ERROR_CODE) {
      await queryClient.invalidateQueries({ queryKey: sessionQueryKey });
    } else if (code === RECENT_AUTH_ERROR_CODE) {
      if (await requestStepUp())
        response = await repeat(cachedSession()?.csrfToken);
    } else if (code === CSRF_ERROR_CODE) {
      let session: Session | null = null;
      try {
        session = await queryClient.fetchQuery({
          ...sessionQueryOptions(client),
          staleTime: 0,
        });
      } catch {
        session = null;
      }
      if (session !== null) response = await repeat(session.csrfToken);
    }
  }

  const body = await readBody(response);
  if (!response.ok) throw new ApiError(response, body);
  return { asset: body as MediaAsset, created: response.status === 201 };
}

/**
 * `uploadMedia` with the query cache and the API client of the component
 * tree. A finished upload marks the lists of the library stale.
 */
export function useUploadMedia() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useCallback(
    async (file: File, onProgress: UploadProgress): Promise<UploadedMedia> => {
      const uploaded = await uploadMedia(file, onProgress, {
        queryClient,
        client,
      });
      queryClient.setQueryData<MediaAsset>(
        mediaAssetQueryKey(uploaded.asset.id),
        (current) =>
          current === undefined ? current : { ...current, ...uploaded.asset },
      );
      void invalidateMediaLists(queryClient);
      return uploaded;
    },
    [client, queryClient],
  );
}

/** The extensions that the upload accepts (`Espalier.Media.Sniff`, step 5). */
export const UPLOAD_EXTENSIONS: Record<MediaKind, readonly string[]> = {
  image: [".png", ".jpg", ".jpeg", ".gif", ".webp"],
  svg: [".svg"],
  video: [".mp4", ".m4v", ".mov", ".webm", ".mkv"],
  captions: [".vtt"],
};

/** The `accept` attribute of a file input for `kinds`. */
export const acceptFor = (kinds: readonly MediaKind[]): string =>
  kinds.flatMap((kind) => UPLOAD_EXTENSIONS[kind]).join(",");

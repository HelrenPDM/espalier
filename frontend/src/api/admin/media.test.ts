import { QueryClient } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { installFakeXhr, type XhrAnswer } from "../../test/fakeXhr";
import { sessionPayload } from "../../test/session";
import { createApiClient } from "../client";
import { ApiError } from "../errors";
import { sessionQueryKey, toSession, type Session } from "../session";
import { setStepUpHandler } from "../stepUp";
import { uploadMedia, type MediaAsset, type UploadContext } from "./media";

/**
 * Task 0018, step 19: `uploadMedia` sends the file with `XMLHttpRequest`
 * and follows the rules of the client middleware of `client.ts` for each
 * answer, with a fake XHR in place of the browser: the CSRF header of the
 * cached session, the step-up before the body while the window of the last
 * second factor is closed, one repeat after a step-up or a CSRF refetch,
 * the invalidated session after `enrollment_required`, and
 * `handleUnauthenticated` after a 401.
 */
const ASSET: MediaAsset = {
  id: "00000000-0000-4000-8000-000000000a01",
  kind: "image",
  status: "queued",
  failure: null,
  failure_detail: null,
  progress: 0,
  title: "team-photo",
  source_name: "team-photo.png",
  origin: "upload",
  ext: null,
  bytes: null,
  width: null,
  height: null,
  duration_ms: null,
  has_audio: false,
  animated: false,
  has_alpha: false,
  url: null,
  poster_url: null,
  inserted_at: "2026-10-15T09:00:00Z",
  updated_at: "2026-10-15T09:00:00Z",
};

const FUTURE = "2999-01-01T00:00:00Z";
const PAST = "2020-01-01T00:00:00Z";

/** The cached session: an author with `recentAuthUntil` and CSRF token 1. */
const sessionWith = (recentAuthUntil: string | null): Session =>
  toSession(
    sessionPayload({
      user: {
        id: "5b1f7c2e-3d4a-4e6b-8c9d-0e1f2a3b4c5d",
        display_name: "Ada Example",
        email: "ada@example.test",
        locale: "en",
      },
      roles: ["learner", "author"],
      csrf_token: "token-1",
      session: { recent_auth_until: recentAuthUntil },
    }),
  );

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

let queryClient: QueryClient;
let fetches: string[];
let context: UploadContext;

/** A file of `size` bytes. */
const fileOf = (name = "team-photo.png", size = 1_000) =>
  new File([new Uint8Array(size)], name, { type: "image/png" });

beforeEach(() => {
  queryClient = new QueryClient();
  queryClient.setQueryData(sessionQueryKey, sessionWith(FUTURE));
  fetches = [];
  // The fetch of the API client answers the session refetch of a 403
  // `csrf` with the CSRF token 2.
  const fetchImpl = vi.fn(async (request: Request) => {
    fetches.push(`${request.method} ${new URL(request.url).pathname}`);
    return json(
      200,
      sessionPayload({ csrf_token: "token-2", roles: ["learner", "author"] }),
    );
  });
  context = { queryClient, client: createApiClient(queryClient, fetchImpl) };
});

afterEach(() => {
  vi.unstubAllGlobals();
  setStepUpHandler(null);
});

/** A step-up handler that answers `success` and, on success, renews the CSRF token. */
function stepUp(success: boolean) {
  const handler = vi.fn(async () => {
    if (success)
      queryClient.setQueryData<Session>(sessionQueryKey, {
        ...sessionWith(FUTURE),
        csrfToken: "token-3",
      });
    return success;
  });
  setStepUpHandler(handler);
  return handler;
}

const created: XhrAnswer = { status: 201, body: ASSET };

describe("a successful upload", () => {
  test("sends the file as the part file with the CSRF token and reports the progress", async () => {
    const { requests } = installFakeXhr([created]);
    const progress = vi.fn();
    const file = fileOf();

    const result = await uploadMedia(file, progress, context);

    expect(result).toEqual({ asset: ASSET, created: true });
    expect(requests).toHaveLength(1);
    const [request] = requests;
    expect(request.method).toBe("POST");
    expect(request.url).toBe("/api/admin/media");
    expect(request.headers["x-csrf-token"]).toBe("token-1");
    const part = request.body?.get("file");
    expect(part).toBeInstanceOf(File);
    expect(part).toMatchObject({ name: "team-photo.png", size: file.size });
    expect([...(request.body?.keys() ?? [])]).toEqual(["file"]);
    expect(progress).toHaveBeenLastCalledWith(1_000, 1_000);
    expect(progress).toHaveBeenCalledWith(500, 1_000);
    expect(fetches).toEqual([]);
  });

  test("a 200 answer is the existing asset of the same file", async () => {
    installFakeXhr([{ status: 200, body: { ...ASSET, status: "ready" } }]);

    const result = await uploadMedia(fileOf(), () => {}, context);

    expect(result.created).toBe(false);
    expect(result.asset.status).toBe("ready");
  });
});

describe("the window of the last second factor", () => {
  test.each([
    ["null", null],
    ["in the past", PAST],
  ])(
    "opens the step-up dialog before the body when recentAuthUntil is %s",
    async (_name, until) => {
      queryClient.setQueryData(sessionQueryKey, sessionWith(until));
      const handler = stepUp(true);
      const { requests } = installFakeXhr([created]);

      await uploadMedia(fileOf(), () => {}, context);

      expect(handler).toHaveBeenCalledTimes(1);
      expect(requests).toHaveLength(1);
      expect(requests[0].headers["x-csrf-token"]).toBe("token-3");
    },
  );

  test("sends nothing and throws reauth_required when the dialog is closed", async () => {
    queryClient.setQueryData(sessionQueryKey, sessionWith(null));
    const handler = stepUp(false);
    const { requests } = installFakeXhr([created]);

    const failure = await uploadMedia(fileOf(), () => {}, context).catch(
      (error: unknown) => error,
    );

    expect(handler).toHaveBeenCalledTimes(1);
    expect(requests).toHaveLength(0);
    expect(failure).toBeInstanceOf(ApiError);
    expect(failure).toMatchObject({ status: 403, code: "reauth_required" });
  });

  test("opens no dialog while the window is open", async () => {
    const handler = stepUp(true);
    installFakeXhr([created]);

    await uploadMedia(fileOf(), () => {}, context);

    expect(handler).not.toHaveBeenCalled();
  });
});

describe("a 403 answer", () => {
  test("with reauth_required steps up and repeats once with the new token", async () => {
    const handler = stepUp(true);
    const { requests } = installFakeXhr([
      { status: 403, body: { error: "reauth_required" } },
      created,
    ]);

    const result = await uploadMedia(fileOf(), () => {}, context);

    expect(result.created).toBe(true);
    expect(handler).toHaveBeenCalledTimes(1);
    expect(requests.map((request) => request.headers["x-csrf-token"])).toEqual([
      "token-1",
      "token-3",
    ]);
  });

  test("with reauth_required after a closed dialog reaches the caller without a repeat", async () => {
    stepUp(false);
    const { requests } = installFakeXhr([
      { status: 403, body: { error: "reauth_required" } },
    ]);

    await expect(
      uploadMedia(fileOf(), () => {}, context),
    ).rejects.toMatchObject({ status: 403, code: "reauth_required" });
    expect(requests).toHaveLength(1);
  });

  test("with reauth_required on the repeat reaches the caller after one step-up", async () => {
    const handler = stepUp(true);
    const { requests } = installFakeXhr([
      { status: 403, body: { error: "reauth_required" } },
    ]);

    await expect(
      uploadMedia(fileOf(), () => {}, context),
    ).rejects.toMatchObject({ status: 403, code: "reauth_required" });
    expect(handler).toHaveBeenCalledTimes(1);
    expect(requests).toHaveLength(2);
  });

  test("with csrf refetches the session and repeats once with its token", async () => {
    const { requests } = installFakeXhr([
      { status: 403, body: { error: "csrf" } },
      created,
    ]);

    const result = await uploadMedia(fileOf(), () => {}, context);

    expect(result.created).toBe(true);
    expect(fetches).toEqual(["GET /api/session"]);
    expect(requests.map((request) => request.headers["x-csrf-token"])).toEqual([
      "token-1",
      "token-2",
    ]);
    expect(queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken).toBe(
      "token-2",
    );
  });

  test("with csrf on the repeat reaches the caller", async () => {
    const { requests } = installFakeXhr([
      { status: 403, body: { error: "csrf" } },
    ]);

    await expect(
      uploadMedia(fileOf(), () => {}, context),
    ).rejects.toMatchObject({ status: 403, code: "csrf" });
    expect(requests).toHaveLength(2);
    expect(fetches).toEqual(["GET /api/session"]);
  });

  test("with enrollment_required invalidates the session query and repeats nothing", async () => {
    const handler = stepUp(true);
    const { requests } = installFakeXhr([
      { status: 403, body: { error: "enrollment_required" } },
    ]);

    await expect(
      uploadMedia(fileOf(), () => {}, context),
    ).rejects.toMatchObject({ status: 403, code: "enrollment_required" });
    expect(requests).toHaveLength(1);
    expect(handler).not.toHaveBeenCalled();
    expect(queryClient.getQueryState(sessionQueryKey)?.isInvalidated).toBe(
      true,
    );
  });

  test("with cross_site_request reaches the caller without a refetch or a repeat", async () => {
    const { requests } = installFakeXhr([
      { status: 403, body: { error: "cross_site_request" } },
    ]);

    await expect(
      uploadMedia(fileOf(), () => {}, context),
    ).rejects.toMatchObject({ status: 403, code: "cross_site_request" });
    expect(requests).toHaveLength(1);
    expect(fetches).toEqual([]);
  });
});

describe("a 401 answer", () => {
  test("unauthenticated removes every other cached query and invalidates the session", async () => {
    queryClient.setQueryData(["admin", "media", "list"], { pages: [] });
    installFakeXhr([{ status: 401, body: { error: "unauthenticated" } }]);

    await expect(
      uploadMedia(fileOf(), () => {}, context),
    ).rejects.toMatchObject({ status: 401 });
    expect(
      queryClient
        .getQueryCache()
        .getAll()
        .map((query) => query.queryKey),
    ).toEqual([sessionQueryKey]);
    expect(queryClient.getQueryState(sessionQueryKey)?.isInvalidated).toBe(
      true,
    );
  });

  test("to the repeat after a CSRF refetch is handled as well", async () => {
    queryClient.setQueryData(["admin", "media", "list"], { pages: [] });
    const { requests } = installFakeXhr([
      { status: 403, body: { error: "csrf" } },
      { status: 401, body: { error: "unauthenticated" } },
    ]);

    await expect(
      uploadMedia(fileOf(), () => {}, context),
    ).rejects.toMatchObject({ status: 401 });
    expect(requests).toHaveLength(2);
    expect(
      queryClient.getQueryData(["admin", "media", "list"]),
    ).toBeUndefined();
    expect(queryClient.getQueryState(sessionQueryKey)?.isInvalidated).toBe(
      true,
    );
  });
});

describe("the other answers", () => {
  test.each([
    [
      422,
      {
        error: "validation_failed",
        fields: { file: ["extension_mismatch"] },
      },
    ],
    [409, { error: "storage_full" }],
    [413, { error: "request_too_large" }],
    [415, { error: "unsupported_media_type" }],
  ])("%i throws an ApiError with the body", async (status, body) => {
    const { requests } = installFakeXhr([{ status, body }]);

    const failure = await uploadMedia(fileOf(), () => {}, context).catch(
      (error: unknown) => error,
    );

    expect(failure).toBeInstanceOf(ApiError);
    expect(failure).toMatchObject({ status, body });
    expect(requests).toHaveLength(1);
  });

  test("a network failure throws a TypeError", async () => {
    installFakeXhr([{ status: 0, network: true }]);

    await expect(
      uploadMedia(fileOf(), () => {}, context),
    ).rejects.toBeInstanceOf(TypeError);
  });
});

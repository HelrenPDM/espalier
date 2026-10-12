import { QueryClient } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { createApiClient } from "./client";
import {
  CSRF_ERROR_CODE,
  ENROLLMENT_ERROR_CODE,
  RECENT_AUTH_ERROR_CODE,
} from "./errors";
import { sessionQueryKey, type Session } from "./session";
import { setStepUpHandler } from "./stepUp";

const session: Session = {
  user: {
    id: "8a4c7a5e-2f5b-4d6e-9c1a-3b2d4e5f6a7b",
    displayName: "Test person 1",
    email: null,
  },
  roles: ["learner"],
  sessionStrength: "demo",
  authMethods: ["demo"],
  providerKey: null,
  pending: null,
  csrfToken: "token-1",
  providers: [],
  flags: {
    demo: true,
    localAccounts: true,
    signup: "closed",
    adminPasskeyRequired: false,
    testNotes: false,
    feedbackFreeText: false,
  },
};

const sessionPayload = (csrfToken: string) => ({
  user: null,
  roles: [],
  session: null,
  pending: null,
  csrf_token: csrfToken,
  providers: [],
  flags: {
    demo: false,
    local_accounts: true,
    signup: "closed",
    admin_passkey_required: false,
    test_notes: false,
    feedback_free_text: false,
  },
});

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

type Route = (request: Request) => Response;

/** A fetch stub that records every request and answers through `route`. */
function stubFetch(route: Route) {
  const requests: Request[] = [];
  const fetchImpl = vi.fn(async (request: Request) => {
    requests.push(request);
    return route(request);
  });
  return { fetchImpl, requests };
}

const path = (request: Request) => new URL(request.url).pathname;

let queryClient: QueryClient;

beforeEach(() => {
  queryClient = new QueryClient();
  queryClient.setQueryData(sessionQueryKey, session);
});

describe("the CSRF header", () => {
  test("POST, PUT, PATCH and DELETE requests carry the token of the cached session", async () => {
    const { fetchImpl, requests } = stubFetch(() => json(200, {}));
    const client = createApiClient(queryClient, fetchImpl);

    await client.POST("/api/auth/demo", { body: { slot: 1 } });
    await client.PUT("/api/me/password", {
      body: { current_password: "old", password: "new" },
    });
    await client.PATCH("/api/enrollments/{id}", {
      params: { path: { id: "5f0d1c2b-3a4e-4b6c-8d7e-9f0a1b2c3d4e" } },
      body: { path: "short" },
    });
    await client.DELETE("/api/session");

    expect(
      requests.map((request) => [
        request.method,
        request.headers.get("x-csrf-token"),
      ]),
    ).toEqual([
      ["POST", "token-1"],
      ["PUT", "token-1"],
      ["PATCH", "token-1"],
      ["DELETE", "token-1"],
    ]);
  });

  test("a GET request goes out without the header", async () => {
    const { fetchImpl, requests } = stubFetch(() =>
      json(200, { programs: [] }),
    );
    const client = createApiClient(queryClient, fetchImpl);

    await client.GET("/api/programs");

    expect(requests).toHaveLength(1);
    expect(requests[0].headers.has("x-csrf-token")).toBe(false);
  });
});

describe("a 403 answer", () => {
  test(`with ${CSRF_ERROR_CODE} refetches the session once and repeats the request once with the new token`, async () => {
    let posts = 0;
    const { fetchImpl, requests } = stubFetch((request) => {
      if (path(request) === "/api/session")
        return json(200, sessionPayload("token-2"));
      posts += 1;
      return posts === 1
        ? json(403, { error: CSRF_ERROR_CODE })
        : json(200, sessionPayload("token-3"));
    });
    const client = createApiClient(queryClient, fetchImpl);

    const { response } = await client.POST("/api/auth/demo", {
      body: { slot: 2 },
    });

    expect(response.status).toBe(200);
    expect(requests.map((request) => [request.method, path(request)])).toEqual([
      ["POST", "/api/auth/demo"],
      ["GET", "/api/session"],
      ["POST", "/api/auth/demo"],
    ]);
    expect(requests[0].headers.get("x-csrf-token")).toBe("token-1");
    expect(requests[2].headers.get("x-csrf-token")).toBe("token-2");
    expect(await requests[2].json()).toEqual({ slot: 2 });
    expect(queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken).toBe(
      "token-2",
    );
    expect(queryClient.getQueryState(sessionQueryKey)?.isInvalidated).toBe(
      false,
    );
  });

  test(`with ${CSRF_ERROR_CODE} after the repeat reaches the caller`, async () => {
    const { fetchImpl, requests } = stubFetch((request) =>
      path(request) === "/api/session"
        ? json(200, sessionPayload("token-2"))
        : json(403, { error: CSRF_ERROR_CODE }),
    );
    const client = createApiClient(queryClient, fetchImpl);

    const { response, error } = await client.POST("/api/auth/demo", {
      body: { slot: 2 },
    });

    expect(response.status).toBe(403);
    expect(error).toEqual({ error: CSRF_ERROR_CODE });
    expect(requests.map(path)).toEqual([
      "/api/auth/demo",
      "/api/session",
      "/api/auth/demo",
    ]);
  });

  test("with cross_site_request triggers neither a refetch nor a repeat", async () => {
    const { fetchImpl, requests } = stubFetch(() =>
      json(403, { error: "cross_site_request" }),
    );
    const client = createApiClient(queryClient, fetchImpl);

    const { response, error } = await client.POST("/api/auth/demo", {
      body: { slot: 2 },
    });

    expect(response.status).toBe(403);
    expect(error).toEqual({ error: "cross_site_request" });
    expect(requests.map(path)).toEqual(["/api/auth/demo"]);
  });
});

test("a 401 answer invalidates the session query", async () => {
  const { fetchImpl } = stubFetch((request) =>
    path(request) === "/api/session"
      ? json(200, sessionPayload("token-2"))
      : json(401, { error: "unauthenticated" }),
  );
  const client = createApiClient(queryClient, fetchImpl);
  expect(queryClient.getQueryState(sessionQueryKey)?.isInvalidated).toBe(false);

  const { response } = await client.GET("/api/programs");

  expect(response.status).toBe(401);
  expect(queryClient.getQueryState(sessionQueryKey)?.isInvalidated).toBe(true);
});

test("a 401 answer to the repeat invalidates the refetched session", async () => {
  let posts = 0;
  const { fetchImpl, requests } = stubFetch((request) => {
    if (path(request) === "/api/session")
      return json(200, sessionPayload("token-2"));
    posts += 1;
    return posts === 1
      ? json(403, { error: CSRF_ERROR_CODE })
      : json(401, { error: "unauthenticated" });
  });
  const client = createApiClient(queryClient, fetchImpl);

  const { response } = await client.POST("/api/auth/demo", {
    body: { slot: 2 },
  });

  expect(response.status).toBe(401);
  expect(requests.map(path)).toEqual([
    "/api/auth/demo",
    "/api/session",
    "/api/auth/demo",
  ]);
  expect(queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken).toBe(
    "token-2",
  );
  expect(queryClient.getQueryState(sessionQueryKey)?.isInvalidated).toBe(true);
});

describe(`a 403 answer with ${RECENT_AUTH_ERROR_CODE}`, () => {
  const INTENTS = "/api/auth/oidc/entra/intents";

  afterEach(() => {
    setStepUpHandler(null);
  });

  const linkIntent = (fetchImpl: (request: Request) => Promise<Response>) =>
    createApiClient(queryClient, fetchImpl).POST(
      "/api/auth/oidc/{provider}/intents",
      { params: { path: { provider: "entra" } }, body: { purpose: "link" } },
    );

  /**
   * A step-up handler that answers `success`. A successful step-up has
   * refetched the session, so it puts `csrfToken` into the cache.
   */
  const stepUp = (success: boolean, csrfToken = "token-2") =>
    vi.fn(async () => {
      if (success)
        queryClient.setQueryData<Session>(sessionQueryKey, {
          ...session,
          csrfToken,
        });
      return success;
    });

  test("calls the step-up handler and on true repeats the request once with the cached CSRF token", async () => {
    let posts = 0;
    const { fetchImpl, requests } = stubFetch(() => {
      posts += 1;
      return posts === 1
        ? json(403, { error: RECENT_AUTH_ERROR_CODE })
        : json(201, { url: "/auth/oidc/entra?intent=intent-1" });
    });
    const handler = stepUp(true);
    setStepUpHandler(handler);

    const { response, data } = await linkIntent(fetchImpl);

    expect(handler).toHaveBeenCalledTimes(1);
    expect(response.status).toBe(201);
    expect(data).toEqual({ url: "/auth/oidc/entra?intent=intent-1" });
    expect(requests.map((request) => [request.method, path(request)])).toEqual([
      ["POST", INTENTS],
      ["POST", INTENTS],
    ]);
    expect(requests[0].headers.get("x-csrf-token")).toBe("token-1");
    expect(requests[1].headers.get("x-csrf-token")).toBe("token-2");
    expect(await requests[1].json()).toEqual({ purpose: "link" });
  });

  test("on false reaches the caller and nothing repeats", async () => {
    const { fetchImpl, requests } = stubFetch(() =>
      json(403, { error: RECENT_AUTH_ERROR_CODE }),
    );
    const handler = stepUp(false);
    setStepUpHandler(handler);

    const { response, error } = await linkIntent(fetchImpl);

    expect(handler).toHaveBeenCalledTimes(1);
    expect(response.status).toBe(403);
    expect(error).toEqual({ error: RECENT_AUTH_ERROR_CODE });
    expect(requests.map(path)).toEqual([INTENTS]);
  });

  test("without a registered handler reaches the caller and nothing repeats", async () => {
    const { fetchImpl, requests } = stubFetch(() =>
      json(403, { error: RECENT_AUTH_ERROR_CODE }),
    );

    const { response } = await linkIntent(fetchImpl);

    expect(response.status).toBe(403);
    expect(requests.map(path)).toEqual([INTENTS]);
  });

  test("on the repeat reaches the caller without a second handler call", async () => {
    const { fetchImpl, requests } = stubFetch(() =>
      json(403, { error: RECENT_AUTH_ERROR_CODE }),
    );
    const handler = stepUp(true);
    setStepUpHandler(handler);

    const { response, error } = await linkIntent(fetchImpl);

    expect(handler).toHaveBeenCalledTimes(1);
    expect(response.status).toBe(403);
    expect(error).toEqual({ error: RECENT_AUTH_ERROR_CODE });
    expect(requests.map(path)).toEqual([INTENTS, INTENTS]);
  });

  test("two parallel requests share one step-up and repeat once each", async () => {
    const answered = new Set<string>();
    const { fetchImpl, requests } = stubFetch((request) => {
      const key = path(request);
      if (answered.has(key)) return json(200, { other_sessions: 0 });
      answered.add(key);
      return json(403, { error: RECENT_AUTH_ERROR_CODE });
    });
    let resolve: (success: boolean) => void = () => {};
    const handler = vi.fn(
      () =>
        new Promise<boolean>((settle) => {
          resolve = settle;
        }),
    );
    setStepUpHandler(handler);
    const client = createApiClient(queryClient, fetchImpl);
    const remove = (id: string) =>
      client.DELETE("/api/me/passkeys/{id}", { params: { path: { id } } });

    const results = Promise.all([
      remove("0b9f3c1e-6a2d-4c8e-9f1a-2b3c4d5e6f70"),
      remove("1c0a4d2f-7b3e-4d9f-8a2b-3c4d5e6f7a81"),
    ]);
    await vi.waitFor(() => expect(requests).toHaveLength(2));
    queryClient.setQueryData<Session>(sessionQueryKey, {
      ...session,
      csrfToken: "token-2",
    });
    resolve(true);
    const [first, second] = await results;

    expect(handler).toHaveBeenCalledTimes(1);
    expect([first.response.status, second.response.status]).toEqual([200, 200]);
    expect(requests).toHaveLength(4);
    expect(
      requests.slice(2).map((request) => request.headers.get("x-csrf-token")),
    ).toEqual(["token-2", "token-2"]);
  });
});

test("a 403 answer with enrollment_required invalidates the session query and reaches the caller", async () => {
  const { fetchImpl, requests } = stubFetch(() =>
    json(403, { error: ENROLLMENT_ERROR_CODE }),
  );
  const handler = vi.fn(async () => true);
  const removeHandler = setStepUpHandler(handler);
  const client = createApiClient(queryClient, fetchImpl);

  try {
    const { response, error } = await client.POST("/api/me/totp");

    expect(response.status).toBe(403);
    expect(error).toEqual({ error: ENROLLMENT_ERROR_CODE });
    expect(queryClient.getQueryState(sessionQueryKey)?.isInvalidated).toBe(
      true,
    );
    expect(requests.map(path)).toEqual(["/api/me/totp"]);
    expect(handler).not.toHaveBeenCalled();
  } finally {
    removeHandler();
  }
});

test("a 401 answer removes every cached query except the session", async () => {
  queryClient.setQueryData(["me", "security"], { passkeys: [] });
  queryClient.setQueryData(["me", "sessions"], []);
  queryClient.setQueryData(["programs"], { programs: [] });
  const { fetchImpl } = stubFetch((request) =>
    path(request) === "/api/session"
      ? json(200, sessionPayload("token-2"))
      : json(401, { error: "unauthenticated" }),
  );
  const client = createApiClient(queryClient, fetchImpl);

  const { response } = await client.GET("/api/me/security");

  expect(response.status).toBe(401);
  expect(
    queryClient
      .getQueryCache()
      .getAll()
      .map((query) => query.queryKey),
  ).toEqual([sessionQueryKey]);
  expect(queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken).toBe(
    "token-1",
  );
  expect(queryClient.getQueryState(sessionQueryKey)?.isInvalidated).toBe(true);
});

test.each(["authentication_failed", "invalid_credentials", "ticket_invalid"])(
  "a 401 %s keeps the other cached queries and invalidates the session",
  async (code) => {
    queryClient.setQueryData(["me", "security"], { passkeys: [] });
    const { fetchImpl } = stubFetch((request) =>
      path(request) === "/api/session"
        ? json(200, sessionPayload("token-2"))
        : json(401, { error: code }),
    );
    const client = createApiClient(queryClient, fetchImpl);

    const { response } = await client.POST("/api/me/reauth", {
      body: { totp: "000000" },
    });

    expect(response.status).toBe(401);
    expect(queryClient.getQueryData(["me", "security"])).toEqual({
      passkeys: [],
    });
    expect(queryClient.getQueryState(sessionQueryKey)?.isInvalidated).toBe(
      true,
    );
  },
);

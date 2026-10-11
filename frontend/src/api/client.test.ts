import { QueryClient } from "@tanstack/react-query";
import { beforeEach, describe, expect, test, vi } from "vitest";
import { createApiClient } from "./client";
import { CSRF_ERROR_CODE } from "./errors";
import { sessionQueryKey, type Session } from "./session";

const session: Session = {
  user: {
    id: "8a4c7a5e-2f5b-4d6e-9c1a-3b2d4e5f6a7b",
    displayName: "Test person 1",
  },
  roles: ["learner"],
  sessionStrength: "demo",
  csrfToken: "token-1",
  providers: [],
  flags: { demo: true },
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

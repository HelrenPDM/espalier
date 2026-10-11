import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, type RenderResult } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { StrictMode, type ReactElement, type ReactNode } from "react";
import { createMemoryRouter, Outlet, RouterProvider } from "react-router";
import { vi } from "vitest";
import { StepUpProvider } from "../account/StepUpProvider";
import { ApiClientProvider } from "../api/ApiClientProvider";
import { createApiClient, type ApiClient } from "../api/client";
import {
  sessionQueryKey,
  toSession,
  type SessionPayload,
} from "../api/session";
import { SessionProvider } from "../auth/SessionProvider";
import "../i18n";
import { sessionPayload } from "./session";

/** A stubbed answer: status, JSON body and headers. */
export interface StubAnswer {
  status: number;
  body?: unknown;
  headers?: Record<string, string>;
}

/**
 * The answers of `stubFetch` by `"METHOD /path"`: one answer, a list that
 * answers the calls in turn (the last one repeats), or a function of the
 * request.
 */
export type StubResponses = Record<
  string,
  | StubAnswer
  | StubAnswer[]
  | ((request: RecordedRequest) => StubAnswer | Promise<StubAnswer>)
>;

/** A request as `stubFetch` saw it. */
export interface RecordedRequest {
  method: string;
  path: string;
  /** The parsed JSON body, or `null`. */
  body: unknown;
  headers: Headers;
  signal: AbortSignal;
}

const json = ({ status, body, headers = {} }: StubAnswer) =>
  new Response(
    status === 204 || body === undefined ? null : JSON.stringify(body),
    {
      status,
      headers:
        status === 204 || body === undefined
          ? headers
          : { "content-type": "application/json", ...headers },
    },
  );

/**
 * A fetch for `createApiClient` that answers from `responses` and records
 * every request. An unknown route answers 404 `not_found`.
 */
export function stubFetch(responses: StubResponses) {
  const requests: RecordedRequest[] = [];
  const calls = new Map<string, number>();

  const fetchImpl = vi.fn(async (request: Request) => {
    const path = new URL(request.url).pathname;
    const text = await request.clone().text();
    let body: unknown = null;
    try {
      body = text === "" ? null : JSON.parse(text);
    } catch {
      body = text;
    }
    const recorded: RecordedRequest = {
      method: request.method,
      path,
      body,
      headers: request.headers,
      signal: request.signal,
    };
    requests.push(recorded);

    const key = `${request.method} ${path}`;
    const entry = responses[key];
    const answer = async (): Promise<StubAnswer> => {
      if (entry === undefined)
        return { status: 404, body: { error: "not_found" } };
      if (typeof entry === "function") return entry(recorded);
      if (Array.isArray(entry)) {
        const index = calls.get(key) ?? 0;
        calls.set(key, index + 1);
        return entry[Math.min(index, entry.length - 1)];
      }
      return entry;
    };
    // An aborted request rejects with an AbortError, as fetch does.
    const aborted = new Promise<never>((_resolve, reject) => {
      const abort = () =>
        reject(new DOMException("The request was aborted.", "AbortError"));
      if (request.signal.aborted) abort();
      else request.signal.addEventListener("abort", abort, { once: true });
    });
    return json(await Promise.race([answer(), aborted]));
  });

  return { fetchImpl, requests };
}

export interface RenderOptions {
  /** The initial path, with query and fragment; the fragment also goes to `window.location`. */
  route?: string;
  /**
   * The route pattern under which `ui` renders, such as
   * `/me/credentials/:id` for a page that reads its parameters; the path of
   * `route` by default.
   */
  path?: string;
  /** The payload of `GET /api/session`, also put into the cache before the render. */
  session?: SessionPayload;
  responses?: StubResponses;
  /** Wraps the tree in `<StrictMode>`. */
  strict?: boolean;
}

export interface RenderWithProvidersResult extends RenderResult {
  router: ReturnType<typeof createMemoryRouter>;
  queryClient: QueryClient;
  client: ApiClient;
  requests: RecordedRequest[];
  user: ReturnType<typeof userEvent.setup>;
  /** The path, query and fragment of the memory router. */
  location: () => string;
}

/**
 * Renders `ui` at every path of a memory router, inside the providers of
 * the SPA: a `QueryClient` without retries, an API client over `stubFetch`,
 * `SessionProvider` and `StepUpProvider`.
 */
export function renderWithProviders(
  ui: ReactNode,
  {
    route = "/",
    path,
    session = sessionPayload(),
    responses = {},
    strict = false,
  }: RenderOptions = {},
): RenderWithProvidersResult {
  const url = new URL(route, window.location.origin);
  window.history.replaceState(null, "", url.pathname + url.search + url.hash);

  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  // The seeded session counts as fresh: only refetches of the page itself
  // (refreshSession, invalidation) read "GET /api/session" again.
  queryClient.setQueryDefaults(sessionQueryKey, { staleTime: Infinity });
  queryClient.setQueryData(sessionQueryKey, toSession(session));
  const { fetchImpl, requests } = stubFetch({
    "GET /api/session": { status: 200, body: session },
    ...responses,
  });
  const client = createApiClient(queryClient, fetchImpl);

  // `ui` renders at the initial path only, so a page that navigates away
  // does not render again at its destination.
  const router = createMemoryRouter(
    [
      {
        element: (
          <SessionProvider>
            <StepUpProvider>
              <Outlet />
            </StepUpProvider>
          </SessionProvider>
        ),
        children: [
          { path: path ?? url.pathname, element: ui },
          { path: "*", element: null },
        ],
      },
    ],
    { initialEntries: [url.pathname + url.search + url.hash] },
  );

  let tree: ReactElement = (
    <QueryClientProvider client={queryClient}>
      <ApiClientProvider client={client}>
        <RouterProvider router={router} />
      </ApiClientProvider>
    </QueryClientProvider>
  );
  if (strict) tree = <StrictMode>{tree}</StrictMode>;

  const user = userEvent.setup();
  const result = render(tree);
  const location = () =>
    router.state.location.pathname +
    router.state.location.search +
    router.state.location.hash;

  return { ...result, router, queryClient, client, requests, user, location };
}

/**
 * Replaces `window.location.assign` for the current test; jsdom implements
 * no navigation. Every other member reads the real location.
 */
export function stubLocationAssign() {
  const assign = vi.fn();
  const real = window.location;
  const stub: Record<string, unknown> = {
    assign,
    replace: (url: string) => real.replace(url),
    reload: () => real.reload(),
    toString: () => real.href,
  };
  for (const key of [
    "href",
    "origin",
    "protocol",
    "host",
    "hostname",
    "port",
    "pathname",
    "search",
    "hash",
  ] as const)
    Object.defineProperty(stub, key, { get: () => real[key] });
  vi.stubGlobal("location", stub);
  return assign;
}

/** The requests of `requests` to `path` with `method`. */
export const requestsTo = (
  requests: RecordedRequest[],
  method: string,
  path: string,
) =>
  requests.filter(
    (request) => request.method === method && request.path === path,
  );

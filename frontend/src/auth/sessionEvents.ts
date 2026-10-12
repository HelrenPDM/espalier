import { useQueryClient, type QueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useMemo, useRef } from "react";
import { useNavigate } from "react-router";
import type { ApiClient } from "../api/client";
import { useApiClient } from "../api/apiClientContext";
import {
  sessionQueryKey,
  sessionQueryOptions,
  type Session,
} from "../api/session";
import { listenMessages } from "../app/messages";
import { resetTestNotes } from "../learner/test-notes/store";

/**
 * Session changes and their synchronization across tabs (task 0011, step 4;
 * ASVS 3.5.1, 3.5.5, 14.3.1). Every response that issues or ends a session
 * token leads to `sessionChanged`, which refetches the session, and with it
 * the new CSRF token, and tells the other tabs through `BroadcastChannel`.
 * A message carries the kind of change only. A sign-out and a sign-in also
 * end the test session notes of the tab (task 0014, step 11), so the next
 * person in the same tab does not see the events of the previous one.
 */
export type SessionChangeKind = "signed-in" | "renewed" | "signed-out";

export interface SessionMessage {
  kind: SessionChangeKind;
}

const CHANNEL_NAME = "espalier-session";
const KINDS: readonly string[] = ["signed-in", "renewed", "signed-out"];

const channelsSupported = () => typeof BroadcastChannel === "function";

// The channel of `useSessionTabSync` in this tab. A message reaches every
// other BroadcastChannel object of the same name, also in the same tab, so
// posting through the listening object keeps a tab from handling its own
// message.
let tabChannel: BroadcastChannel | null = null;

function post(message: SessionMessage) {
  if (!channelsSupported()) return;
  if (tabChannel) {
    tabChannel.postMessage(message);
    return;
  }
  const channel = new BroadcastChannel(CHANNEL_NAME);
  channel.postMessage(message);
  channel.close();
}

/**
 * Drops every value of the signed-out account (ASVS 14.3.1): every cached
 * query except the session, every mutation, the data of the session query
 * and the test session notes of this tab (`resetTestNotes`). The session
 * query stays in the cache and returns to its initial state without a
 * refetch: the observer of `SessionProvider` keeps it (a removed query
 * would leave that observer on the old data), and the guards wait until
 * the caller has navigated and refetches the session.
 */
export function clearAccountData(queryClient: QueryClient): void {
  resetTestNotes();
  queryClient.removeQueries({
    predicate: (query) => query.queryKey[0] !== sessionQueryKey[0],
  });
  queryClient.getMutationCache().clear();
  queryClient
    .getQueryCache()
    .find({ queryKey: sessionQueryKey, exact: true })
    ?.reset();
}

/** Loads the session again, which puts the current CSRF token into the cache. */
export function refreshSession(
  queryClient: QueryClient,
  client: ApiClient,
): Promise<Session> {
  return queryClient.fetchQuery({
    ...sessionQueryOptions(client),
    staleTime: 0,
  });
}

/**
 * Handles a session change of this tab: `signed-out` clears the account
 * data first (`clearAccountData`), and `signed-in` ends the test session
 * notes of the previous session (`resetTestNotes`); then the session is
 * refetched and the other tabs receive `{ kind }`. The promise settles
 * after the refetch, also when it fails.
 */
export async function sessionChanged(
  kind: SessionChangeKind,
  queryClient: QueryClient,
  client: ApiClient,
): Promise<void> {
  if (kind === "signed-out") clearAccountData(queryClient);
  else if (kind === "signed-in") resetTestNotes();
  const refreshed = refreshSession(queryClient, client).catch(() => undefined);
  post({ kind });
  await refreshed;
}

/**
 * Returns `{ kind }` for an object whose only member is `kind` with a known
 * value, and `null` for every other value.
 */
export function parseSessionMessage(data: unknown): SessionMessage | null {
  if (typeof data !== "object" || data === null || Array.isArray(data))
    return null;
  const keys = Object.keys(data);
  if (keys.length !== 1 || keys[0] !== "kind") return null;
  const { kind } = data as { kind: unknown };
  if (typeof kind !== "string" || !KINDS.includes(kind)) return null;
  return { kind: kind as SessionChangeKind };
}

/** `refreshSession` and `sessionChanged` bound to the clients of the tree. */
export function useSessionEvents() {
  const queryClient = useQueryClient();
  const client = useApiClient();
  return useMemo(
    () => ({
      refreshSession: () => refreshSession(queryClient, client),
      sessionChanged: (kind: SessionChangeKind) =>
        sessionChanged(kind, queryClient, client),
    }),
    [queryClient, client],
  );
}

/**
 * Follows the session changes of other tabs. Mounted once next to
 * `SessionProvider`. Every valid message refetches the session; `signed-out`
 * runs `onSignedOut`, which clears the account data and opens `/sign-in`
 * before the refetch, and `signed-in` ends the test session notes of this
 * tab first, because the tab now belongs to the session of the other tab.
 * `listenMessages` drops every message that `parseSessionMessage` rejects,
 * so a malformed message triggers no request (ASVS 3.5.5).
 */
export function useSessionTabSync(onSignedOut?: () => Promise<void>): void {
  const queryClient = useQueryClient();
  const client = useApiClient();
  const navigate = useNavigate();
  const signedOut = useRef(onSignedOut);
  useEffect(() => {
    signedOut.current = onSignedOut;
  });

  // The navigation to /sign-in comes before the refetch, so a guarded page
  // does not redirect with itself in `return_to` first.
  const handle = useCallback(
    async (message: SessionMessage) => {
      if (message.kind !== "signed-out") {
        if (message.kind === "signed-in") resetTestNotes();
        await refreshSession(queryClient, client).catch(() => undefined);
      } else if (signedOut.current) {
        await signedOut.current();
      } else {
        clearAccountData(queryClient);
        await navigate("/sign-in");
        await refreshSession(queryClient, client).catch(() => undefined);
      }
    },
    [client, navigate, queryClient],
  );

  useEffect(() => {
    if (!channelsSupported()) return undefined;
    const channel = new BroadcastChannel(CHANNEL_NAME);
    tabChannel = channel;
    const stop = listenMessages(channel, parseSessionMessage, (message) => {
      void handle(message);
    });
    return () => {
      stop();
      if (tabChannel === channel) tabChannel = null;
      channel.close();
    };
  }, [handle]);
}

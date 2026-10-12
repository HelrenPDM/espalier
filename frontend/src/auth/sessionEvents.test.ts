import { act, screen, waitFor } from "@testing-library/react";
import { createElement } from "react";
import { afterEach, describe, expect, test, vi } from "vitest";
import { sessionQueryKey, type Session } from "../api/session";
import {
  renderWithProviders,
  requestsTo,
  type RecordedRequest,
  type StubResponses,
} from "../test/render";
import { sessionPayload, signedInPayload } from "../test/session";
import { useSession } from "./SessionProvider";
import { parseSessionMessage, sessionChanged } from "./sessionEvents";
import { listenMessages } from "../app/messages";
import { TEST_NOTES_KEY, testNotesLog } from "../learner/test-notes/store";

const CHANNEL = "espalier-session";
const securityKey = ["me", "security"] as const;

const opened: BroadcastChannel[] = [];

/** Another tab: a channel of the same name outside the rendered tree. */
function otherTab() {
  const channel = new BroadcastChannel(CHANNEL);
  opened.push(channel);
  const received: unknown[] = [];
  listenMessages(
    channel,
    (data) => data,
    (data) => received.push(data),
  );
  return { channel, received };
}

/** Waits for the delivery of the posted messages (a timer of the channel). */
const delivery = () =>
  act(() => new Promise<void>((resolve) => setTimeout(resolve, 20)));

afterEach(() => {
  for (const channel of opened.splice(0)) channel.close();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  testNotesLog(true).clear();
});

/** A finished mutation in the cache, such as a TOTP setup with its secret. */
async function seedMutation(
  queryClient: ReturnType<typeof renderWithProviders>["queryClient"],
) {
  await queryClient
    .getMutationCache()
    .build(queryClient, {
      mutationFn: async () => ({ secret_base32: "JBSWY3DPEHPK3PXP" }),
      gcTime: Infinity,
    })
    .execute(undefined);
}

/** The page: the user that `SessionProvider` provides. */
function Page() {
  const { user } = useSession();
  return createElement("p", null, `page of ${user?.email ?? "nobody"}`);
}

/** Mounts `useSessionTabSync` through `SessionProvider`. */
async function renderTab(responses: StubResponses = {}) {
  const result = renderWithProviders(createElement(Page), {
    route: "/account/security",
    session: signedInPayload("mfa"),
    responses,
  });
  await screen.findByText("page of ada@example.test");
  result.queryClient.setQueryData(securityKey, { passkeys: [] });
  await seedMutation(result.queryClient);
  return result;
}

const sessionGets = (requests: RecordedRequest[]) =>
  requestsTo(requests, "GET", "/api/session");

describe("parseSessionMessage", () => {
  test.each(["signed-in", "renewed", "signed-out"] as const)(
    "returns { kind } for %s",
    (kind) => {
      expect(parseSessionMessage({ kind })).toEqual({ kind });
    },
  );

  test.each([
    ["an unknown kind", { kind: "unknown" }],
    ["a string", "signed-out"],
    ["an extra member", { kind: "signed-in", extra: 1 }],
    ["a kind of another type", { kind: 1 }],
    ["an empty object", {}],
    ["a list", [{ kind: "signed-out" }]],
    ["null", null],
    ["undefined", undefined],
  ])("returns null for %s", (_name, data) => {
    expect(parseSessionMessage(data)).toBeNull();
  });
});

describe("a message of another tab", () => {
  test("signed-out clears the query cache, opens /sign-in and refetches the session", async () => {
    const { queryClient, requests, location } = await renderTab({
      "GET /api/session": { status: 200, body: sessionPayload() },
    });
    expect(sessionGets(requests)).toHaveLength(0);

    otherTab().channel.postMessage({ kind: "signed-out" });

    await waitFor(() => expect(location()).toBe("/sign-in"));
    expect(queryClient.getQueryData(securityKey)).toBeUndefined();
    expect(queryClient.getMutationCache().getAll()).toEqual([]);
    expect(
      queryClient.getQueryData<Session>(sessionQueryKey)?.user ?? null,
    ).toBeNull();
    await waitFor(() => expect(sessionGets(requests)).toHaveLength(1));
    await waitFor(() =>
      expect(
        queryClient.getQueryData<Session>(sessionQueryKey)?.user,
      ).toBeNull(),
    );
  });

  test("renewed refetches the session and keeps the cache", async () => {
    const { queryClient, requests, location } = await renderTab({
      "GET /api/session": {
        status: 200,
        body: signedInPayload("mfa", { csrf_token: "csrf-2" }),
      },
    });

    otherTab().channel.postMessage({ kind: "renewed" });

    await waitFor(() => expect(sessionGets(requests)).toHaveLength(1));
    await waitFor(() =>
      expect(
        queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken,
      ).toBe("csrf-2"),
    );
    expect(queryClient.getQueryData(securityKey)).toEqual({ passkeys: [] });
    expect(queryClient.getMutationCache().getAll()).toHaveLength(1);
    expect(location()).toBe("/account/security");
  });

  test.each([
    ["an unknown kind", { kind: "unknown" }],
    ["a string", "signed-out"],
    ["an extra member", { kind: "signed-in", extra: 1 }],
  ])(
    "with %s leaves no GET /api/session and keeps the cache",
    async (_name, data) => {
      const { queryClient, requests, location } = await renderTab();
      const { channel } = otherTab();

      channel.postMessage(data);
      await delivery();

      expect(sessionGets(requests)).toHaveLength(0);
      expect(queryClient.getQueryData(securityKey)).toEqual({ passkeys: [] });
      expect(queryClient.getMutationCache().getAll()).toHaveLength(1);
      expect(location()).toBe("/account/security");

      // The listener is alive: a valid message after it refetches once.
      channel.postMessage({ kind: "renewed" });
      await waitFor(() => expect(sessionGets(requests)).toHaveLength(1));
    },
  );

  test("after the unmount triggers no request", async () => {
    const { requests, unmount } = await renderTab();
    unmount();

    otherTab().channel.postMessage({ kind: "renewed" });
    await delivery();

    expect(sessionGets(requests)).toHaveLength(0);
  });
});

describe("sessionChanged", () => {
  test("renewed refetches the session and reaches another tab but not the own listener", async () => {
    const { queryClient, client, requests } = await renderTab({
      "GET /api/session": {
        status: 200,
        body: signedInPayload("mfa", { csrf_token: "csrf-2" }),
      },
    });
    const { received } = otherTab();

    await act(() => sessionChanged("renewed", queryClient, client));

    expect(sessionGets(requests)).toHaveLength(1);
    expect(queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken).toBe(
      "csrf-2",
    );
    await waitFor(() => expect(received).toEqual([{ kind: "renewed" }]));
    await delivery();
    expect(sessionGets(requests)).toHaveLength(1);
  });

  test("signed-out clears the cache before the refetch and tells another tab", async () => {
    const { queryClient, client, requests, location } = await renderTab({
      "GET /api/session": { status: 200, body: sessionPayload() },
    });
    const { received } = otherTab();

    const changed = sessionChanged("signed-out", queryClient, client);
    // Synchronously, before the refetch answers: no value of the account.
    expect(queryClient.getQueryData(securityKey)).toBeUndefined();
    expect(queryClient.getMutationCache().getAll()).toEqual([]);
    expect(queryClient.getQueryData(sessionQueryKey)).toBeUndefined();
    await act(() => changed);

    expect(sessionGets(requests)).toHaveLength(1);
    expect(queryClient.getQueryData<Session>(sessionQueryKey)?.user).toBeNull();
    await waitFor(() => expect(received).toEqual([{ kind: "signed-out" }]));
    await delivery();
    // The own listener did not handle the message.
    expect(location()).toBe("/account/security");
    expect(sessionGets(requests)).toHaveLength(1);
  });

  test("signed-out hands the refetched session to SessionProvider", async () => {
    const { queryClient, client } = await renderTab({
      "GET /api/session": { status: 200, body: sessionPayload() },
    });

    await act(() => sessionChanged("signed-out", queryClient, client));

    expect(await screen.findByText("page of nobody")).toBeInTheDocument();
  });

  test("settles after a failed refetch", async () => {
    const { queryClient, client } = await renderTab({
      "GET /api/session": { status: 500, body: { error: "internal" } },
    });

    await expect(
      act(() => sessionChanged("renewed", queryClient, client)),
    ).resolves.toBeUndefined();
  });

  test("without BroadcastChannel still refetches the session", async () => {
    vi.stubGlobal("BroadcastChannel", undefined);
    const { queryClient, client, requests } = await renderTab({
      "GET /api/session": {
        status: 200,
        body: signedInPayload("mfa", { csrf_token: "csrf-2" }),
      },
    });

    await act(() => sessionChanged("renewed", queryClient, client));

    expect(sessionGets(requests)).toHaveLength(1);
    expect(queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken).toBe(
      "csrf-2",
    );
  });
});

/**
 * Task 0014 step 11: the test session notes of a tab end with a sign-out
 * and a sign-in, so the next test person in the same tab sees neither the
 * item correctness nor the exam outcomes of the previous one, and the clock
 * of the log starts again.
 */
describe("the test session notes", () => {
  const notes = testNotesLog(true);

  /** Records two notes five seconds apart, as the previous person did. */
  function recordNotes() {
    const now = vi.spyOn(Date, "now");
    now.mockReturnValue(10_000);
    notes.record({ event: "item_answered", item: "item-1", correct: true });
    now.mockReturnValue(15_000);
    notes.record({
      event: "exam_submitted",
      assessment: "exam-1",
      outcome: "passed",
    });
    now.mockRestore();
    expect(notes.notes()).toHaveLength(2);
    expect(sessionStorage.getItem(TEST_NOTES_KEY)).not.toBeNull();
  }

  /** The log is empty, its key gone, and the next note starts the clock. */
  function expectNotesEnded() {
    expect(notes.notes()).toEqual([]);
    expect(sessionStorage.getItem(TEST_NOTES_KEY)).toBeNull();
    const now = vi.spyOn(Date, "now").mockReturnValue(90_000);
    notes.record({ event: "station_opened", station: 1 });
    now.mockRestore();
    expect(notes.notes()).toEqual([
      { event: "station_opened", station: 1, at: 0 },
    ]);
  }

  /** A page with the sign-out of `SessionProvider`. */
  function SignOutButton() {
    const { signOut } = useSession();
    return createElement(
      "button",
      { type: "button", onClick: () => void signOut() },
      "Sign out",
    );
  }

  test("end with the sign-out of this tab", async () => {
    const { user, location } = renderWithProviders(
      createElement(SignOutButton),
      {
        route: "/account/security",
        session: signedInPayload("mfa"),
        responses: {
          "DELETE /api/session": { status: 204 },
          "GET /api/session": { status: 200, body: sessionPayload() },
        },
      },
    );
    await screen.findByRole("button", { name: "Sign out" });
    recordNotes();

    await user.click(screen.getByRole("button", { name: "Sign out" }));

    await waitFor(() => expect(location()).toBe("/sign-in"));
    expectNotesEnded();
  });

  test.each(["signed-out", "signed-in"] as const)(
    "end with sessionChanged %s",
    async (kind) => {
      const { queryClient, client } = await renderTab({
        "GET /api/session": {
          status: 200,
          body:
            kind === "signed-out" ? sessionPayload() : signedInPayload("mfa"),
        },
      });
      recordNotes();

      await act(() => sessionChanged(kind, queryClient, client));

      expectNotesEnded();
    },
  );

  test.each(["signed-out", "signed-in"] as const)(
    "end with a %s message of another tab",
    async (kind) => {
      const { requests } = await renderTab({
        "GET /api/session": {
          status: 200,
          body:
            kind === "signed-out" ? sessionPayload() : signedInPayload("mfa"),
        },
      });
      recordNotes();

      otherTab().channel.postMessage({ kind });

      await waitFor(() => expect(sessionGets(requests)).toHaveLength(1));
      expectNotesEnded();
    },
  );

  test("stay with a renewed session", async () => {
    const { queryClient, client, requests } = await renderTab({
      "GET /api/session": { status: 200, body: signedInPayload("mfa") },
    });
    recordNotes();

    await act(() => sessionChanged("renewed", queryClient, client));
    otherTab().channel.postMessage({ kind: "renewed" });
    await waitFor(() => expect(sessionGets(requests)).toHaveLength(2));

    expect(notes.notes()).toHaveLength(2);
    expect(sessionStorage.getItem(TEST_NOTES_KEY)).not.toBeNull();
  });
});

import { screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { sessionQueryKey, type Session } from "../api/session";
import {
  renderWithProviders,
  requestsTo,
  stubLocationAssign,
  type StubResponses,
} from "../test/render";
import { sessionPayload, signedInPayload } from "../test/session";
import { useSession } from "./SessionProvider";
import { takeReturnTo } from "./returnTo";
import { listenMessages } from "../app/messages";

const LOGOUT_URL =
  "https://login.example.test/oauth2/logout?post_logout_redirect_uri=x";
const securityKey = ["me", "security"] as const;

afterEach(() => {
  vi.unstubAllGlobals();
  takeReturnTo();
});

function SignOutButton() {
  const { signOut } = useSession();
  return (
    <button type="button" onClick={() => void signOut()}>
      Sign out
    </button>
  );
}

async function renderSignOut(responses: StubResponses) {
  const result = renderWithProviders(<SignOutButton />, {
    route: "/account/security",
    session: signedInPayload("mfa", {
      session: { auth_methods: ["oidc", "idp_mfa"], provider_key: "entra" },
    }),
    responses: {
      "GET /api/session": { status: 200, body: sessionPayload() },
      ...responses,
    },
  });
  await screen.findByRole("button", { name: "Sign out" });
  result.queryClient.setQueryData(securityKey, { passkeys: [] });
  // A finished mutation, such as a TOTP setup with its secret.
  await result.queryClient
    .getMutationCache()
    .build(result.queryClient, {
      mutationFn: async () => ({ secret_base32: "JBSWY3DPEHPK3PXP" }),
      gcTime: Infinity,
    })
    .execute(undefined);
  return result;
}

/** The keys of the cached queries that hold data. */
const keysWithData = (
  queryClient: Awaited<ReturnType<typeof renderSignOut>>["queryClient"],
) =>
  queryClient
    .getQueryCache()
    .getAll()
    .filter((query) => query.state.data !== undefined)
    .map((query) => query.queryKey);

test("a 200 with logout_url clears the query cache and then calls window.location.assign", async () => {
  const assign = stubLocationAssign();
  const { queryClient, requests, user, location } = await renderSignOut({
    "DELETE /api/session": { status: 200, body: { logout_url: LOGOUT_URL } },
  });
  let cachedAtAssign: unknown[] | null = null;
  let mutationsAtAssign = -1;
  assign.mockImplementation(() => {
    cachedAtAssign = keysWithData(queryClient);
    mutationsAtAssign = queryClient.getMutationCache().getAll().length;
  });
  expect(keysWithData(queryClient)).toEqual([sessionQueryKey, securityKey]);
  expect(queryClient.getMutationCache().getAll()).toHaveLength(1);

  await user.click(screen.getByRole("button", { name: "Sign out" }));

  await waitFor(() => expect(assign).toHaveBeenCalledWith(LOGOUT_URL));
  expect(assign).toHaveBeenCalledTimes(1);
  // At the moment of the navigation no query holds data of the account:
  // the session query is reset and refetches.
  expect(cachedAtAssign).toEqual([]);
  expect(mutationsAtAssign).toBe(0);
  expect(queryClient.getQueryData(securityKey)).toBeUndefined();
  expect(location()).toBe("/account/security");
  const [deleted] = requestsTo(requests, "DELETE", "/api/session");
  expect(deleted.headers.get("x-csrf-token")).toBe("csrf-1");
});

test("a 204 clears the query cache and leads to /sign-in", async () => {
  const assign = stubLocationAssign();
  const { queryClient, requests, user, location } = await renderSignOut({
    "DELETE /api/session": { status: 204 },
  });
  const otherTab = new BroadcastChannel("espalier-session");
  const received: unknown[] = [];
  listenMessages(
    otherTab,
    (data) => data,
    (data) => received.push(data),
  );

  try {
    await user.click(screen.getByRole("button", { name: "Sign out" }));

    await waitFor(() => expect(location()).toBe("/sign-in"));
    expect(assign).not.toHaveBeenCalled();
    expect(queryClient.getQueryData(securityKey)).toBeUndefined();
    expect(queryClient.getMutationCache().getAll()).toEqual([]);
    expect(requestsTo(requests, "DELETE", "/api/session")).toHaveLength(1);
    await waitFor(() =>
      expect(
        queryClient.getQueryData<Session>(sessionQueryKey)?.user,
      ).toBeNull(),
    );
    await waitFor(() => expect(received).toEqual([{ kind: "signed-out" }]));
  } finally {
    otherTab.close();
  }
});

test("a failed DELETE keeps the session and the page", async () => {
  const assign = stubLocationAssign();
  const { queryClient, requests, user, location } = await renderSignOut({
    "DELETE /api/session": { status: 500, body: { error: "internal" } },
  });

  await user.click(screen.getByRole("button", { name: "Sign out" }));

  await waitFor(() =>
    expect(requestsTo(requests, "DELETE", "/api/session")).toHaveLength(1),
  );
  expect(assign).not.toHaveBeenCalled();
  expect(location()).toBe("/account/security");
  expect(queryClient.getQueryData(securityKey)).toEqual({ passkeys: [] });
  expect(queryClient.getMutationCache().getAll()).toHaveLength(1);
  expect(queryClient.getQueryData<Session>(sessionQueryKey)?.user?.email).toBe(
    "ada@example.test",
  );
  expect(requestsTo(requests, "GET", "/api/session")).toHaveLength(0);
});

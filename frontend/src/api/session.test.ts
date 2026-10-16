import { afterEach, expect, test } from "vitest";
import { toSession } from "./session";

const prototypeKeys = () => Object.getOwnPropertyNames(Object.prototype).sort();
const keysBefore = prototypeKeys();

afterEach(() => {
  expect(prototypeKeys()).toEqual(keysBefore);
});

// JSON.parse creates `__proto__` and `constructor` as own members, as the
// body of a fetch response does.
const hostilePayload = () =>
  JSON.parse(`{
    "__proto__": {"polluted": true},
    "constructor": {"prototype": {"polluted": true}},
    "user": {
      "id": "8a4c7a5e-2f5b-4d6e-9c1a-3b2d4e5f6a7b",
      "display_name": "Test person 1",
      "email": null,
      "locale": "en",
      "__proto__": {"polluted": true},
      "constructor": {"prototype": {"polluted": true}}
    },
    "roles": ["learner"],
    "session": {
      "strength": "demo",
      "auth_methods": ["demo"],
      "provider_key": null,
      "recent_auth_until": null,
      "expires_at": "2026-10-12T10:00:00Z",
      "idle_timeout_minutes": 60,
      "__proto__": {"polluted": true}
    },
    "pending": null,
    "csrf_token": "token-1",
    "providers": [{
      "key": "entra",
      "type": "entra",
      "kind": "redirect",
      "label": "Entra ID",
      "start_url": "/auth/oidc/entra",
      "__proto__": {"polluted": true},
      "constructor": {"prototype": {"polluted": true}}
    }],
    "flags": {
      "demo": true,
      "local_accounts": true,
      "signup": "closed",
      "admin_passkey_required": false,
      "test_notes": true,
      "feedback_free_text": false,
      "media_embed_consent": "click",
      "__proto__": {"polluted": true}
    }
  }`);

test("toSession copies only the members it knows and pollutes no prototype", () => {
  const session = toSession(hostilePayload());

  expect(session).toEqual({
    user: {
      id: "8a4c7a5e-2f5b-4d6e-9c1a-3b2d4e5f6a7b",
      displayName: "Test person 1",
      email: null,
    },
    roles: ["learner"],
    sessionStrength: "demo",
    authMethods: ["demo"],
    providerKey: null,
    recentAuthUntil: null,
    pending: null,
    csrfToken: "token-1",
    providers: [
      {
        key: "entra",
        type: "entra",
        kind: "redirect",
        label: "Entra ID",
        startUrl: "/auth/oidc/entra",
      },
    ],
    flags: {
      demo: true,
      localAccounts: true,
      signup: "closed",
      adminPasskeyRequired: false,
      testNotes: true,
      feedbackFreeText: false,
      mediaEmbedConsent: "click",
    },
  });
  expect(Object.keys(session)).toEqual([
    "user",
    "roles",
    "sessionStrength",
    "authMethods",
    "providerKey",
    "recentAuthUntil",
    "pending",
    "csrfToken",
    "providers",
    "flags",
  ]);
  expect(Object.keys(session.user ?? {})).toEqual([
    "id",
    "displayName",
    "email",
  ]);
  expect(Object.keys(session.providers[0])).toEqual([
    "key",
    "type",
    "kind",
    "label",
    "startUrl",
  ]);
  expect(Object.keys(session.flags)).toEqual([
    "demo",
    "localAccounts",
    "signup",
    "adminPasskeyRequired",
    "testNotes",
    "feedbackFreeText",
    "mediaEmbedConsent",
  ]);

  for (const value of [
    session,
    session.user,
    session.providers[0],
    session.flags,
  ]) {
    expect(Object.getPrototypeOf(value)).toBe(Object.prototype);
  }
  expect(Object.getPrototypeOf(session.roles)).toBe(Array.prototype);
  expect(({} as Record<string, unknown>).polluted).toBeUndefined();
  expect(Object.prototype).not.toHaveProperty("polluted");
});

test("toSession maps a signed-out payload to null user and strength", () => {
  const payload = hostilePayload();
  payload.user = null;
  payload.session = null;

  const session = toSession(payload);

  expect(session.user).toBeNull();
  expect(session.sessionStrength).toBeNull();
});

test("toSession maps the pending state, the provider key and every flag", () => {
  const payload = hostilePayload();
  payload.user = null;
  payload.session = {
    strength: "mfa",
    auth_methods: ["oidc", "idp_mfa"],
    provider_key: "entra",
    recent_auth_until: "2026-10-12T09:10:00Z",
    expires_at: "2026-10-12T10:00:00Z",
    idle_timeout_minutes: 60,
  };
  payload.pending = {
    next: "second_factor",
    expires_at: "2026-10-11T10:05:00Z",
  };
  payload.flags = {
    demo: false,
    local_accounts: false,
    signup: "domain",
    admin_passkey_required: true,
    test_notes: false,
    feedback_free_text: true,
    media_embed_consent: "auto",
  };

  const session = toSession(payload);

  expect(session.authMethods).toEqual(["oidc", "idp_mfa"]);
  expect(session.providerKey).toBe("entra");
  expect(session.recentAuthUntil).toBe("2026-10-12T09:10:00Z");
  expect(session.pending).toEqual({
    next: "second_factor",
    expiresAt: "2026-10-11T10:05:00Z",
  });
  expect(session.flags).toEqual({
    demo: false,
    localAccounts: false,
    signup: "domain",
    adminPasskeyRequired: true,
    testNotes: false,
    feedbackFreeText: true,
    mediaEmbedConsent: "auto",
  });
});

test("toSession drops a provider entry with an unknown kind", () => {
  const payload = hostilePayload();
  payload.providers.push({
    key: "other",
    type: "oidc",
    kind: "popup",
    label: "Other",
    start_url: "/auth/other",
  });

  expect(toSession(payload).providers.map((provider) => provider.key)).toEqual([
    "entra",
  ]);
});

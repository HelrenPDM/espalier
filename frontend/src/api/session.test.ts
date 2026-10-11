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
      "__proto__": {"polluted": true}
    }
  }`);

test("toSession copies only the members it knows and pollutes no prototype", () => {
  const session = toSession(hostilePayload());

  expect(session).toEqual({
    user: {
      id: "8a4c7a5e-2f5b-4d6e-9c1a-3b2d4e5f6a7b",
      displayName: "Test person 1",
    },
    roles: ["learner"],
    sessionStrength: "demo",
    csrfToken: "token-1",
    providers: [
      {
        key: "entra",
        type: "entra",
        kind: "redirect",
        label: "Entra ID",
        start_url: "/auth/oidc/entra",
      },
    ],
    flags: { demo: true },
  });
  expect(Object.keys(session)).toEqual([
    "user",
    "roles",
    "sessionStrength",
    "csrfToken",
    "providers",
    "flags",
  ]);
  expect(Object.keys(session.user ?? {})).toEqual(["id", "displayName"]);
  expect(Object.keys(session.providers[0])).toEqual([
    "key",
    "type",
    "kind",
    "label",
    "start_url",
  ]);
  expect(Object.keys(session.flags)).toEqual(["demo"]);

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

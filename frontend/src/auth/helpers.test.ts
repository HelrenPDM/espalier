import { afterEach, describe, expect, test, vi } from "vitest";
import { webauthnError } from "../test/webauthn";
import { takeFragmentParam } from "./fragment";
import { rememberReturnTo, takeReturnTo } from "./returnTo";
import { classifyWebAuthnError } from "./webauthn";

const RETURN_TO_KEY = "espalier.return_to";

afterEach(() => {
  vi.restoreAllMocks();
  takeReturnTo();
  window.history.replaceState(null, "", "/");
});

describe("takeFragmentParam", () => {
  test("reads the parameter and removes the fragment, keeping path and query", () => {
    window.history.replaceState(
      { idx: 3 },
      "",
      "/auth/finish?lang=de#ticket=t-1&other=2",
    );
    const replaceState = vi.spyOn(window.history, "replaceState");

    expect(takeFragmentParam("ticket")).toBe("t-1");

    expect(replaceState).toHaveBeenCalledTimes(1);
    expect(replaceState).toHaveBeenCalledWith(
      { idx: 3 },
      "",
      "/auth/finish?lang=de",
    );
    expect(window.location.hash).toBe("");
    expect(window.location.href).toBe(
      `${window.location.origin}/auth/finish?lang=de`,
    );
    expect(window.history.state).toEqual({ idx: 3 });
  });

  test("returns null for a missing parameter and still removes the fragment", () => {
    window.history.replaceState(null, "", "/account/email/confirm#other=2");

    expect(takeFragmentParam("token")).toBeNull();

    expect(window.location.hash).toBe("");
    expect(window.location.pathname).toBe("/account/email/confirm");
  });

  test("returns null without a fragment", () => {
    window.history.replaceState(null, "", "/invite");

    expect(takeFragmentParam("token")).toBeNull();
    expect(window.location.pathname + window.location.search).toBe("/invite");
  });

  test("decodes the parameter value", () => {
    window.history.replaceState(null, "", "/recover#token=a%2Bb%3D");

    expect(takeFragmentParam("token")).toBe("a+b=");
  });
});

describe("classifyWebAuthnError", () => {
  test("a ceremony the SPA cancelled is aborted", () => {
    expect(
      classifyWebAuthnError(
        webauthnError("AbortError", "ERROR_CEREMONY_ABORTED"),
      ),
    ).toBe("aborted");
  });

  test("a closed or timed-out browser dialog is cancelled", () => {
    expect(
      classifyWebAuthnError(
        webauthnError(
          "NotAllowedError",
          "ERROR_PASSTHROUGH_SEE_CAUSE_PROPERTY",
        ),
      ),
    ).toBe("cancelled");
    expect(
      classifyWebAuthnError(new DOMException("closed", "NotAllowedError")),
    ).toBe("cancelled");
  });

  test("a passkey the authenticator already holds is a duplicate", () => {
    expect(
      classifyWebAuthnError(
        webauthnError(
          "InvalidStateError",
          "ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED",
        ),
      ),
    ).toBe("duplicate");
  });

  test.each([
    [
      "another WebAuthn error",
      webauthnError("SecurityError", "ERROR_INVALID_DOMAIN"),
    ],
    ["a plain error", new Error("failed")],
    ["null", null],
    ["undefined", undefined],
    ["a string", "NotAllowedError"],
  ])("%s has failed", (_name, error) => {
    expect(classifyWebAuthnError(error)).toBe("failed");
  });
});

describe("rememberReturnTo and takeReturnTo", () => {
  test("keep one path under espalier.return_to and delete it on read", () => {
    const setItem = vi.spyOn(Storage.prototype, "setItem");
    const removeItem = vi.spyOn(Storage.prototype, "removeItem");

    rememberReturnTo("/programs/demo?step=2");

    expect(setItem).toHaveBeenCalledWith(
      RETURN_TO_KEY,
      "/programs/demo?step=2",
    );
    expect(takeReturnTo()).toBe("/programs/demo?step=2");
    expect(removeItem).toHaveBeenCalledWith(RETURN_TO_KEY);
    expect(takeReturnTo()).toBeNull();
  });

  test("a second path replaces the first", () => {
    rememberReturnTo("/account/security");
    rememberReturnTo("/programs/demo");

    expect(takeReturnTo()).toBe("/programs/demo");
    expect(takeReturnTo()).toBeNull();
  });

  test("takeReturnTo returns null when nothing is stored", () => {
    expect(takeReturnTo()).toBeNull();
  });

  test("store and read only safeReturnTo values", () => {
    const setItem = vi.spyOn(Storage.prototype, "setItem");
    rememberReturnTo("//evil.example");
    expect(setItem).toHaveBeenCalledWith(RETURN_TO_KEY, "/");
    expect(takeReturnTo()).toBe("/");

    vi.spyOn(Storage.prototype, "getItem").mockReturnValueOnce(
      "https://evil.example/",
    );
    expect(takeReturnTo()).toBe("/");
  });

  test("survive a storage that throws", () => {
    const blocked = () => {
      throw new DOMException("The operation is insecure.", "SecurityError");
    };
    const setItem = vi
      .spyOn(Storage.prototype, "setItem")
      .mockImplementation(blocked);
    const getItem = vi
      .spyOn(Storage.prototype, "getItem")
      .mockImplementation(blocked);

    expect(() => rememberReturnTo("/account/security")).not.toThrow();
    expect(takeReturnTo()).toBeNull();
    expect(setItem).toHaveBeenCalled();
    expect(getItem).toHaveBeenCalled();
  });

  test("takeReturnTo survives a removeItem that throws", () => {
    rememberReturnTo("/account/security");
    vi.spyOn(Storage.prototype, "removeItem").mockImplementation(() => {
      throw new DOMException("The operation is insecure.", "SecurityError");
    });

    expect(() => takeReturnTo()).not.toThrow();
  });
});

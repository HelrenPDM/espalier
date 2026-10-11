import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, expect } from "vitest";
import type { AxeMatchers } from "vitest-axe/matchers";
import * as axeMatchers from "vitest-axe/matchers";
// The component tests render with the i18n instance of the SPA.
import "../i18n";

// vitest-axe 0.1.0 declares its matcher types for the `Vi` namespace of
// Vitest before 0.31. Current Vitest reads custom matcher types from
// `Matchers`, whose type parameters this declaration repeats.
declare module "vitest" {
  interface Matchers<
    R extends void | Promise<void> = void | Promise<void>,
    T = unknown,
  > extends AxeMatchers {}
}

expect.extend(axeMatchers);

// Testing Library unmounts after each test by itself only when Vitest runs
// with `globals: true`.
afterEach(() => {
  cleanup();
});

// jsdom has no fetch API, so the tests run with the Request class of Node,
// which rejects a relative URL. A browser resolves it against the document
// URL, as this subclass does, so the API client keeps its base URL "".
class DocumentRequest extends Request {
  constructor(input: RequestInfo | URL, init?: RequestInit) {
    super(
      typeof input === "string" ? new URL(input, window.location.href) : input,
      init,
    );
  }
}
globalThis.Request = DocumentRequest;

// jsdom has no ResizeObserver, which Headless UI calls when a menu opens.
class ResizeObserverStub implements ResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
}
globalThis.ResizeObserver ??= ResizeObserverStub;

// Node's BroadcastChannel dispatches Node's MessageEvent, which fails the
// `instanceof MessageEvent` check of listenMessages under jsdom. This
// channel delivers jsdom MessageEvents, as a browser does: asynchronously,
// to every other open channel of the same name, with a structured clone of
// the message.
class DocumentBroadcastChannel extends EventTarget {
  static #open = new Map<string, Set<DocumentBroadcastChannel>>();
  readonly name: string;
  #closed = false;

  constructor(name: string) {
    super();
    this.name = String(name);
    const peers = DocumentBroadcastChannel.#open.get(this.name) ?? new Set();
    peers.add(this);
    DocumentBroadcastChannel.#open.set(this.name, peers);
  }

  postMessage(message: unknown) {
    if (this.#closed)
      throw new DOMException("Channel closed", "InvalidStateError");
    const peers = DocumentBroadcastChannel.#open.get(this.name) ?? new Set();
    for (const peer of peers) {
      if (peer === this) continue;
      const data = structuredClone(message);
      setTimeout(() => {
        if (!peer.#closed)
          peer.dispatchEvent(
            new MessageEvent("message", { data, origin: location.origin }),
          );
      }, 0);
    }
  }

  close() {
    this.#closed = true;
    DocumentBroadcastChannel.#open.get(this.name)?.delete(this);
  }
}
globalThis.BroadcastChannel =
  DocumentBroadcastChannel as unknown as typeof BroadcastChannel;

import { afterEach, expect, test, vi } from "vitest";
import { listenMessages } from "./messages";

type Ping = { kind: "ping" };

const parsePing = (data: unknown): Ping | null =>
  typeof data === "object" &&
  data !== null &&
  "kind" in data &&
  data.kind === "ping"
    ? { kind: "ping" }
    : null;

const post = (data: unknown, origin: string) =>
  window.dispatchEvent(new MessageEvent("message", { data, origin }));

let stop: () => void = () => {};

afterEach(() => stop());

test("a valid message from the own origin reaches the handler once", () => {
  const handler = vi.fn();
  stop = listenMessages(window, parsePing, handler);

  post({ kind: "ping" }, window.location.origin);

  expect(handler).toHaveBeenCalledTimes(1);
  expect(handler).toHaveBeenCalledWith({ kind: "ping" });
});

test("a message from another origin never reaches the handler", () => {
  const handler = vi.fn();
  stop = listenMessages(window, parsePing, handler);

  post({ kind: "ping" }, "https://evil.example");

  expect(handler).not.toHaveBeenCalled();
});

test("a same-origin message that the parser rejects never reaches the handler", () => {
  const handler = vi.fn();
  stop = listenMessages(window, parsePing, handler);

  post({ kind: "pong" }, window.location.origin);
  post("ping", window.location.origin);

  expect(handler).not.toHaveBeenCalled();
});

test("no message reaches the handler after the returned function has run", () => {
  const handler = vi.fn();
  listenMessages(window, parsePing, handler)();

  post({ kind: "ping" }, window.location.origin);

  expect(handler).not.toHaveBeenCalled();
});

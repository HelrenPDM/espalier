import { afterEach, expect, test, vi } from "vitest";
import { requestStepUp, setStepUpHandler } from "./stepUp";

afterEach(() => {
  setStepUpHandler(null);
});

/** A handler whose promise the test settles. */
function deferredHandler() {
  let resolve: (success: boolean) => void = () => {};
  const handler = vi.fn(
    () =>
      new Promise<boolean>((settle) => {
        resolve = settle;
      }),
  );
  return { handler, resolve: (success: boolean) => resolve(success) };
}

test("without a handler requestStepUp resolves false", async () => {
  await expect(requestStepUp()).resolves.toBe(false);
});

test("concurrent calls share one promise and call the handler once", async () => {
  const { handler, resolve } = deferredHandler();
  setStepUpHandler(handler);

  const first = requestStepUp();
  const second = requestStepUp();

  expect(second).toBe(first);
  expect(handler).toHaveBeenCalledTimes(1);
  resolve(true);
  await expect(first).resolves.toBe(true);
  await expect(second).resolves.toBe(true);
});

test("a call after the settled promise asks the handler again", async () => {
  const handler = vi.fn(async () => true);
  setStepUpHandler(handler);

  await expect(requestStepUp()).resolves.toBe(true);
  await expect(requestStepUp()).resolves.toBe(true);

  expect(handler).toHaveBeenCalledTimes(2);
});

test("a rejecting handler resolves false and releases the pending promise", async () => {
  const handler = vi
    .fn<() => Promise<boolean>>()
    .mockRejectedValueOnce(new Error("dialog failed"))
    .mockResolvedValueOnce(true);
  setStepUpHandler(handler);

  await expect(requestStepUp()).resolves.toBe(false);
  await expect(requestStepUp()).resolves.toBe(true);
  expect(handler).toHaveBeenCalledTimes(2);
});

test("the remover of setStepUpHandler removes only its own handler", async () => {
  const first = vi.fn(async () => false);
  const second = vi.fn(async () => true);
  const removeFirst = setStepUpHandler(first);
  const removeSecond = setStepUpHandler(second);

  removeFirst();
  await expect(requestStepUp()).resolves.toBe(true);
  expect(second).toHaveBeenCalledTimes(1);
  expect(first).not.toHaveBeenCalled();

  removeSecond();
  await expect(requestStepUp()).resolves.toBe(false);
  expect(second).toHaveBeenCalledTimes(1);
});

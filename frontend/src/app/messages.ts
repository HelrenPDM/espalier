/**
 * Registers a `message` listener that drops every message it cannot trust
 * (ASVS 3.5.5). Every `message` listener of the SPA goes through this
 * function.
 *
 * For a `Window` target it drops every event whose `origin` differs from
 * `window.location.origin`. A `BroadcastChannel` delivers messages from the
 * same origin only (HTML Living Standard, "Broadcasting to other browsing
 * contexts"). For every target it drops the event when `parse` returns `null`
 * or throws, and otherwise calls `handler` with the parsed value. The
 * returned function removes the listener.
 */
export function listenMessages<T>(
  target: Window | BroadcastChannel,
  parse: (data: unknown) => T | null,
  handler: (message: T) => void,
): () => void {
  // Everything that is no BroadcastChannel counts as a window, so the origin
  // check also applies to a window of another realm.
  const checkOrigin = !(
    typeof BroadcastChannel === "function" && target instanceof BroadcastChannel
  );

  const listener = (event: Event) => {
    if (!(event instanceof MessageEvent)) return;
    if (checkOrigin && event.origin !== window.location.origin) return;
    let message: T | null;
    try {
      message = parse(event.data);
    } catch {
      return;
    }
    if (message === null) return;
    handler(message);
  };

  const eventTarget: EventTarget = target;
  eventTarget.addEventListener("message", listener);
  return () => eventTarget.removeEventListener("message", listener);
}

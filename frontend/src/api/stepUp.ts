/**
 * The bridge between the API client and the step-up dialog (task 0011,
 * step 13). The client calls `requestStepUp()` after a 403 with
 * `RECENT_AUTH_ERROR_CODE`; `StepUpProvider` registers the handler that
 * opens the dialog and resolves `true` after a successful step-up.
 */
type StepUpHandler = () => Promise<boolean>;

let handler: StepUpHandler | null = null;
let pending: Promise<boolean> | null = null;

/**
 * Registers `next` as the handler and returns a function that removes it
 * again, unless another handler replaced it in the meantime.
 */
export function setStepUpHandler(next: StepUpHandler | null): () => void {
  handler = next;
  return () => {
    if (handler === next) handler = null;
  };
}

/**
 * Asks for a step-up. Concurrent calls share one pending promise, so
 * parallel requests open one dialog. Without a handler it resolves `false`.
 */
export function requestStepUp(): Promise<boolean> {
  if (pending) return pending;
  if (handler === null) return Promise.resolve(false);
  const current = handler()
    .catch(() => false)
    .finally(() => {
      pending = null;
    });
  pending = current;
  return current;
}

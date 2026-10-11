import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { useQueryClient } from "@tanstack/react-query";
import { securityQueryOptions } from "../api/account";
import { useApiClient } from "../api/apiClientContext";
import { setStepUpHandler } from "../api/stepUp";
import { StepUpDialog } from "./StepUpDialog";

/**
 * Registers the step-up handler of the API client (task 0011 step 13).
 * Mounted once inside the providers of the app; the handler opens
 * `StepUpDialog` and resolves with its outcome. The admin area of 0015
 * reuses it through the API client.
 */
export function StepUpProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const client = useApiClient();
  const [open, setOpen] = useState(false);
  const resolver = useRef<((success: boolean) => void) | null>(null);

  // The dialog offers the methods of the security summary. Loading it
  // before the dialog opens lets the focus trap find the first method.
  useEffect(
    () =>
      setStepUpHandler(async () => {
        await queryClient
          .ensureQueryData(securityQueryOptions(client))
          .catch(() => undefined);
        return new Promise<boolean>((resolve) => {
          resolver.current = resolve;
          setOpen(true);
        });
      }),
    [client, queryClient],
  );

  // A pending request never stays open when the provider unmounts.
  useEffect(
    () => () => {
      resolver.current?.(false);
      resolver.current = null;
    },
    [],
  );

  const done = useCallback((success: boolean) => {
    setOpen(false);
    const resolve = resolver.current;
    resolver.current = null;
    resolve?.(success);
  }, []);

  return (
    <>
      {children}
      <StepUpDialog open={open} onDone={done} />
    </>
  );
}

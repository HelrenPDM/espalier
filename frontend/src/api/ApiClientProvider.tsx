import type { ReactNode } from "react";
import type { ApiClient } from "./client";
import { ApiClientContext } from "./apiClientContext";

/** Provides `client` to the query hooks and the pages below it. */
export function ApiClientProvider({
  client,
  children,
}: {
  client: ApiClient;
  children: ReactNode;
}) {
  return (
    <ApiClientContext.Provider value={client}>
      {children}
    </ApiClientContext.Provider>
  );
}

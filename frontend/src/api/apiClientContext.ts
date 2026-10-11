import { createContext, useContext } from "react";
import { api, type ApiClient } from "./client";

/**
 * The API client of the component tree. The default is the client of the
 * SPA; component tests provide one built with `createApiClient` and a stub
 * fetch (`ApiClientProvider`).
 */
export const ApiClientContext = createContext<ApiClient>(api);

export function useApiClient(): ApiClient {
  return useContext(ApiClientContext);
}

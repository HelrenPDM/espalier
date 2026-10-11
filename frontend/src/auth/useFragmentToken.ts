import { useEffect, useRef, useState } from "react";
import { takeFragmentParam } from "./fragment";

/**
 * Reads `#token=` once into a ref and removes the fragment (README section
 * 6.4). StrictMode runs the effect twice in development, and a second read
 * would find no fragment and overwrite the token, so the ref keeps the
 * first value. `undefined` until the effect has run.
 */
export function useFragmentToken(): string | null | undefined {
  const tokenRef = useRef<string | null | undefined>(undefined);
  const [token, setToken] = useState<string | null | undefined>(undefined);
  useEffect(() => {
    if (tokenRef.current === undefined)
      tokenRef.current = takeFragmentParam("token");
    setToken(tokenRef.current === "" ? null : tokenRef.current);
  }, []);
  return token;
}

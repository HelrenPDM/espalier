/**
 * Reads the parameter `name` of the URL fragment and removes the fragment
 * from the address bar and the history entry. E-mail tokens and the OIDC
 * ticket travel in the fragment, which never reaches a server and no
 * `Referer` header (README section 6.4, ASVS 14.2.1).
 */
export function takeFragmentParam(name: string): string | null {
  const value = new URLSearchParams(window.location.hash.slice(1)).get(name);
  history.replaceState(
    history.state,
    "",
    window.location.pathname + window.location.search,
  );
  return value;
}

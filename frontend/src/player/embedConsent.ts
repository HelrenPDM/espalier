import { createContext, useContext, useSyncExternalStore } from "react";

/**
 * When the player of a streaming service loads (`MEDIA_EMBED_CONSENT`,
 * task 0018): `click` after the learner agrees for its host, `auto` with
 * the page.
 */
export type EmbedConsent = "click" | "auto";

/**
 * The consent setting of the embeds below. Its default `click` holds where
 * nobody provides one: the SCORM package has no setting, so an embed there
 * always asks first. The learner pages provide
 * `session.flags.mediaEmbedConsent` and the admin preview
 * `media_policy.embed_consent` of the import, so the player itself reads
 * nothing from `src/api/`.
 */
export const EmbedConsentContext = createContext<EmbedConsent>("click");

export function useEmbedConsent(): EmbedConsent {
  return useContext(EmbedConsentContext);
}

// The hosts that the learner agreed to, for the life of the page. Nothing
// is stored, so a new page asks again. A sign-out and a sign-in end the
// agreements as well (`forgetEmbedConsent`), because the next person in
// the same tab has agreed to nothing.
const agreedHosts = new Set<string>();
const listeners = new Set<() => void>();

const hostKey = (host: string) => host.toLowerCase();

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/**
 * Records that the learner agreed to load embeds from `host` (`host` or
 * `host:port`). Every embed of that host on the page then loads, also one
 * that renders later.
 */
export function agreeToEmbed(host: string): void {
  const key = hostKey(host);
  if (agreedHosts.has(key)) return;
  agreedHosts.add(key);
  for (const listener of listeners) listener();
}

/** True once the learner agreed to load embeds from `host` on this page. */
export function useEmbedAgreed(host: string): boolean {
  const key = hostKey(host);
  return useSyncExternalStore(
    subscribe,
    () => agreedHosts.has(key),
    () => false,
  );
}

/**
 * Forgets every agreement, as a new page does, and lets every embed on the
 * page ask again. `src/auth/sessionEvents.ts` calls it on a sign-out and a
 * sign-in, in this tab and in another one.
 */
export function forgetEmbedConsent(): void {
  agreedHosts.clear();
  for (const listener of listeners) listener();
}

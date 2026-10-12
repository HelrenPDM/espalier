import type { Role } from "../api/session";

/** The key of a section of the admin area (task 0015, step 5). */
export type AdminSectionKey =
  | "packs"
  | "users"
  | "policies"
  | "approvedTools"
  | "roles"
  | "apiClients"
  | "webhooks"
  | "audit"
  | "attendance"
  | "insights"
  | "registrar";

export interface AdminSection {
  key: AdminSectionKey;
  /** The path below `/admin`. */
  path: string;
  /** The role that sees the section; the server checks it again. */
  role: Role;
}

/**
 * The sections of the admin area in the order of the navigation: author
 * (packs; 0016 adds exports), admin, facilitator, analyst (0014) and
 * registrar. Each section appears only for its role (ASVS 8.3.1: the
 * navigation is convenience; the router pipelines decide).
 */
export const ADMIN_SECTIONS: readonly AdminSection[] = [
  { key: "packs", path: "packs", role: "author" },
  { key: "users", path: "users", role: "admin" },
  { key: "policies", path: "policies", role: "admin" },
  { key: "approvedTools", path: "approved-tools", role: "admin" },
  { key: "roles", path: "roles", role: "admin" },
  { key: "apiClients", path: "api-clients", role: "admin" },
  { key: "webhooks", path: "webhooks", role: "admin" },
  { key: "audit", path: "audit", role: "admin" },
  { key: "attendance", path: "attendance", role: "facilitator" },
  { key: "insights", path: "insights", role: "analyst" },
  { key: "registrar", path: "registrar", role: "registrar" },
];

/** The sections that `roles` see. */
export function sectionsFor(roles: readonly Role[]): AdminSection[] {
  return ADMIN_SECTIONS.filter((section) => roles.includes(section.role));
}

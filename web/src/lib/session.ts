// Where a token becomes a user. auth.ts stays database-free so it can run in
// the proxy; this file is the half that queries, so only pages, actions and
// API routes may import it.

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { SESSION_COOKIE, readToken } from "@/lib/auth";
import { getUser, type UserRow } from "@/lib/db";

/** The signed-in browser user, or null when the cookie is missing or stale. */
export async function currentUser(): Promise<UserRow | null> {
  const store = await cookies();
  const token = await readToken(store.get(SESSION_COOKIE)?.value, Date.now());
  if (token?.audience !== "web") return null;
  return getUser(token.userId);
}

/** The app user behind an `Authorization: Bearer` header, or null. */
export async function apiUser(request: Request): Promise<UserRow | null> {
  const header = request.headers.get("authorization");
  const prefix = "Bearer ";
  if (!header?.startsWith(prefix)) return null;

  const token = await readToken(header.slice(prefix.length).trim(), Date.now());
  if (token?.audience !== "app") return null;
  return getUser(token.userId);
}

/**
 * Server actions are reachable by anyone who can post to them, so each one
 * asks again rather than trusting that a page checked. A member lands on the
 * library, which tells them the editor is not for their account.
 */
export async function requireAdmin(): Promise<UserRow> {
  const user = await currentUser();
  if (!user || user.role !== "admin") redirect("/");
  return user;
}

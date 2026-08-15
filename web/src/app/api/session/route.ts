import { jsonError } from "@/lib/api";
import {
  DUMMY_PASSWORD_HASH,
  createToken,
  verifyPassword,
} from "@/lib/auth";
import { findUserByUsername } from "@/lib/db";

export const dynamic = "force-dynamic";

/**
 * Where the app trades a username and a password for the token it sends on
 * every other call — so this is the one route under /api that carries no
 * Authorization header of its own. An unknown username costs the same
 * derivation as a wrong password and gets the same answer.
 */
export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonError(400, "Body is not valid JSON.");
  }

  const username = (body as { username?: unknown })?.username;
  const password = (body as { password?: unknown })?.password;
  if (typeof username !== "string" || typeof password !== "string") {
    return jsonError(400, "Body must contain 'username' and 'password'.");
  }

  const user = await findUserByUsername(username.trim());
  const correct = await verifyPassword(
    password,
    user?.password_hash ?? DUMMY_PASSWORD_HASH,
  );
  if (!user || !correct) return jsonError(401, "Wrong username or password.");

  return Response.json({
    token: await createToken("app", user.id, Date.now()),
  });
}

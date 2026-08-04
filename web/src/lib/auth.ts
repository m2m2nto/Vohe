// Single-password auth for a personal tool. The cookie carries an issue
// timestamp plus an HMAC of it, so it can expire and cannot be forged without
// AUTH_SECRET. Web Crypto only, so this also runs in middleware.

export const SESSION_COOKIE = "vohe_session";
export const SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 30; // 30 days

function secret(): string {
  const value = process.env.AUTH_SECRET;
  if (!value) throw new Error("AUTH_SECRET is not set.");
  return value;
}

async function sign(message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret()),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function createSessionCookie(issuedAtMs: number): Promise<string> {
  const issuedAt = String(issuedAtMs);
  return `${issuedAt}.${await sign(issuedAt)}`;
}

export async function isValidSessionCookie(
  value: string | undefined,
  nowMs: number,
): Promise<boolean> {
  if (!value) return false;
  const dot = value.indexOf(".");
  if (dot === -1) return false;
  const issuedAt = value.slice(0, dot);
  const mac = value.slice(dot + 1);
  if (!/^\d+$/.test(issuedAt)) return false;
  if (!constantTimeEqual(mac, await sign(issuedAt))) return false;
  const ageSeconds = (nowMs - Number(issuedAt)) / 1000;
  return ageSeconds >= 0 && ageSeconds < SESSION_MAX_AGE_SECONDS;
}

export function isCorrectPassword(input: string): boolean {
  const expected = process.env.ADMIN_PASSWORD;
  if (!expected) throw new Error("ADMIN_PASSWORD is not set.");
  return constantTimeEqual(input, expected);
}

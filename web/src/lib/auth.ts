// Signing and password hashing, and nothing that needs a database: a token
// carries its audience, its user id and an HMAC of both, so it can expire and
// cannot be forged without AUTH_SECRET. Web Crypto only, so this also runs in
// middleware. Turning a token into an account is src/lib/session.ts.

export const SESSION_COOKIE = "vohe_session";

/** Which surface a token was minted for. */
export type Audience = "web" | "app";

/**
 * The browser expires as it always has. The app lasts a year, because
 * re-typing a password on a phone is the friction accounts exist to remove.
 */
export const TOKEN_MAX_AGE_SECONDS: Record<Audience, number> = {
  web: 60 * 60 * 24 * 30, // 30 days
  app: 60 * 60 * 24 * 365, // a year
};

/**
 * A real hash of a password nobody has, so a sign-in with an unknown username
 * can still spend one derivation and take as long as a wrong password does.
 */
export const DUMMY_PASSWORD_HASH =
  "pbkdf2$sha256$600000$8edb7aebc182cee79b40bdbcfe72381e$4432b9238582f4c9599b83c8f9c803e7840f70caa9c72cf0c681ca0cf9da3b32";

const PBKDF2_ITERATIONS = 600_000;

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function fromHex(hex: string): Uint8Array<ArrayBuffer> | null {
  if (hex.length === 0 || hex.length % 2 !== 0 || !/^[0-9a-f]+$/.test(hex)) {
    return null;
  }
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

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
  return toHex(new Uint8Array(mac));
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function derive(
  plain: string,
  salt: Uint8Array<ArrayBuffer>,
  iterations: number,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(plain),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations },
    key,
    256,
  );
  return toHex(new Uint8Array(bits));
}

/**
 * `pbkdf2$sha256$<iterations>$<salt>$<hash>`. The parameters travel with the
 * hash, so raising them later only changes what new passwords are stored as.
 * Derivation costs a few hundred milliseconds — it runs on sign-in only.
 */
export async function hashPassword(plain: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await derive(plain, salt, PBKDF2_ITERATIONS);
  return `pbkdf2$sha256$${PBKDF2_ITERATIONS}$${toHex(salt)}$${hash}`;
}

/** False, never a throw, for anything that is not a hash this function wrote. */
export async function verifyPassword(
  plain: string,
  stored: string,
): Promise<boolean> {
  const parts = stored.split("$");
  if (parts.length !== 5) return false;
  const [scheme, hash, iterations, saltHex, expected] = parts;
  if (scheme !== "pbkdf2" || hash !== "sha256") return false;
  if (!/^[1-9]\d*$/.test(iterations)) return false;
  const salt = fromHex(saltHex);
  if (!salt || !expected) return false;
  return constantTimeEqual(
    await derive(plain, salt, Number(iterations)),
    expected,
  );
}

/**
 * Lower case, no look-alikes: l, o, 0 and 1 are all absent, so a password read
 * aloud or copied off a screen cannot be mistyped into a character that isn't
 * in it. Exactly 32 long, so masking five random bits picks one without bias —
 * a modulo over any other length would favour the first few characters.
 */
const PASSWORD_ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789";

/**
 * A temporary password for an account an admin has just created or reset.
 * Sixty bits of `crypto.getRandomValues`, grouped in fours because it is meant
 * to be passed to a person rather than pasted.
 */
export function generatePassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  const chars = Array.from(bytes, (b) => PASSWORD_ALPHABET[b & 31]);
  return [
    chars.slice(0, 4).join(""),
    chars.slice(4, 8).join(""),
    chars.slice(8, 12).join(""),
  ].join("-");
}

/**
 * `<audience>.<userId>.<issuedAt>.<mac>`. The audience gives the two surfaces
 * different lifetimes and stops a year-long app token being replayed as a
 * browser session.
 */
export async function createToken(
  audience: Audience,
  userId: number,
  issuedAtMs: number,
): Promise<string> {
  const body = `${audience}.${userId}.${issuedAtMs}`;
  return `${body}.${await sign(body)}`;
}

/** The user a token names, or null if it is forged, expired or nonsense. */
export async function readToken(
  value: string | undefined,
  nowMs: number,
): Promise<{ audience: Audience; userId: number } | null> {
  if (!value) return null;
  const parts = value.split(".");
  if (parts.length !== 4) return null;
  const [audience, userId, issuedAt, mac] = parts;
  if (audience !== "web" && audience !== "app") return null;
  if (!/^\d+$/.test(userId) || !/^\d+$/.test(issuedAt)) return null;

  const body = `${audience}.${userId}.${issuedAt}`;
  if (!constantTimeEqual(mac, await sign(body))) return null;

  const ageSeconds = (nowMs - Number(issuedAt)) / 1000;
  if (ageSeconds < 0 || ageSeconds >= TOKEN_MAX_AGE_SECONDS[audience]) {
    return null;
  }
  return { audience, userId: Number(userId) };
}


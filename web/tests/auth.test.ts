// Run with: npm test
import { test } from "node:test";
import assert from "node:assert/strict";

process.env.AUTH_SECRET = "test-secret";

const {
  createToken,
  readToken,
  generatePassword,
  hashPassword,
  verifyPassword,
  DUMMY_PASSWORD_HASH,
  TOKEN_MAX_AGE_SECONDS,
} = await import("../src/lib/auth.ts");

const now = 1_700_000_000_000;

test("a hashed password verifies against itself and nothing else", async () => {
  const started = performance.now();
  const stored = await hashPassword("correct horse");
  console.log(`hashPassword: ${Math.round(performance.now() - started)}ms`);

  assert.match(stored, /^pbkdf2\$sha256\$600000\$[0-9a-f]{32}\$[0-9a-f]{64}$/);
  assert.equal(await verifyPassword("correct horse", stored), true);
  assert.equal(await verifyPassword("correct hors", stored), false);
  assert.equal(await verifyPassword("", stored), false);
});

test("the same password hashes differently every time", async () => {
  const first = await hashPassword("correct horse");
  const second = await hashPassword("correct horse");
  assert.notEqual(first, second);
  assert.equal(await verifyPassword("correct horse", first), true);
  assert.equal(await verifyPassword("correct horse", second), true);
});

test("a stored hash that is not one of ours is false, not a throw", async () => {
  for (const stored of [
    "",
    "correct horse",
    "pbkdf2$sha256$600000$nosalt$nohash",
    "pbkdf2$sha256$0$00$00",
    "pbkdf2$sha256$abc$00112233445566778899aabbccddeeff$00",
    "pbkdf2$sha512$600000$00112233445566778899aabbccddeeff$00",
    "scrypt$sha256$600000$00112233445566778899aabbccddeeff$00",
    "pbkdf2$sha256$600000$00112233445566778899aabbccddeeff",
  ]) {
    assert.equal(await verifyPassword("correct horse", stored), false, stored);
  }
});

test("the dummy hash is a real one, so a missing user still costs a derivation", async () => {
  assert.match(
    DUMMY_PASSWORD_HASH,
    /^pbkdf2\$sha256\$600000\$[0-9a-f]{32}\$[0-9a-f]{64}$/,
  );
  assert.equal(await verifyPassword("", DUMMY_PASSWORD_HASH), false);
  assert.equal(await verifyPassword("password", DUMMY_PASSWORD_HASH), false);
});

test("a hash stored with a cheaper cost still verifies", async () => {
  // What a hash written before the iteration count was raised looks like.
  const salt = new Uint8Array(16).fill(7);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode("correct horse"),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations: 1000 },
    key,
    256,
  );
  const hex = (bytes: Uint8Array) =>
    Array.from(bytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
  const stored = `pbkdf2$sha256$1000$${hex(salt)}$${hex(new Uint8Array(bits))}`;

  assert.equal(await verifyPassword("correct horse", stored), true);
  assert.equal(await verifyPassword("wrong horse", stored), false);
});

test("a generated password is readable, unguessable and fresh each time", async () => {
  const seen = new Set<string>();
  for (let i = 0; i < 500; i++) {
    const password = generatePassword();
    assert.match(
      password,
      /^[abcdefghijkmnpqrstuvwxyz23456789]{4}-[abcdefghijkmnpqrstuvwxyz23456789]{4}-[abcdefghijkmnpqrstuvwxyz23456789]{4}$/,
      password,
    );
    // The look-alikes have to stay out: someone reads this one aloud.
    assert.equal(/[lo01]/.test(password), false, password);
    seen.add(password);
  }
  assert.equal(seen.size, 500, "every password should differ");
});

test("a generated password is one a hash round-trips", async () => {
  const password = generatePassword();
  const stored = await hashPassword(password);
  assert.equal(await verifyPassword(password, stored), true);
  assert.equal(await verifyPassword(generatePassword(), stored), false);
});

test("the generator reaches its whole alphabet", () => {
  // Guards the masking: a modulo over a 31-character alphabet would still
  // produce every character, but `& 31` over a shorter one yields undefined.
  const alphabet = "abcdefghijkmnpqrstuvwxyz23456789";
  const seen = new Set(
    Array.from({ length: 400 }, () => generatePassword().replaceAll("-", ""))
      .join("")
      .split(""),
  );
  assert.equal(seen.size, alphabet.length);
  for (const c of alphabet) assert.ok(seen.has(c), `never produced ${c}`);
});

test("a token names its user and its surface", async () => {
  for (const audience of ["web", "app"] as const) {
    const token = await createToken(audience, 42, now);
    assert.deepEqual(await readToken(token, now), { audience, userId: 42 });
    assert.deepEqual(await readToken(token, now + 60_000), {
      audience,
      userId: 42,
    });
  }
});

test("the two surfaces cannot borrow each other's tokens", async () => {
  const web = await readToken(await createToken("web", 1, now), now);
  const app = await readToken(await createToken("app", 1, now), now);
  assert.equal(web?.audience, "web");
  assert.equal(app?.audience, "app");
});

test("a tampered token is rejected", async () => {
  const token = await createToken("web", 42, now);
  const [, , , mac] = token.split(".");

  assert.equal(await readToken(`app.42.${now}.${mac}`, now), null);
  assert.equal(await readToken(`web.43.${now}.${mac}`, now), null);
  assert.equal(await readToken(`web.42.${now + 1}.${mac}`, now), null);
  assert.equal(await readToken(`web.42.${now}.deadbeef`, now), null);
  assert.equal(await readToken(token.replace(/.$/, "0"), now), null);
});

test("garbage is rejected", async () => {
  for (const value of [
    undefined,
    "",
    "nonsense",
    `${now}.deadbeef`, // the shape of the old single-password cookie
    "web.42.notanumber.abc",
    "web.notanumber.1.abc",
    "editor.42.1.abc",
    `web.42.${now}`,
    `web.42.${now}.abc.abc`,
  ]) {
    assert.equal(await readToken(value, now), null, String(value));
  }
});

test("a token signed with another secret is rejected", async () => {
  const token = await createToken("app", 42, now);
  process.env.AUTH_SECRET = "different-secret";
  assert.equal(await readToken(token, now), null);
  process.env.AUTH_SECRET = "test-secret";
});

test("each surface expires on its own clock", async () => {
  for (const audience of ["web", "app"] as const) {
    const token = await createToken(audience, 42, now);
    const maxAgeMs = TOKEN_MAX_AGE_SECONDS[audience] * 1000;
    assert.notEqual(await readToken(token, now + maxAgeMs - 1), null);
    assert.equal(await readToken(token, now + maxAgeMs), null);
    assert.equal(await readToken(token, now - 1), null); // issued in the future
  }
  assert.ok(TOKEN_MAX_AGE_SECONDS.app > TOKEN_MAX_AGE_SECONDS.web);
});

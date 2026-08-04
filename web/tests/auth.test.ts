// Run with: npm test
import { test } from "node:test";
import assert from "node:assert/strict";

process.env.AUTH_SECRET = "test-secret";
process.env.ADMIN_PASSWORD = "correct horse";

const {
  createSessionCookie,
  isValidSessionCookie,
  isCorrectPassword,
  SESSION_MAX_AGE_SECONDS,
} = await import("../src/lib/auth.ts");

const now = 1_700_000_000_000;

test("a freshly issued cookie is accepted", async () => {
  const cookie = await createSessionCookie(now);
  assert.equal(await isValidSessionCookie(cookie, now), true);
  assert.equal(await isValidSessionCookie(cookie, now + 60_000), true);
});

test("missing, malformed, or tampered cookies are rejected", async () => {
  const cookie = await createSessionCookie(now);
  assert.equal(await isValidSessionCookie(undefined, now), false);
  assert.equal(await isValidSessionCookie("", now), false);
  assert.equal(await isValidSessionCookie("nonsense", now), false);
  assert.equal(await isValidSessionCookie(`${now}.deadbeef`, now), false);
  // same signature, later claimed issue time
  assert.equal(
    await isValidSessionCookie(`${now + 1}.${cookie.split(".")[1]}`, now),
    false,
  );
});

test("a cookie signed with another secret is rejected", async () => {
  const cookie = await createSessionCookie(now);
  process.env.AUTH_SECRET = "different-secret";
  assert.equal(await isValidSessionCookie(cookie, now), false);
  process.env.AUTH_SECRET = "test-secret";
});

test("cookies expire", async () => {
  const cookie = await createSessionCookie(now);
  const maxAgeMs = SESSION_MAX_AGE_SECONDS * 1000;
  assert.equal(await isValidSessionCookie(cookie, now + maxAgeMs - 1), true);
  assert.equal(await isValidSessionCookie(cookie, now + maxAgeMs), false);
  assert.equal(await isValidSessionCookie(cookie, now - 1), false);
});

test("password comparison", () => {
  assert.equal(isCorrectPassword("correct horse"), true);
  assert.equal(isCorrectPassword("correct hors"), false);
  assert.equal(isCorrectPassword(""), false);
});

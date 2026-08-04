// Run with: npm test
import { test } from "node:test";
import assert from "node:assert/strict";

process.env.AUTH_SECRET = "test-secret";
process.env.ADMIN_PASSWORD = "correct horse";
process.env.API_TOKEN = "token-abc";

const { isValidApiToken } = await import("../src/lib/auth.ts");
const { parseSubmissionsBody, MAX_SUBMISSION_ENTRIES } = await import(
  "../src/lib/api.ts"
);

test("only the exact bearer token is accepted", () => {
  assert.equal(isValidApiToken("Bearer token-abc"), true);
  assert.equal(isValidApiToken("Bearer token-abc "), true); // trailing space trimmed
  assert.equal(isValidApiToken("Bearer token-ab"), false);
  assert.equal(isValidApiToken("Bearer TOKEN-ABC"), false);
  assert.equal(isValidApiToken("token-abc"), false); // no scheme
  assert.equal(isValidApiToken("Basic token-abc"), false);
  assert.equal(isValidApiToken(""), false);
  assert.equal(isValidApiToken(null), false);
});

test("the API stays closed when no token is configured", () => {
  delete process.env.API_TOKEN;
  assert.equal(isValidApiToken("Bearer token-abc"), false);
  assert.equal(isValidApiToken("Bearer "), false);
  process.env.API_TOKEN = "token-abc";
});

test("submissions are trimmed, de-duplicated, and kept in order", () => {
  const parsed = parseSubmissionsBody({
    entries: [
      { word: "  pas ", translation: " cane " },
      { word: "pas", translation: "cane" },
      { word: "mačka", translation: "gatto" },
    ],
  });
  assert.ok(!("error" in parsed));
  assert.deepEqual(parsed.entries, [
    { word: "pas", translation: "cane" },
    { word: "mačka", translation: "gatto" },
  ]);
  assert.deepEqual(parsed.invalid, []);
});

test("an entry the app's parser could not read back is reported, not imported", () => {
  const parsed = parseSubmissionsBody({
    entries: [
      { word: "well-being", translation: "benessere" },
      { word: "", translation: "niente" },
      { word: "#pas", translation: "cane" },
      { word: "pas", translation: "" },
      { word: "gatto", translation: "mačka" },
    ],
  });
  assert.ok(!("error" in parsed));
  assert.deepEqual(parsed.entries, [{ word: "gatto", translation: "mačka" }]);
  assert.deepEqual(
    parsed.invalid.map((i) => i.word),
    ["well-being", "", "#pas", "pas"],
  );
  assert.match(parsed.invalid[0].reason, /hyphen/);
});

test("a malformed body is rejected as a whole", () => {
  const errorOf = (body: unknown) => {
    const parsed = parseSubmissionsBody(body);
    return "error" in parsed ? parsed.error : null;
  };
  assert.match(errorOf(null) ?? "", /JSON object/);
  assert.match(errorOf("entries") ?? "", /JSON object/);
  assert.match(errorOf({}) ?? "", /'entries' array/);
  assert.match(errorOf({ entries: {} }) ?? "", /'entries' array/);
  assert.match(errorOf({ entries: [] }) ?? "", /empty/);
  assert.match(
    errorOf({
      entries: Array.from({ length: MAX_SUBMISSION_ENTRIES + 1 }, () => ({
        word: "a",
        translation: "b",
      })),
    }) ?? "",
    /At most/,
  );
});

test("non-string fields are treated as missing, not crashes", () => {
  const parsed = parseSubmissionsBody({
    entries: [{ word: 42, translation: null }, "nonsense", null],
  });
  assert.ok(!("error" in parsed));
  assert.equal(parsed.entries.length, 0);
  assert.equal(parsed.invalid.length, 3);
});

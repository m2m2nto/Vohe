// Run with: npm test
import { test } from "node:test";
import assert from "node:assert/strict";

const { parseSubmissionsBody, MAX_SUBMISSION_ENTRIES } = await import(
  "../src/lib/api.ts"
);

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
      { word: "cane - gatto", translation: "pas" },
      { word: "", translation: "niente" },
      { word: "#pas", translation: "cane" },
      { word: "pas", translation: "" },
      { word: "well-being", translation: "benessere" },
      { word: "gatto", translation: "mačka" },
    ],
  });
  assert.ok(!("error" in parsed));
  assert.deepEqual(parsed.entries, [
    { word: "well-being", translation: "benessere" },
    { word: "gatto", translation: "mačka" },
  ]);
  assert.deepEqual(
    parsed.invalid.map((i) => i.word),
    ["cane - gatto", "", "#pas", "pas"],
  );
  assert.match(parsed.invalid[0].reason, / - /);
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

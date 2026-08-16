// Run with: npm test
import { test } from "node:test";
import assert from "node:assert/strict";
import { planProposals } from "../src/lib/proposals.ts";
import type { EntryRow } from "../src/lib/db.ts";

const HEADER = "Croatian-Italian";

/** Rows as `listEntries` returns them: export order, position ascending. */
function rows(...pairs: [string, string][]): EntryRow[] {
  return pairs.map(([word, translation], i) => ({
    id: i + 1,
    word,
    translation,
    position: i,
  }));
}

test("a word the dictionary does not carry is queued", () => {
  const plan = planProposals("pas - cane", HEADER, rows(["mačka", "gatto"]));
  assert.deepEqual(plan.queued, [{ word: "pas", translation: "cane" }]);
  assert.equal(plan.unchanged, 0);
  assert.deepEqual(plan.problems, []);
});

test("a word already carried word for word is dropped, not queued", () => {
  const plan = planProposals("pas - cane", HEADER, rows(["pas", "cane"]));
  assert.deepEqual(plan.queued, []);
  assert.equal(plan.unchanged, 1);
});

test("a word carried with a different translation is queued as a retranslation", () => {
  const plan = planProposals("pas - cagnolino", HEADER, rows(["pas", "cane"]));
  assert.deepEqual(plan.queued, [{ word: "pas", translation: "cagnolino" }]);
  assert.equal(plan.unchanged, 0);
});

test("a repeated word in the dictionary is compared against its first row", () => {
  // Approving writes to the first row, so that is the translation on offer.
  const carried = rows(["pas", "cane"], ["pas", "cagnolino"]);
  assert.equal(planProposals("pas - cane", HEADER, carried).unchanged, 1);
  assert.equal(planProposals("pas - cagnolino", HEADER, carried).queued.length, 1);
});

test("blank lines, comments and the deck's own header are ignored", () => {
  const plan = planProposals(
    "Croatian - Italian\n\n# 100 most used words\npas - cane\n",
    HEADER,
    [],
  );
  assert.deepEqual(plan.queued, [{ word: "pas", translation: "cane" }]);
  assert.deepEqual(plan.problems, []);
});

test("a header for a different pair is read as a word, not skipped", () => {
  const plan = planProposals("Spanish-Italian\npas - cane", HEADER, []);
  assert.equal(plan.queued.length, 2);
  assert.equal(plan.queued[0].word, "Spanish");
});

test("a bad line is reported and the rest of the paste still lands", () => {
  const plan = planProposals("pas - cane\nnonsense\nmačka - gatto", HEADER, []);
  assert.deepEqual(plan.queued, [
    { word: "pas", translation: "cane" },
    { word: "mačka", translation: "gatto" },
  ]);
  assert.equal(plan.problems.length, 1);
  assert.equal(plan.problems[0].line, 2);
  assert.equal(plan.problems[0].text, "nonsense");
});

test("a line starting with # is a comment even when it reads as a pair", () => {
  const plan = planProposals("# ne - non\n\n#hash - cancelletto", HEADER, []);
  assert.deepEqual(plan.queued, []);
  assert.deepEqual(plan.problems, []);
});

test("an empty side is reported with its line number", () => {
  const plan = planProposals("pas - cane\nmačka - ", HEADER, []);
  assert.equal(plan.queued.length, 1);
  assert.equal(plan.problems.length, 1);
  assert.equal(plan.problems[0].line, 2);
});

test("the first row for a word wins and the later one is reported", () => {
  const plan = planProposals("pas - cane\npas - cagnolino", HEADER, []);
  assert.deepEqual(plan.queued, [{ word: "pas", translation: "cane" }]);
  assert.equal(plan.problems.length, 1);
  assert.match(plan.problems[0].reason, /line 1/);
});

test("a word repeated in the paste is reported even when the first was dropped", () => {
  const plan = planProposals(
    "pas - cane\npas - cagnolino",
    HEADER,
    rows(["pas", "cane"]),
  );
  assert.deepEqual(plan.queued, []);
  assert.equal(plan.unchanged, 1);
  assert.equal(plan.problems.length, 1);
});

test("hyphens inside either side survive the split", () => {
  const plan = planProposals("tako-tako - così-così", HEADER, []);
  assert.deepEqual(plan.queued, [
    { word: "tako-tako", translation: "così-così" },
  ]);
});

test("an empty paste is not a problem, it is simply nothing", () => {
  const plan = planProposals("\n  \n", HEADER, []);
  assert.deepEqual(plan.queued, []);
  assert.equal(plan.unchanged, 0);
  assert.deepEqual(plan.problems, []);
});

// Run with: npm test
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { parseDeckText } from "../src/lib/deckFormat.ts";
import { findDuplicates, redundantEntryIds } from "../src/lib/duplicates.ts";
import type { EntryRow } from "../src/lib/db.ts";

const samplesDir = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "samples",
);

/** Rows as `listEntries` returns them: export order, position ascending. */
function rows(...pairs: [string, string][]): EntryRow[] {
  return pairs.map(([word, translation], i) => ({
    id: i + 1,
    word,
    translation,
    position: i,
  }));
}

test("a word carried once is not a duplicate", () => {
  const groups = findDuplicates(rows(["cane", "pas"], ["gatto", "mačka"]));
  assert.deepEqual(groups, []);
  assert.deepEqual(redundantEntryIds(groups), []);
});

test("same word and same translation is an exact copy, keeping the first", () => {
  const groups = findDuplicates(
    rows(["vrt", "giardino"], ["cane", "pas"], ["vrt", "giardino"]),
  );
  assert.equal(groups.length, 1);
  assert.equal(groups[0].word, "vrt");
  assert.equal(groups[0].conflicting, false);
  // Row 1 stays, row 3 goes.
  assert.deepEqual(redundantEntryIds(groups), [3]);
});

test("same word with differing translations is left for review", () => {
  const groups = findDuplicates(rows(["mjesec", "mese/luna"], ["mjesec", "mese"]));
  assert.equal(groups.length, 1);
  assert.equal(groups[0].conflicting, true);
  assert.deepEqual(
    groups[0].entries.map((e) => e.translation),
    ["mese/luna", "mese"],
  );
  // Nothing is auto-removed: dropping either one would decide for the admin.
  assert.deepEqual(redundantEntryIds(groups), []);
});

test("a word repeated three times counts as one group", () => {
  const groups = findDuplicates(
    rows(["jedva", "appena"], ["jedva", "appena"], ["jedva", "a malapena"]),
  );
  assert.equal(groups.length, 1);
  assert.equal(groups[0].entries.length, 3);
  // Two of the three agree, but the third does not — so the whole word is
  // review work, not a silent cleanup.
  assert.equal(groups[0].conflicting, true);
  assert.deepEqual(redundantEntryIds(groups), []);
});

test("groups keep export order so the kept row is the earliest", () => {
  const groups = findDuplicates(
    rows(["b", "x"], ["a", "y"], ["b", "x"], ["b", "x"]),
  );
  assert.deepEqual(
    groups[0].entries.map((e) => e.id),
    [1, 3, 4],
  );
  assert.deepEqual(redundantEntryIds(groups), [3, 4]);
});

test("reproduces the real sample's card-count shortfall", () => {
  const deck = parseDeckText(
    readFileSync(join(samplesDir, "croatian_italian_words.txt"), "utf8"),
  );
  const entries = rows(
    ...deck.pairs.map((p) => [p.word, p.translation] as [string, string]),
  );

  const groups = findDuplicates(entries);
  const distinct = new Set(entries.map((e) => e.word)).size;

  // The numbers behind "745 words on the web, 628 cards on the phone".
  assert.equal(entries.length, 745);
  assert.equal(distinct, 628);
  assert.equal(entries.length - distinct, 117);

  assert.equal(groups.length, 101, "duplicated words");
  assert.equal(groups.filter((g) => g.conflicting).length, 37, "need review");
  assert.equal(groups.filter((g) => !g.conflicting).length, 64, "exact copies");
  assert.equal(redundantEntryIds(groups).length, 74, "rows removable outright");

  // Clearing the exact copies alone cannot change how many distinct words the
  // dictionary carries — it only removes rows the phone was already ignoring.
  const removed = redundantEntryIds(groups);
  const kept = entries.filter((e) => !removed.includes(e.id));
  assert.equal(new Set(kept.map((e) => e.word)).size, distinct);
  assert.equal(kept.length, entries.length - removed.length);
  assert.equal(findDuplicates(kept).every((g) => g.conflicting), true);
});

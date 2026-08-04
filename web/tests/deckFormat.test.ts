// Run with: npm test
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  exportFilename,
  parseDeckText,
  serializeDeck,
  validateEntry,
  validateLanguage,
} from "../src/lib/deckFormat.ts";

const samplesDir = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "samples",
);

test("parses the shape documented in SPEC.md", () => {
  const deck = parseDeckText(
    ["Italian-Croatian", "", "# a comment", "cane-pas", "gatto - mačka"].join(
      "\n",
    ),
  );
  assert.equal(deck.language1, "Italian");
  assert.equal(deck.language2, "Croatian");
  assert.deepEqual(deck.pairs, [
    { word: "cane", translation: "pas" },
    { word: "gatto", translation: "mačka" },
  ]);
});

test("splits on the first spaced hyphen, else the first bare one", () => {
  const deck = parseDeckText("A-B\nlagan - facile/leggero\nne - non / no");
  assert.deepEqual(deck.pairs[0], { word: "lagan", translation: "facile/leggero" });
  const multi = parseDeckText("A-B\ncane - pas-tu");
  assert.deepEqual(multi.pairs[0], { word: "cane", translation: "pas-tu" });
  const bare = parseDeckText("A-B\ncane-pas");
  assert.deepEqual(bare.pairs[0], { word: "cane", translation: "pas" });
});

test("a word may contain hyphens when the line has a spaced separator", () => {
  const deck = parseDeckText("A-B\ntako-tako - cosi-cosi\nwell-being - benessere");
  assert.deepEqual(deck.pairs, [
    { word: "tako-tako", translation: "cosi-cosi" },
    { word: "well-being", translation: "benessere" },
  ]);
  // Only the first spaced hyphen splits; later ones stay in the translation.
  const extra = parseDeckText("A-B\ntako-tako - cosi - cosi");
  assert.deepEqual(extra.pairs[0], { word: "tako-tako", translation: "cosi - cosi" });
});

test("rejects malformed input", () => {
  assert.throws(() => parseDeckText(""), /empty/);
  assert.throws(() => parseDeckText("no hyphen here"), /language1-language2/);
  assert.throws(() => parseDeckText("A-B"), /No vocabulary entries/);
  assert.throws(() => parseDeckText("A-B\nlonely"), /not 'word-translation'/);
  assert.throws(() => parseDeckText("A-B\n- pas"), /not 'word-translation'/);
});

test("validation guards what the app's parser cannot represent", () => {
  assert.equal(validateEntry("cane", "pas"), null);
  assert.equal(validateEntry("cane", "pas-tu"), null);
  assert.equal(validateEntry("well-being", "benessere"), null);
  assert.match(validateEntry("cane - gatto", "pas") ?? "", / - /);
  assert.match(validateEntry("", "pas") ?? "", /required/);
  assert.match(validateEntry("#cane", "pas") ?? "", /#/);
  assert.equal(validateLanguage("Language 1", "Italian"), null);
  assert.match(validateLanguage("Language 1", "Serbo-Croatian") ?? "", /hyphen/);
});

test("serialize produces text the parser reads back identically", () => {
  const deck = {
    language1: "Italian",
    language2: "Croatian",
    pairs: [
      { word: "cane", translation: "pas" },
      { word: "così-così", translation: "tako-tako" },
    ],
  };
  assert.equal(
    serializeDeck(deck),
    "Italian-Croatian\ncane - pas\ncosì-così - tako-tako\n",
  );
  assert.deepEqual(parseDeckText(serializeDeck(deck)), deck);
});

test("round-trips every real sample file", () => {
  const files = readdirSync(samplesDir).filter((f) => f.endsWith(".txt"));
  assert.ok(files.length > 0, "no sample files found");

  for (const file of files) {
    const original = parseDeckText(readFileSync(join(samplesDir, file), "utf8"));
    const roundTripped = parseDeckText(serializeDeck(original));
    assert.deepEqual(roundTripped, original, `${file} did not round-trip`);

    for (const pair of original.pairs) {
      assert.equal(
        validateEntry(pair.word, pair.translation),
        null,
        `${file}: "${pair.word}" would be rejected by the editor`,
      );
    }
  }
});

test("export filename keeps the deck name", () => {
  assert.equal(exportFilename("Croatian-Italian"), "Croatian-Italian.txt");
  assert.equal(exportFilename("my/deck.txt"), "my_deck.txt");
});

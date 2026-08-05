// Imports every ../samples/*.txt into the database, skipping decks that
// already exist. Run after db:migrate.
// Usage: npm run db:seed
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, basename } from "node:path";
import { neon } from "@neondatabase/serverless";
import { parseDeckText } from "../src/lib/deckFormat.ts";

const here = dirname(fileURLToPath(import.meta.url));
const samplesDir = join(here, "..", "..", "samples");

const url = process.env.DATABASE_URL;
if (!url) {
  console.error("DATABASE_URL is not set. Put it in web/.env.local.");
  process.exit(1);
}
const sql = neon(url);

const files = readdirSync(samplesDir).filter((f) => f.endsWith(".txt")).sort();
if (files.length === 0) {
  console.error(`No .txt files in ${samplesDir}`);
  process.exit(1);
}

for (const file of files) {
  const name = basename(file, ".txt");
  const existing = await sql`select id from decks where name = ${name}`;
  if (existing.length > 0) {
    console.log(`skip: "${name}" already exists`);
    continue;
  }

  let deck;
  try {
    deck = parseDeckText(readFileSync(join(samplesDir, file), "utf8"));
  } catch (error) {
    console.error(`skip: "${name}" — ${error.message}`);
    continue;
  }

  // The sample's own labels have to be on the admin's list, or the deck would
  // arrive with a pair its own settings menu cannot offer back.
  await sql`
    insert into languages (name)
    values (${deck.language1}), (${deck.language2})
    on conflict (name) do nothing
  `;

  const [row] = await sql`
    insert into decks (name, language1, language2)
    values (${name}, ${deck.language1}, ${deck.language2})
    returning id
  `;

  // One round trip for the whole deck — the biggest sample is ~745 entries.
  await sql.query(
    `insert into entries (deck_id, word, translation, position)
     select $1, * from unnest($2::text[], $3::text[], $4::int[])`,
    [
      row.id,
      deck.pairs.map((p) => p.word),
      deck.pairs.map((p) => p.translation),
      deck.pairs.map((_, i) => i),
    ],
  );

  console.log(
    `seeded: "${name}" (${deck.language1}-${deck.language2}, ${deck.pairs.length} entries)`,
  );
}

import { neon, type NeonQueryFunction } from "@neondatabase/serverless";

let client: NeonQueryFunction<false, false> | null = null;

/**
 * Lazy so `next build` does not need DATABASE_URL just to compile the pages
 * that use it.
 */
export function sql(): NeonQueryFunction<false, false> {
  if (!client) {
    const url = process.env.DATABASE_URL;
    if (!url) throw new Error("DATABASE_URL is not set.");
    client = neon(url);
  }
  return client;
}

export type DeckRow = {
  id: number;
  name: string;
  language1: string;
  language2: string;
  entry_count: number;
};

export type EntryRow = {
  id: number;
  word: string;
  translation: string;
  position: number;
};

export async function listDecks(): Promise<DeckRow[]> {
  return (await sql()`
    select d.id, d.name, d.language1, d.language2,
           count(e.id)::int as entry_count
    from decks d
    left join entries e on e.deck_id = d.id
    group by d.id
    order by d.name
  `) as DeckRow[];
}

export async function getDeck(id: number): Promise<DeckRow | null> {
  const rows = (await sql()`
    select d.id, d.name, d.language1, d.language2,
           (select count(*)::int from entries e where e.deck_id = d.id) as entry_count
    from decks d
    where d.id = ${id}
  `) as DeckRow[];
  return rows[0] ?? null;
}

export async function listEntries(deckId: number): Promise<EntryRow[]> {
  return (await sql()`
    select id, word, translation, position
    from entries
    where deck_id = ${deckId}
    order by position, id
  `) as EntryRow[];
}

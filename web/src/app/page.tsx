import Link from "next/link";
import { listDecks } from "@/lib/db";
import { createDeck, logout } from "./actions";

export const dynamic = "force-dynamic";

export default async function LibraryPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  const decks = await listDecks();

  return (
    <>
      <header className="bar">
        <h1>Vohe Dictionaries</h1>
        <form action={logout}>
          <button type="submit">Sign out</button>
        </form>
      </header>

      {error && <p className="error">{error}</p>}

      <h2>Dictionaries</h2>
      {decks.length === 0 ? (
        <p className="hint">No dictionaries yet. Create one below.</p>
      ) : (
        <ul className="deck-list">
          {decks.map((deck) => (
            <li key={deck.id}>
              <span>
                <Link href={`/decks/${deck.id}`}>{deck.name}</Link>
                <span className="meta">
                  {" "}
                  — {deck.language1}–{deck.language2}, {deck.entry_count} words
                </span>
              </span>
              <a href={`/decks/${deck.id}/export`}>.txt</a>
            </li>
          ))}
        </ul>
      )}

      <h2>New dictionary</h2>
      <form action={createDeck} className="stack card">
        <label htmlFor="name">Name (becomes the deck and file name)</label>
        <input id="name" name="name" type="text" placeholder="Italian-Croatian" />
        <div className="row" style={{ gridTemplateColumns: "1fr 1fr" }}>
          <span>
            <label htmlFor="language1">Front language</label>
            <input id="language1" name="language1" type="text" placeholder="Italian" />
          </span>
          <span>
            <label htmlFor="language2">Back language</label>
            <input id="language2" name="language2" type="text" placeholder="Croatian" />
          </span>
        </div>
        <p className="hint">
          These two become the first line of the exported file
          (<code>Italian-Croatian</code>), so neither may contain a hyphen.
        </p>
        <div>
          <button className="primary" type="submit">
            Create
          </button>
        </div>
      </form>
    </>
  );
}

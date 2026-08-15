import Link from "next/link";
import { redirect } from "next/navigation";
import { listDecks, listLanguages } from "@/lib/db";
import { currentUser } from "@/lib/session";
import { NoAccess } from "./NoAccess";
import { SubmitButton } from "./SubmitButton";
import { createDeck, logout } from "./actions";

export const dynamic = "force-dynamic";

export default async function LibraryPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const user = await currentUser();
  if (!user) redirect("/login");
  if (user.role !== "admin") return <NoAccess username={user.username} />;

  const { error } = await searchParams;
  const decks = await listDecks();
  const languages = await listLanguages();

  return (
    <>
      <header className="bar">
        <h1>Vohe Dictionaries</h1>
        <span className="inline">
          <Link href="/languages">Languages</Link>
          <form action={logout}>
            <SubmitButton>Sign out</SubmitButton>
          </form>
        </span>
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
                  — {deck.language1}–{deck.language2}, {deck.entry_count} words,
                  v{deck.version}
                </span>
                {deck.pending_count > 0 && (
                  <>
                    {" "}
                    <Link className="badge" href={`/decks/${deck.id}`}>
                      {deck.pending_count} to review
                    </Link>
                  </>
                )}
                {deck.distinct_count < deck.entry_count && (
                  <>
                    {" "}
                    <Link className="badge" href={`/decks/${deck.id}`}>
                      {deck.entry_count - deck.distinct_count} repeated
                    </Link>
                  </>
                )}
              </span>
              <a href={`/decks/${deck.id}/export`}>.txt</a>
            </li>
          ))}
        </ul>
      )}

      <h2>New dictionary</h2>
      {languages.length === 0 ? (
        <p className="hint">
          A dictionary needs a front and a back language, and there are none to
          pick yet. Add them in <Link href="/languages">Languages</Link> first.
        </p>
      ) : (
        <form action={createDeck} className="stack card">
          <label htmlFor="name">Name (becomes the deck and file name)</label>
          <input id="name" name="name" type="text" placeholder="Italian-Croatian" />
          <div className="row" style={{ gridTemplateColumns: "1fr 1fr" }}>
            <span>
              <label htmlFor="language1">Front language</label>
              <select id="language1" name="language1" defaultValue="">
                <option value="">Choose…</option>
                {languages.map((language) => (
                  <option key={language.id} value={language.name}>
                    {language.name}
                  </option>
                ))}
              </select>
            </span>
            <span>
              <label htmlFor="language2">Back language</label>
              <select id="language2" name="language2" defaultValue="">
                <option value="">Choose…</option>
                {languages.map((language) => (
                  <option key={language.id} value={language.name}>
                    {language.name}
                  </option>
                ))}
              </select>
            </span>
          </div>
          <p className="hint">
            These two become the first line of the exported file
            (<code>Italian-Croatian</code>) and come from{" "}
            <Link href="/languages">Languages</Link>.
          </p>
          <div>
            <SubmitButton className="primary">Create</SubmitButton>
          </div>
        </form>
      )}
    </>
  );
}

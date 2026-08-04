import Link from "next/link";
import { notFound } from "next/navigation";
import { getDeck, listEntries, listPendingSubmissions } from "@/lib/db";
import {
  addEntry,
  approveWord,
  deleteDeck,
  deleteEntry,
  importEntries,
  logout,
  rejectWord,
  updateDeck,
  updateEntry,
} from "../../actions";

export const dynamic = "force-dynamic";

export default async function DeckPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const { id } = await params;
  const { error } = await searchParams;

  const deckId = Number(id);
  if (!Number.isInteger(deckId)) notFound();

  const deck = await getDeck(deckId);
  if (!deck) notFound();

  const entries = await listEntries(deckId);
  const pending = await listPendingSubmissions(deckId);

  return (
    <>
      <header className="bar">
        <h1>{deck.name}</h1>
        <span className="inline">
          <Link href="/">All dictionaries</Link>
          <form action={logout}>
            <button type="submit">Sign out</button>
          </form>
        </span>
      </header>
      <p className="hint">
        {deck.language1}–{deck.language2} · {deck.entry_count} words · version{" "}
        {deck.version} · <a href={`/decks/${deckId}/export`}>download .txt</a>
      </p>

      {error && <p className="error">{error}</p>}

      {pending.length > 0 && (
        <>
          <h2>From the app — waiting for review ({pending.length})</h2>
          <p className="hint">
            Words sent from Vohe on the phone. They are not part of this
            dictionary, the exported <code>.txt</code>, or any other device
            until you approve them.
          </p>
          {pending.map((submission) => (
            <div className="row" key={submission.id}>
              <span>{submission.word}</span>
              <span>
                {submission.translation}
                {submission.current_translation !== null &&
                  submission.current_translation !== submission.translation && (
                    <span className="meta">
                      {" "}
                      (replaces &ldquo;{submission.current_translation}&rdquo;)
                    </span>
                  )}
              </span>
              <form action={approveWord}>
                <input type="hidden" name="deckId" value={deckId} />
                <input type="hidden" name="submissionId" value={submission.id} />
                <button className="primary" type="submit">
                  Approve
                </button>
              </form>
              <form action={rejectWord}>
                <input type="hidden" name="deckId" value={deckId} />
                <input type="hidden" name="submissionId" value={submission.id} />
                <button className="danger" type="submit">
                  Reject
                </button>
              </form>
            </div>
          ))}
        </>
      )}

      <h2>Add a word</h2>
      <form action={addEntry} className="card">
        <input type="hidden" name="deckId" value={deckId} />
        <div className="row">
          <input
            name="word"
            type="text"
            placeholder={deck.language1}
            aria-label={deck.language1}
          />
          <input
            name="translation"
            type="text"
            placeholder={deck.language2}
            aria-label={deck.language2}
          />
          <button className="primary" type="submit">
            Add
          </button>
        </div>
      </form>

      <h2>Words ({entries.length})</h2>
      <div className="row head">
        <span>{deck.language1}</span>
        <span>{deck.language2}</span>
      </div>
      {entries.map((entry) => (
        <div className="row" key={entry.id}>
          <form
            action={updateEntry}
            id={`edit-${entry.id}`}
            style={{ display: "contents" }}
          >
            <input type="hidden" name="deckId" value={deckId} />
            <input type="hidden" name="entryId" value={entry.id} />
            <input
              name="word"
              type="text"
              defaultValue={entry.word}
              aria-label={`${deck.language1} word`}
            />
            <input
              name="translation"
              type="text"
              defaultValue={entry.translation}
              aria-label={`${deck.language2} translation`}
            />
            <button type="submit">Save</button>
          </form>
          <form action={deleteEntry}>
            <input type="hidden" name="deckId" value={deckId} />
            <input type="hidden" name="entryId" value={entry.id} />
            <button className="danger" type="submit">
              Delete
            </button>
          </form>
        </div>
      ))}
      {entries.length === 0 && (
        <p className="hint">No words yet. Add one above, or paste a list below.</p>
      )}

      <h2>Paste a list</h2>
      <form action={importEntries} className="stack card">
        <input type="hidden" name="deckId" value={deckId} />
        <textarea
          name="text"
          aria-label="Words to import"
          placeholder={`ciao - bok\ngrazie - hvala\ncosì-così - tako-tako`}
        />
        <p className="hint">
          One <code>word - translation</code> per line; appended to the end. The
          spaces around the hyphen mark the split, so both sides may contain
          hyphens (<code>così-così - tako-tako</code>). Blank lines and{" "}
          <code>#</code> comments are ignored, and a first line reading <code>
            {deck.language1}-{deck.language2}
          </code>{" "}
          is skipped, so a whole .txt file can be pasted. Nothing is imported if
          any line is invalid.
        </p>
        <div>
          <button className="primary" type="submit">
            Import
          </button>
        </div>
      </form>

      <h2>Dictionary settings</h2>
      <form action={updateDeck} className="stack card">
        <input type="hidden" name="deckId" value={deckId} />
        <div className="row" style={{ gridTemplateColumns: "1fr 1fr 1fr" }}>
          <span>
            <label htmlFor="name">Name</label>
            <input id="name" name="name" type="text" defaultValue={deck.name} />
          </span>
          <span>
            <label htmlFor="language1">Front language</label>
            <input
              id="language1"
              name="language1"
              type="text"
              defaultValue={deck.language1}
            />
          </span>
          <span>
            <label htmlFor="language2">Back language</label>
            <input
              id="language2"
              name="language2"
              type="text"
              defaultValue={deck.language2}
            />
          </span>
        </div>
        <div>
          <button type="submit">Save settings</button>
        </div>
      </form>

      <form action={deleteDeck} className="stack card">
        <input type="hidden" name="deckId" value={deckId} />
        <label htmlFor="confirm">
          Delete this dictionary and all {entries.length} words — type DELETE to
          confirm
        </label>
        <div className="inline">
          <input
            id="confirm"
            name="confirm"
            type="text"
            style={{ maxWidth: 160 }}
          />
          <button className="danger" type="submit">
            Delete dictionary
          </button>
        </div>
      </form>
    </>
  );
}

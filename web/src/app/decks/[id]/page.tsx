import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import {
  getDeck,
  listEntries,
  listLanguages,
  listPendingSubmissions,
} from "@/lib/db";
import { currentUser } from "@/lib/session";
import { findDuplicates, redundantEntryIds } from "@/lib/duplicates";
import { NoAccess } from "../../NoAccess";
import { SubmitButton } from "../../SubmitButton";
import {
  addEntry,
  approveWord,
  deleteDeck,
  deleteEntry,
  importEntries,
  logout,
  rejectWord,
  removeExactDuplicates,
  resolveDuplicate,
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
  const user = await currentUser();
  if (!user) redirect("/login");
  if (user.role !== "admin") return <NoAccess username={user.username} />;

  const { id } = await params;
  const { error } = await searchParams;

  const deckId = Number(id);
  if (!Number.isInteger(deckId)) notFound();

  const deck = await getDeck(deckId);
  if (!deck) notFound();

  const entries = await listEntries(deckId);
  const pending = await listPendingSubmissions(deckId);
  const languages = await listLanguages();

  const duplicates = findDuplicates(entries);
  const conflicting = duplicates.filter((group) => group.conflicting);
  const exactCopies = duplicates.length - conflicting.length;
  const removableRows = redundantEntryIds(duplicates).length;

  return (
    <>
      <header className="bar">
        <h1>{deck.name}</h1>
        <span className="inline">
          <Link href="/">All dictionaries</Link>
          <form action={logout}>
            <SubmitButton>Sign out</SubmitButton>
          </form>
        </span>
      </header>
      <p className="hint">
        {deck.language1}–{deck.language2} · {deck.entry_count} words
        {deck.distinct_count < deck.entry_count && (
          <> · {deck.distinct_count} cards on the phone</>
        )}{" "}
        · version {deck.version} ·{" "}
        <a href={`/decks/${deckId}/export`}>download .txt</a>
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
                {submission.proposer && (
                  <span className="meta"> — from {submission.proposer}</span>
                )}
              </span>
              <form action={approveWord}>
                <input type="hidden" name="deckId" value={deckId} />
                <input type="hidden" name="submissionId" value={submission.id} />
                <SubmitButton className="primary">Approve</SubmitButton>
              </form>
              <form action={rejectWord}>
                <input type="hidden" name="deckId" value={deckId} />
                <input type="hidden" name="submissionId" value={submission.id} />
                <SubmitButton className="danger">Reject</SubmitButton>
              </form>
            </div>
          ))}
        </>
      )}

      {duplicates.length > 0 && (
        <>
          <h2>Repeated words ({duplicates.length})</h2>
          <p className="hint">
            Vohe keys a card on the word, so only the last row for a repeated
            word reaches the phone — which is why {deck.entry_count} words here
            become {deck.distinct_count} cards. Clear the identical copies in
            one go, then pick the translation to keep for the ones that
            disagree.
          </p>

          {exactCopies > 0 && (
            <form action={removeExactDuplicates} className="card">
              <input type="hidden" name="deckId" value={deckId} />
              <div className="inline">
                <SubmitButton className="primary">
                  Remove {removableRows} identical{" "}
                  {removableRows === 1 ? "copy" : "copies"}
                </SubmitButton>
                <span className="meta">
                  {exactCopies} {exactCopies === 1 ? "word" : "words"} repeated
                  with the same translation — the first row stays, nothing is
                  lost.
                </span>
              </div>
            </form>
          )}

          {conflicting.map((group) => (
            <div className="card" key={group.word}>
              <p className="inline" style={{ marginTop: 0 }}>
                <strong>{group.word}</strong>
                <span className="meta">
                  {group.entries.length} rows disagree — keep one, edit it first
                  if the right answer is a mix
                </span>
              </p>
              {group.entries.map((entry) => (
                <form
                  action={resolveDuplicate}
                  className="row"
                  style={{ gridTemplateColumns: "1fr auto" }}
                  key={entry.id}
                >
                  <input type="hidden" name="deckId" value={deckId} />
                  <input type="hidden" name="entryId" value={entry.id} />
                  <input
                    name="translation"
                    type="text"
                    defaultValue={entry.translation}
                    aria-label={`${deck.language2} translation of ${group.word}`}
                  />
                  <SubmitButton>Keep this one</SubmitButton>
                </form>
              ))}
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
          <SubmitButton className="primary">Add</SubmitButton>
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
            <SubmitButton>Save</SubmitButton>
          </form>
          <form action={deleteEntry}>
            <input type="hidden" name="deckId" value={deckId} />
            <input type="hidden" name="entryId" value={entry.id} />
            <SubmitButton className="danger">Delete</SubmitButton>
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
          <SubmitButton className="primary">Import</SubmitButton>
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
            <select id="language1" name="language1" defaultValue={deck.language1}>
              {languages.map((language) => (
                <option key={language.id} value={language.name}>
                  {language.name}
                </option>
              ))}
            </select>
          </span>
          <span>
            <label htmlFor="language2">Back language</label>
            <select id="language2" name="language2" defaultValue={deck.language2}>
              {languages.map((language) => (
                <option key={language.id} value={language.name}>
                  {language.name}
                </option>
              ))}
            </select>
          </span>
        </div>
        <p className="hint">
          Both menus come from <Link href="/languages">Languages</Link>. Changing
          either one rewrites the exported file&rsquo;s first line and offers the
          phone an update.
        </p>
        <div>
          <SubmitButton>Save settings</SubmitButton>
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
          <SubmitButton className="danger">Delete dictionary</SubmitButton>
        </div>
      </form>
    </>
  );
}

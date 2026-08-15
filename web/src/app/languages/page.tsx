import Link from "next/link";
import { redirect } from "next/navigation";
import { listLanguages } from "@/lib/db";
import { currentUser } from "@/lib/session";
import { NoAccess } from "../NoAccess";
import { SubmitButton } from "../SubmitButton";
import { addLanguage, deleteLanguage, logout } from "../actions";

export const dynamic = "force-dynamic";

export default async function LanguagesPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const user = await currentUser();
  if (!user) redirect("/login");
  if (user.role !== "admin") return <NoAccess username={user.username} />;

  const { error } = await searchParams;
  const languages = await listLanguages();

  return (
    <>
      <header className="bar">
        <h1>Languages</h1>
        <span className="inline">
          <Link href="/">All dictionaries</Link>
          <form action={logout}>
            <SubmitButton>Sign out</SubmitButton>
          </form>
        </span>
      </header>
      <p className="hint">
        The labels the front and back menus offer when you create or edit a
        dictionary. They become the first line of the exported file
        (<code>Italian-Croatian</code>), so none may contain a hyphen.
      </p>

      {error && <p className="error">{error}</p>}

      <h2>In the list ({languages.length})</h2>
      {languages.length === 0 ? (
        <p className="hint">No languages yet. Add the first one below.</p>
      ) : (
        <ul className="deck-list">
          {languages.map((language) => (
            <li key={language.id}>
              <span>
                {language.name}
                {language.deck_count > 0 && (
                  <span className="meta">
                    {" "}
                    — used by {language.deck_count}{" "}
                    {language.deck_count === 1 ? "dictionary" : "dictionaries"}
                  </span>
                )}
              </span>
              {language.deck_count === 0 && (
                <form action={deleteLanguage}>
                  <input type="hidden" name="languageId" value={language.id} />
                  <SubmitButton className="danger">Delete</SubmitButton>
                </form>
              )}
            </li>
          ))}
        </ul>
      )}

      <h2>Add a language</h2>
      <form action={addLanguage} className="card">
        <div className="inline">
          <input
            name="name"
            type="text"
            placeholder="English"
            aria-label="Language"
            style={{ maxWidth: 240 }}
          />
          <SubmitButton className="primary">Add</SubmitButton>
        </div>
      </form>
    </>
  );
}

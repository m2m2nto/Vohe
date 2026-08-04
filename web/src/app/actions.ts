"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import {
  SESSION_COOKIE,
  SESSION_MAX_AGE_SECONDS,
  createSessionCookie,
  isCorrectPassword,
} from "@/lib/auth";
import {
  approveSubmission,
  bumpDeckVersion,
  rejectSubmission,
  sql,
} from "@/lib/db";
import {
  normalizeName,
  parseDeckText,
  validateEntry,
  validateLanguage,
} from "@/lib/deckFormat";

function field(formData: FormData, name: string): string {
  const value = formData.get(name);
  return typeof value === "string" ? value.trim() : "";
}

function deckPath(deckId: number, error?: string): string {
  return error
    ? `/decks/${deckId}?error=${encodeURIComponent(error)}`
    : `/decks/${deckId}`;
}

export async function login(formData: FormData) {
  if (!isCorrectPassword(field(formData, "password"))) {
    redirect("/login?error=1");
  }
  const store = await cookies();
  store.set(SESSION_COOKIE, await createSessionCookie(Date.now()), {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: SESSION_MAX_AGE_SECONDS,
  });
  redirect("/");
}

export async function logout() {
  const store = await cookies();
  store.delete(SESSION_COOKIE);
  redirect("/login");
}

export async function createDeck(formData: FormData) {
  const name = normalizeName(field(formData, "name"));
  const language1 = field(formData, "language1");
  const language2 = field(formData, "language2");

  const error =
    (!name ? "Deck name is required." : null) ??
    validateLanguage("Language 1", language1) ??
    validateLanguage("Language 2", language2);
  if (error) redirect(`/?error=${encodeURIComponent(error)}`);

  let created: { id: number }[];
  try {
    created = (await sql()`
      insert into decks (name, language1, language2)
      values (${name}, ${language1}, ${language2})
      returning id
    `) as { id: number }[];
  } catch (e) {
    const message =
      e instanceof Error && e.message.includes("decks_name_key")
        ? `A deck named "${name}" already exists.`
        : "Could not create the deck.";
    redirect(`/?error=${encodeURIComponent(message)}`);
  }

  revalidatePath("/");
  redirect(deckPath(created[0].id));
}

export async function updateDeck(formData: FormData) {
  const deckId = Number(field(formData, "deckId"));
  const name = normalizeName(field(formData, "name"));
  const language1 = field(formData, "language1");
  const language2 = field(formData, "language2");

  const error =
    (!name ? "Deck name is required." : null) ??
    validateLanguage("Language 1", language1) ??
    validateLanguage("Language 2", language2);
  if (error) redirect(deckPath(deckId, error));

  await sql()`
    update decks
    set name = ${name}, language1 = ${language1}, language2 = ${language2}
    where id = ${deckId}
  `;
  await bumpDeckVersion(deckId);
  revalidatePath("/");
  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId));
}

export async function deleteDeck(formData: FormData) {
  const deckId = Number(field(formData, "deckId"));
  if (field(formData, "confirm") !== "DELETE") {
    redirect(deckPath(deckId, 'Type DELETE to confirm deck deletion.'));
  }
  await sql()`delete from decks where id = ${deckId}`;
  revalidatePath("/");
  redirect("/");
}

export async function addEntry(formData: FormData) {
  const deckId = Number(field(formData, "deckId"));
  const word = field(formData, "word");
  const translation = field(formData, "translation");

  const error = validateEntry(word, translation);
  if (error) redirect(deckPath(deckId, error));

  await sql()`
    insert into entries (deck_id, word, translation, position)
    values (
      ${deckId}, ${word}, ${translation},
      coalesce((select max(position) + 1 from entries where deck_id = ${deckId}), 0)
    )
  `;
  await bumpDeckVersion(deckId);
  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId));
}

export async function updateEntry(formData: FormData) {
  const deckId = Number(field(formData, "deckId"));
  const entryId = Number(field(formData, "entryId"));
  const word = field(formData, "word");
  const translation = field(formData, "translation");

  const error = validateEntry(word, translation);
  if (error) redirect(deckPath(deckId, error));

  await sql()`
    update entries
    set word = ${word}, translation = ${translation}
    where id = ${entryId} and deck_id = ${deckId}
  `;
  await bumpDeckVersion(deckId);
  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId));
}

export async function deleteEntry(formData: FormData) {
  const deckId = Number(field(formData, "deckId"));
  const entryId = Number(field(formData, "entryId"));
  await sql()`delete from entries where id = ${entryId} and deck_id = ${deckId}`;
  await bumpDeckVersion(deckId);
  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId));
}

/**
 * Accepts a word proposed by the iOS app: it joins the dictionary, the version
 * moves, and every app that pulls the update gets it.
 */
export async function approveWord(formData: FormData) {
  const deckId = Number(field(formData, "deckId"));
  const submissionId = Number(field(formData, "submissionId"));
  await approveSubmission(deckId, submissionId);
  revalidatePath("/");
  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId));
}

/** Declines a proposal. The dictionary is untouched; the app keeps its own copy. */
export async function rejectWord(formData: FormData) {
  const deckId = Number(field(formData, "deckId"));
  const submissionId = Number(field(formData, "submissionId"));
  await rejectSubmission(deckId, submissionId);
  revalidatePath("/");
  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId));
}

/**
 * Appends pasted "word - translation" lines. A leading header line matching the
 * deck's own language pair is ignored, so a whole .txt file can be pasted.
 * All-or-nothing: one bad line rejects the whole paste.
 */
export async function importEntries(formData: FormData) {
  const deckId = Number(field(formData, "deckId"));
  const raw = formData.get("text");
  const text = typeof raw === "string" ? raw : "";

  const decks = (await sql()`
    select language1, language2 from decks where id = ${deckId}
  `) as { language1: string; language2: string }[];
  const deck = decks[0];
  if (!deck) redirect("/");

  const lines = text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"));

  if (lines.length === 0) {
    redirect(deckPath(deckId, "Nothing to import."));
  }

  const header = `${deck.language1}-${deck.language2}`.toLowerCase();
  const first = lines[0].replace(/\s*-\s*/, "-").toLowerCase();
  const body = first === header ? lines.slice(1) : lines;

  // "well-being - benessere" would silently import as "well" / "being - benessere",
  // because the app splits on the first hyphen. Reject instead of corrupting.
  const ambiguous = body.find((line) => {
    const spaced = line.indexOf(" - ");
    return spaced !== -1 && line.indexOf("-") !== spaced + 1;
  });
  if (ambiguous) {
    redirect(
      deckPath(
        deckId,
        `Ambiguous line: "${ambiguous}" — the word side cannot contain a hyphen.`,
      ),
    );
  }

  let parsed;
  try {
    parsed = parseDeckText([header, ...body].join("\n"));
  } catch (e) {
    redirect(deckPath(deckId, e instanceof Error ? e.message : "Import failed."));
  }

  for (const pair of parsed.pairs) {
    const error = validateEntry(pair.word, pair.translation);
    if (error) redirect(deckPath(deckId, error));
  }

  const [{ next }] = (await sql()`
    select coalesce(max(position) + 1, 0)::int as next
    from entries where deck_id = ${deckId}
  `) as { next: number }[];

  await sql().query(
    `insert into entries (deck_id, word, translation, position)
     select $1, w, t, $2 + p
     from unnest($3::text[], $4::text[], $5::int[]) as u(w, t, p)`,
    [
      deckId,
      next,
      parsed.pairs.map((p) => p.word),
      parsed.pairs.map((p) => p.translation),
      parsed.pairs.map((_, i) => i),
    ],
  );
  await bumpDeckVersion(deckId);

  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId));
}

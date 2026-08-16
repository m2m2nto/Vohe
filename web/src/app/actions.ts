"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import {
  DUMMY_PASSWORD_HASH,
  SESSION_COOKIE,
  TOKEN_MAX_AGE_SECONDS,
  createToken,
  generatePassword,
  hashPassword,
  verifyPassword,
} from "@/lib/auth";
import {
  approveSubmissions,
  bumpDeckVersion,
  countAdmins,
  createUser,
  deleteUser,
  findUserByUsername,
  getDeck,
  getUser,
  insertSubmissions,
  listEntries,
  listLanguages,
  rejectSubmissions,
  setUserPassword,
  setUserRole,
  sql,
} from "@/lib/db";
import { requireAdmin } from "@/lib/session";
import { refuseDelete, refuseRoleChange } from "@/lib/accountGuards";
import {
  normalizeName,
  parseDeckText,
  validateEntry,
  validateLanguage,
  validateLanguageChoice,
} from "@/lib/deckFormat";
import { findDuplicates, redundantEntryIds } from "@/lib/duplicates";
import { planProposals, type ProposalPlan } from "@/lib/proposals";

function field(formData: FormData, name: string): string {
  const value = formData.get(name);
  return typeof value === "string" ? value.trim() : "";
}

/**
 * A notice reports what an action did when the count is the point — how many
 * words were queued, skipped or added. It rides the URL like the error does, so
 * it survives the redirect that follows every write.
 */
function deckPath(deckId: number, error?: string, notice?: string): string {
  if (error) return `/decks/${deckId}?error=${encodeURIComponent(error)}`;
  if (notice) return `/decks/${deckId}?notice=${encodeURIComponent(notice)}`;
  return `/decks/${deckId}`;
}

function plural(count: number, noun: string): string {
  return count === 1 ? noun : `${noun}s`;
}

function languagesPath(error?: string): string {
  return error ? `/languages?error=${encodeURIComponent(error)}` : "/languages";
}

function usersPath(error?: string): string {
  return error ? `/users?error=${encodeURIComponent(error)}` : "/users";
}

/**
 * Re-read on every save rather than trusted from the posted form: the menu the
 * admin saw may name a language that has since been deleted.
 */
async function languageNames(): Promise<string[]> {
  return (await listLanguages()).map((language) => language.name);
}

/**
 * Any account may sign in; whether it may then do anything is the pages' and
 * the actions' question. An unknown username costs the same derivation as a
 * wrong password and gets the same message, so neither can be told from the
 * other. The password is read untrimmed — it is compared to a hash, not typed
 * into a field where a stray space would be a slip.
 */
export async function login(formData: FormData) {
  const raw = formData.get("password");
  const password = typeof raw === "string" ? raw : "";
  const user = await findUserByUsername(field(formData, "username"));
  const correct = await verifyPassword(
    password,
    user?.password_hash ?? DUMMY_PASSWORD_HASH,
  );
  if (!user || !correct) redirect("/login?error=1");

  const store = await cookies();
  store.set(SESSION_COOKIE, await createToken("web", user.id, Date.now()), {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: TOKEN_MAX_AGE_SECONDS.web,
  });
  redirect("/");
}

export async function logout() {
  const store = await cookies();
  store.delete(SESSION_COOKIE);
  redirect("/login");
}

/**
 * Adds a label the dictionary menus will offer. The export rules are checked
 * here, once, so no deck can later be given a pair the .txt header cannot hold.
 */
export async function addLanguage(formData: FormData) {
  await requireAdmin();
  const name = field(formData, "name");

  const error = validateLanguage("Language", name);
  if (error) redirect(languagesPath(error));

  try {
    await sql()`insert into languages (name) values (${name})`;
  } catch (e) {
    const message =
      e instanceof Error && e.message.includes("languages_name_key")
        ? `"${name}" is already in the list.`
        : "Could not add the language.";
    redirect(languagesPath(message));
  }

  revalidatePath("/languages");
  revalidatePath("/");
  redirect(languagesPath());
}

/**
 * Removes a label from the menus. Refused while a dictionary is set to it, so
 * no deck can end up naming a language the admin can no longer pick.
 */
export async function deleteLanguage(formData: FormData) {
  await requireAdmin();
  const languageId = Number(field(formData, "languageId"));

  const rows = (await sql()`
    select name from languages where id = ${languageId}
  `) as { name: string }[];
  const language = rows[0];
  if (!language) redirect(languagesPath("That language is no longer in the list."));

  // Recounted here rather than trusted from the form: the page may be stale.
  const [{ used }] = (await sql()`
    select count(*)::int as used from decks
    where language1 = ${language.name} or language2 = ${language.name}
  `) as { used: number }[];

  if (used > 0) {
    redirect(
      languagesPath(
        `"${language.name}" is used by ${used} ${
          used === 1 ? "dictionary" : "dictionaries"
        }. Change ${used === 1 ? "it" : "them"} first.`,
      ),
    );
  }

  await sql()`delete from languages where id = ${languageId}`;
  revalidatePath("/languages");
  revalidatePath("/");
  redirect(languagesPath());
}

export async function createDeck(formData: FormData) {
  await requireAdmin();
  const name = normalizeName(field(formData, "name"));
  const language1 = field(formData, "language1");
  const language2 = field(formData, "language2");

  const allowed = await languageNames();
  const error =
    (!name ? "Deck name is required." : null) ??
    validateLanguageChoice("Front language", language1, allowed) ??
    validateLanguageChoice("Back language", language2, allowed);
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
  await requireAdmin();
  const deckId = Number(field(formData, "deckId"));
  const name = normalizeName(field(formData, "name"));
  const language1 = field(formData, "language1");
  const language2 = field(formData, "language2");

  const allowed = await languageNames();
  const error =
    (!name ? "Deck name is required." : null) ??
    validateLanguageChoice("Front language", language1, allowed) ??
    validateLanguageChoice("Back language", language2, allowed);
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
  await requireAdmin();
  const deckId = Number(field(formData, "deckId"));
  if (field(formData, "confirm") !== "DELETE") {
    redirect(deckPath(deckId, 'Type DELETE to confirm deck deletion.'));
  }
  await sql()`delete from decks where id = ${deckId}`;
  revalidatePath("/");
  redirect("/");
}

export async function addEntry(formData: FormData) {
  await requireAdmin();
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
  await requireAdmin();
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
  await requireAdmin();
  const deckId = Number(field(formData, "deckId"));
  const entryId = Number(field(formData, "entryId"));
  await sql()`delete from entries where id = ${entryId} and deck_id = ${deckId}`;
  await bumpDeckVersion(deckId);
  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId));
}

/**
 * Drops the extra rows of every word whose copies all say the same thing,
 * keeping the earliest. The phone was already showing one card per word, so
 * this changes nothing there — it just makes the two counts agree. Words whose
 * copies disagree are untouched; only the admin can settle those.
 */
export async function removeExactDuplicates(formData: FormData) {
  await requireAdmin();
  const deckId = Number(field(formData, "deckId"));

  // Recomputed here rather than trusted from the form: the page may be stale.
  const ids = redundantEntryIds(findDuplicates(await listEntries(deckId)));
  if (ids.length === 0) {
    redirect(deckPath(deckId, "No exact copies left to remove."));
  }

  await sql().query(
    `delete from entries where deck_id = $1 and id = any($2::int[])`,
    [deckId, ids],
  );
  await bumpDeckVersion(deckId);

  revalidatePath("/");
  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId));
}

/**
 * Settles one disagreeing word: the chosen row keeps the translation as the
 * admin left it in the field, and every other row for that same word goes.
 * The word itself is read from the database, so the deletion can only ever
 * touch the chosen row's own word inside its own deck.
 */
export async function resolveDuplicate(formData: FormData) {
  await requireAdmin();
  const deckId = Number(field(formData, "deckId"));
  const entryId = Number(field(formData, "entryId"));
  const translation = field(formData, "translation");

  const rows = (await sql()`
    select word from entries where id = ${entryId} and deck_id = ${deckId}
  `) as { word: string }[];
  const kept = rows[0];
  if (!kept) {
    redirect(deckPath(deckId, "That row is no longer in the dictionary."));
  }

  const error = validateEntry(kept.word, translation);
  if (error) redirect(deckPath(deckId, error));

  await sql()`
    update entries set translation = ${translation} where id = ${entryId}
  `;
  await sql()`
    delete from entries
    where deck_id = ${deckId} and word = ${kept.word} and id <> ${entryId}
  `;
  await bumpDeckVersion(deckId);

  revalidatePath("/");
  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId));
}

/** The proposals ticked in the review queue, ignoring anything unparseable. */
function checkedSubmissionIds(formData: FormData): number[] {
  return formData
    .getAll("submissionId")
    .map((value) => Number(value))
    .filter((id) => Number.isInteger(id));
}

/**
 * Accepts the ticked proposals: each joins the dictionary, the version moves
 * once for the batch, and every app that pulls the update gets them.
 */
export async function approveWords(formData: FormData) {
  await requireAdmin();
  const deckId = Number(field(formData, "deckId"));
  const ids = checkedSubmissionIds(formData);
  if (ids.length === 0) {
    redirect(deckPath(deckId, "Tick the words to approve first."));
  }
  const approved = await approveSubmissions(deckId, ids);
  revalidatePath("/");
  revalidatePath(`/decks/${deckId}`);
  redirect(
    deckPath(deckId, undefined, `${approved} ${plural(approved, "word")} added.`),
  );
}

/** Declines the ticked proposals. The dictionary is untouched; each word can be proposed again. */
export async function rejectWords(formData: FormData) {
  await requireAdmin();
  const deckId = Number(field(formData, "deckId"));
  const ids = checkedSubmissionIds(formData);
  if (ids.length === 0) {
    redirect(deckPath(deckId, "Tick the words to reject first."));
  }
  const rejected = await rejectSubmissions(deckId, ids);
  revalidatePath("/");
  revalidatePath(`/decks/${deckId}`);
  redirect(
    deckPath(
      deckId,
      undefined,
      `${rejected} ${plural(rejected, "word")} rejected.`,
    ),
  );
}

/**
 * What the accounts page shows after minting a password. It is returned to the
 * caller rather than redirected to, so a password never lands in a URL, in
 * browser history, or in a server's access log.
 */
export type PasswordResult =
  | { ok: true; username: string; password: string }
  | { ok: false; error: string }
  | null;

/** `admin` or `member` and nothing else, whatever the form happened to post. */
function roleFrom(formData: FormData): string {
  return field(formData, "role") === "admin" ? "admin" : "member";
}

/**
 * Creates an account with a password nobody chose. The admin passes it on and
 * it is never readable again — only its hash is kept — so losing it means
 * resetting it rather than looking it up.
 */
export async function createAccount(
  _previous: PasswordResult,
  formData: FormData,
): Promise<PasswordResult> {
  await requireAdmin();
  const username = field(formData, "username");
  if (!username) return { ok: false, error: "Username is required." };

  const password = generatePassword();
  try {
    await createUser(
      username,
      await hashPassword(password),
      roleFrom(formData),
    );
  } catch (e) {
    return {
      ok: false,
      error:
        e instanceof Error && e.message.includes("users_username_key")
          ? `"${username}" already has an account.`
          : "Could not create the account.",
    };
  }

  revalidatePath("/users");
  return { ok: true, username, password };
}

/**
 * A new password for an account whose own is lost. It does not sign that
 * account out: a token carries a user id and an HMAC, never the password, so
 * the phone keeps working until its token expires.
 */
export async function resetAccountPassword(
  _previous: PasswordResult,
  formData: FormData,
): Promise<PasswordResult> {
  await requireAdmin();
  const account = await getUser(Number(field(formData, "userId")));
  if (!account) return { ok: false, error: "That account no longer exists." };

  const password = generatePassword();
  await setUserPassword(account.id, await hashPassword(password));

  revalidatePath("/users");
  return { ok: true, username: account.username, password };
}

/** The refusals themselves live in accountGuards.ts, where they are testable. */
export async function setAccountRole(formData: FormData) {
  const me = await requireAdmin();
  const role = roleFrom(formData);
  const account = await getUser(Number(field(formData, "userId")));
  if (!account) redirect(usersPath("That account no longer exists."));

  const refusal = refuseRoleChange(me, account, role, await countAdmins());
  if (refusal) redirect(usersPath(refusal));

  await setUserRole(account.id, role);
  revalidatePath("/users");
  redirect(usersPath());
}

/**
 * The account goes; the proposals it sent stay, back to unattributed, because
 * submitted_by is "on delete set null". Its tokens stop working on their next
 * request, since every one of them resolves its user id against the table.
 */
export async function deleteAccount(formData: FormData) {
  const me = await requireAdmin();
  const account = await getUser(Number(field(formData, "userId")));
  if (!account) redirect(usersPath());

  const refusal = refuseDelete(me, account, await countAdmins());
  if (refusal) redirect(usersPath(refusal));

  await deleteUser(account.id);
  revalidatePath("/users");
  redirect(usersPath());
}

/**
 * Appends pasted "word - translation" lines; the spaces around the hyphen mark
 * the split, so either side may contain hyphens. A leading header line matching
 * the deck's own language pair is ignored, so a whole .txt file can be pasted.
 * All-or-nothing: one bad line rejects the whole paste.
 */
export async function importEntries(formData: FormData) {
  await requireAdmin();
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

/** Enough of the skipped lines to fix the source; the rest is a count. */
const PROBLEMS_SHOWN = 5;

function proposalNotice(plan: ProposalPlan, queued: number): string {
  const parts = [`${queued} ${plural(queued, "word")} sent for review`];

  const alreadyWaiting = plan.queued.length - queued;
  if (alreadyWaiting > 0) parts.push(`${alreadyWaiting} already waiting`);
  if (plan.unchanged > 0) {
    parts.push(`${plan.unchanged} already in the dictionary`);
  }

  if (plan.problems.length > 0) {
    const shown = plan.problems
      .slice(0, PROBLEMS_SHOWN)
      .map((problem) => `line ${problem.line} — ${problem.reason}`);
    const rest = plan.problems.length - shown.length;
    if (rest > 0) shown.push(`and ${rest} more`);
    parts.push(`${plan.problems.length} skipped (${shown.join("; ")})`);
  }

  return `${parts.join(" · ")}.`;
}

/**
 * Sends a pasted list to the review queue instead of straight into the
 * dictionary — the path for words a language model wrote, which are worth
 * having and worth reading before they reach anyone's phone.
 *
 * Words the dictionary already carries verbatim are dropped rather than
 * queued: a list generated from the exported .txt repeats plenty of them, and
 * the queue is for decisions. Nothing here moves the version.
 */
export async function proposeEntries(formData: FormData) {
  const admin = await requireAdmin();
  const deckId = Number(field(formData, "deckId"));
  const raw = formData.get("text");
  const text = typeof raw === "string" ? raw : "";

  const deck = await getDeck(deckId);
  if (!deck) redirect("/");

  const plan = planProposals(
    text,
    `${deck.language1}-${deck.language2}`,
    await listEntries(deckId),
  );

  const pasted =
    plan.queued.length + plan.unchanged + plan.problems.length;
  if (pasted === 0) redirect(deckPath(deckId, "Nothing to send for review."));

  const queued =
    plan.queued.length > 0
      ? await insertSubmissions(deckId, plan.queued, admin.id)
      : 0;

  revalidatePath(`/decks/${deckId}`);
  redirect(deckPath(deckId, undefined, proposalNotice(plan, queued)));
}

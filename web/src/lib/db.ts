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

export type UserRow = {
  id: number;
  username: string;
  password_hash: string;
  /** `admin` opens the editor. Anything else is an app-only account. */
  role: string;
};

export type DeckRow = {
  id: number;
  name: string;
  language1: string;
  language2: string;
  version: number;
  entry_count: number;
  /**
   * Distinct words, which is how many cards the app ends up with — it keys a
   * card on the word. Lower than `entry_count` means the dictionary repeats
   * words.
   */
  distinct_count: number;
  pending_count: number;
};

export type LanguageRow = {
  id: number;
  name: string;
  /** Dictionaries using this label on either side. Above zero blocks deletion. */
  deck_count: number;
};

export type EntryRow = {
  id: number;
  word: string;
  translation: string;
  position: number;
};

export type SubmissionRow = {
  id: number;
  word: string;
  translation: string;
  submitted_at: string;
  /** The approved translation this proposal would replace, when the word exists. */
  current_translation: string | null;
  /**
   * Who sent it. Null for proposals made before accounts existed, or whose
   * account has since been deleted.
   */
  proposer: string | null;
};

/** Sign-in reads the stored hash from here and verifies against it. */
export async function findUserByUsername(
  username: string,
): Promise<UserRow | null> {
  const rows = (await sql()`
    select id, username, password_hash, role from users
    where username = ${username}
  `) as UserRow[];
  return rows[0] ?? null;
}

/**
 * Every request resolves its token's user id through here rather than trusting
 * a role carried in the token, so demoting or deleting an account takes effect
 * on the next request instead of when its token expires.
 */
export async function getUser(id: number): Promise<UserRow | null> {
  const rows = (await sql()`
    select id, username, password_hash, role from users where id = ${id}
  `) as UserRow[];
  return rows[0] ?? null;
}

export async function listDecks(): Promise<DeckRow[]> {
  return (await sql()`
    select d.id, d.name, d.language1, d.language2, d.version,
           (select count(*)::int from entries e where e.deck_id = d.id) as entry_count,
           (select count(distinct e.word)::int from entries e
             where e.deck_id = d.id) as distinct_count,
           (select count(*)::int from submissions s
             where s.deck_id = d.id and s.status = 'pending') as pending_count
    from decks d
    order by d.name
  `) as DeckRow[];
}

export async function getDeck(id: number): Promise<DeckRow | null> {
  const rows = (await sql()`
    select d.id, d.name, d.language1, d.language2, d.version,
           (select count(*)::int from entries e where e.deck_id = d.id) as entry_count,
           (select count(distinct e.word)::int from entries e
             where e.deck_id = d.id) as distinct_count,
           (select count(*)::int from submissions s
             where s.deck_id = d.id and s.status = 'pending') as pending_count
    from decks d
    where d.id = ${id}
  `) as DeckRow[];
  return rows[0] ?? null;
}

/** The two language menus and the languages section read the same list. */
export async function listLanguages(): Promise<LanguageRow[]> {
  return (await sql()`
    select l.id, l.name,
           (select count(*)::int from decks d
             where d.language1 = l.name or d.language2 = l.name) as deck_count
    from languages l
    order by l.name
  `) as LanguageRow[];
}

export async function listEntries(deckId: number): Promise<EntryRow[]> {
  return (await sql()`
    select id, word, translation, position
    from entries
    where deck_id = ${deckId}
    order by position, id
  `) as EntryRow[];
}

/**
 * Every approved change to a dictionary's words moves this number, and only
 * this number tells the app there is something new to pull.
 */
export async function bumpDeckVersion(deckId: number): Promise<void> {
  await sql()`update decks set version = version + 1 where id = ${deckId}`;
}

export async function listPendingSubmissions(
  deckId: number,
): Promise<SubmissionRow[]> {
  return (await sql()`
    select s.id, s.word, s.translation, s.submitted_at,
           (select e.translation from entries e
             where e.deck_id = s.deck_id and e.word = s.word
             order by e.position, e.id limit 1) as current_translation,
           u.username as proposer
    from submissions s
    left join users u on u.id = s.submitted_by
    where s.deck_id = ${deckId} and s.status = 'pending'
    order by s.submitted_at, s.id
  `) as SubmissionRow[];
}

/**
 * Stores proposals as pending. Duplicates of a proposal already waiting are
 * dropped by the partial unique index, so the app can re-send freely.
 * Returns how many rows were actually created. Two people proposing the same
 * word for the same dictionary therefore stay one pending row, credited to
 * whoever sent it first.
 */
export async function insertSubmissions(
  deckId: number,
  entries: { word: string; translation: string }[],
  userId: number,
): Promise<number> {
  const rows = (await sql().query(
    `insert into submissions (deck_id, word, translation, submitted_by)
     select $1, w, t, $4 from unnest($2::text[], $3::text[]) as u(w, t)
     on conflict do nothing
     returning id`,
    [
      deckId,
      entries.map((e) => e.word),
      entries.map((e) => e.translation),
      userId,
    ],
  )) as { id: number }[];
  return rows.length;
}

/**
 * Applies a proposal to the dictionary: replaces the translation when the word
 * already exists, appends it otherwise, then bumps the version so the app sees
 * an update. A no-op if the submission is no longer pending.
 */
export async function approveSubmission(
  deckId: number,
  submissionId: number,
): Promise<void> {
  const pending = (await sql()`
    select word, translation from submissions
    where id = ${submissionId} and deck_id = ${deckId} and status = 'pending'
  `) as { word: string; translation: string }[];
  const proposal = pending[0];
  if (!proposal) return;

  const existing = (await sql()`
    select id from entries
    where deck_id = ${deckId} and word = ${proposal.word}
    order by position, id limit 1
  `) as { id: number }[];

  if (existing[0]) {
    await sql()`
      update entries set translation = ${proposal.translation}
      where id = ${existing[0].id}
    `;
  } else {
    await sql()`
      insert into entries (deck_id, word, translation, position)
      values (
        ${deckId}, ${proposal.word}, ${proposal.translation},
        coalesce((select max(position) + 1 from entries where deck_id = ${deckId}), 0)
      )
    `;
  }

  await sql()`
    update submissions set status = 'approved', resolved_at = now()
    where id = ${submissionId}
  `;
  await bumpDeckVersion(deckId);
}

/** Leaves the dictionary untouched; the word can be proposed again later. */
export async function rejectSubmission(
  deckId: number,
  submissionId: number,
): Promise<void> {
  await sql()`
    update submissions set status = 'rejected', resolved_at = now()
    where id = ${submissionId} and deck_id = ${deckId} and status = 'pending'
  `;
}

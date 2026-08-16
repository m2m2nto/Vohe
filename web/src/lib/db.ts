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

export type UserListRow = {
  id: number;
  username: string;
  role: string;
  created_at: string;
  /**
   * Proposals this account has sent. They outlive it: deleting the account
   * sets `submitted_by` back to null rather than removing them.
   */
  proposal_count: number;
};

/** The accounts page. Deliberately never selects `password_hash`. */
export async function listUsers(): Promise<UserListRow[]> {
  return (await sql()`
    select u.id, u.username, u.role, u.created_at,
           (select count(*)::int from submissions s where s.submitted_by = u.id)
             as proposal_count
    from users u
    order by u.username
  `) as UserListRow[];
}

/**
 * Guards the one irreversible mistake this page can make: demoting or deleting
 * the last account that can still open the editor.
 */
export async function countAdmins(): Promise<number> {
  const [{ n }] = (await sql()`
    select count(*)::int as n from users where role = 'admin'
  `) as { n: number }[];
  return n;
}

/** Throws on a duplicate username, which the action turns into a message. */
export async function createUser(
  username: string,
  passwordHash: string,
  role: string,
): Promise<void> {
  await sql()`
    insert into users (username, password_hash, role)
    values (${username}, ${passwordHash}, ${role})
  `;
}

export async function setUserPassword(
  id: number,
  passwordHash: string,
): Promise<void> {
  await sql()`update users set password_hash = ${passwordHash} where id = ${id}`;
}

export async function setUserRole(id: number, role: string): Promise<void> {
  await sql()`update users set role = ${role} where id = ${id}`;
}

/**
 * The account's tokens stop working on their next request, because every one
 * of them resolves its user id against this table rather than trusting itself.
 */
export async function deleteUser(id: number): Promise<void> {
  await sql()`delete from users where id = ${id}`;
}

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
 * Applies proposals to the dictionary: a word already there has its translation
 * replaced, one that is not is appended, and the version is bumped once for the
 * whole batch so the app sees a single update. Ids that are no longer pending
 * are skipped; the count returned is what was actually applied.
 *
 * A hundred approved words is one paste's worth, so this stays a fixed handful
 * of queries rather than three per word.
 */
export async function approveSubmissions(
  deckId: number,
  ids: number[],
): Promise<number> {
  if (ids.length === 0) return 0;

  const pending = (await sql().query(
    `select id, word, translation from submissions
     where deck_id = $1 and id = any($2::int[]) and status = 'pending'
     order by submitted_at, id`,
    [deckId, ids],
  )) as { id: number; word: string; translation: string }[];
  if (pending.length === 0) return 0;

  // Approving two proposals for one word means the dictionary can only end up
  // saying one thing, and it is the later proposal that has the last word.
  const wanted = new Map<string, string>();
  for (const proposal of pending) wanted.set(proposal.word, proposal.translation);

  // The row an approval writes to: the first one carrying that word, in export
  // order, exactly as the editor's own duplicate handling picks it.
  const targets = new Map<string, number>();
  const existing = (await sql().query(
    `select distinct on (word) word, id from entries
     where deck_id = $1 order by word, position, id`,
    [deckId],
  )) as { word: string; id: number }[];
  for (const row of existing) targets.set(row.word, row.id);

  const updates: { id: number; translation: string }[] = [];
  const inserts: { word: string; translation: string }[] = [];
  for (const [word, translation] of wanted) {
    const id = targets.get(word);
    if (id === undefined) inserts.push({ word, translation });
    else updates.push({ id, translation });
  }

  if (updates.length > 0) {
    await sql().query(
      `update entries e set translation = u.translation
       from unnest($1::int[], $2::text[]) as u(id, translation)
       where e.id = u.id`,
      [updates.map((u) => u.id), updates.map((u) => u.translation)],
    );
  }

  if (inserts.length > 0) {
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
        inserts.map((i) => i.word),
        inserts.map((i) => i.translation),
        inserts.map((_, i) => i),
      ],
    );
  }

  await sql().query(
    `update submissions set status = 'approved', resolved_at = now()
     where deck_id = $1 and id = any($2::int[]) and status = 'pending'`,
    [deckId, pending.map((p) => p.id)],
  );
  await bumpDeckVersion(deckId);
  return pending.length;
}

/**
 * Leaves the dictionary untouched, so no version moves; each word can be
 * proposed again later. Returns how many rows were still pending to reject.
 */
export async function rejectSubmissions(
  deckId: number,
  ids: number[],
): Promise<number> {
  if (ids.length === 0) return 0;
  const rejected = (await sql().query(
    `update submissions set status = 'rejected', resolved_at = now()
     where deck_id = $1 and id = any($2::int[]) and status = 'pending'
     returning id`,
    [deckId, ids],
  )) as { id: number }[];
  return rejected.length;
}

create table if not exists decks (
  id serial primary key,
  name text not null unique,
  language1 text not null,
  language2 text not null,
  created_at timestamptz not null default now()
);

create table if not exists entries (
  id serial primary key,
  deck_id integer not null references decks(id) on delete cascade,
  word text not null,
  translation text not null,
  position integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists entries_deck_id_position_idx on entries (deck_id, position, id);

-- Bumped on every approved content change. The iOS app stores the version it
-- last pulled and badges the dictionary when this one is higher.
alter table decks add column if not exists version integer not null default 1;

-- Words sent by the iOS app. They stay out of `entries` — and therefore out of
-- every export and API read — until approved here.
create table if not exists submissions (
  id serial primary key,
  deck_id integer not null references decks(id) on delete cascade,
  word text not null,
  translation text not null,
  status text not null default 'pending',
  submitted_at timestamptz not null default now(),
  resolved_at timestamptz
);

-- Re-sending the same proposal while it waits is a no-op. Once rejected, the
-- same word/translation can be proposed again.
create unique index if not exists submissions_pending_unique
  on submissions (deck_id, word, translation) where status = 'pending';

create index if not exists submissions_deck_status_idx
  on submissions (deck_id, status, submitted_at);

-- The labels a dictionary's front and back may be set to, managed at
-- /languages. Decks keep storing their pair as text, so exports and the API
-- are unaffected. This table only decides what the two menus offer.
-- (No semicolons in these comments: migrate.mjs splits the file on them.)
create table if not exists languages (
  id serial primary key,
  name text not null unique,
  created_at timestamptz not null default now()
);

-- Dictionaries created before the list existed had their labels typed by hand.
-- Adopting them keeps every deck's own pair on the menu.
insert into languages (name)
  select language from (
    select language1 as language from decks
    union
    select language2 from decks
  ) as used
  on conflict (name) do nothing;

-- Named accounts, the one identity for both the editor and the app. The hash
-- is self-describing -- algorithm, iterations and salt -- so its cost can be
-- raised later without a data migration. Only an admin may open the editor.
create table if not exists users (
  id serial primary key,
  username text not null unique,
  password_hash text not null,
  role text not null default 'member',
  created_at timestamptz not null default now()
);

-- Who sent a proposal. Nullable, so every proposal made before accounts
-- existed stays valid and simply shows as unattributed.
alter table submissions add column if not exists submitted_by integer references users(id);

-- Deleting an account must not take its proposals with it, nor be refused
-- because it has any: they stay in the queue and go back to unattributed,
-- which the review queue already renders. Dropped first so re-running this
-- replaces whichever version of the constraint is already there.
alter table submissions drop constraint if exists submissions_submitted_by_fkey;

alter table submissions add constraint submissions_submitted_by_fkey
  foreign key (submitted_by) references users(id) on delete set null;

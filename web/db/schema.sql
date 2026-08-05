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

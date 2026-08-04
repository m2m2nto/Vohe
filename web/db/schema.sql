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

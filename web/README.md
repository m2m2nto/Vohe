# Vohe Dictionaries — web editor and backend

A small Next.js app behind named accounts that stores Vohe dictionaries in
Postgres, exports each one as a `.txt` file in exactly the format
[`DeckParser.swift`](../Vohe/Services/DeckParser.swift) imports, and serves them
to the iOS app over a JSON API the app signs in to.

Two ways to get words onto the phone: download the `.txt` and import it with the
**+** button, or point the app at this server and pull dictionaries directly.
Words added on the phone come back here as **proposals** and join the dictionary
only once you approve them.

```
src/lib/deckFormat.ts   mirror of DeckParser.swift (parse, serialize, validate)
src/lib/duplicates.ts   groups repeated words into "identical" and "needs review"
src/lib/auth.ts         password hashing + HMAC-signed session tokens (no database)
src/lib/session.ts      turns a token into the account that sent it
src/lib/accountGuards.ts  refuses the moves that would leave the editor adminless
src/lib/api.ts          JSON API shapes and submission validation
src/lib/db.ts           Neon Postgres queries
src/proxy.ts            locks every route except /login and /api
src/app/SubmitButton.tsx submit button that locks and spins while its action runs
src/app/page.tsx        dictionary list + create
src/app/languages/      the language labels the two menus offer
src/app/users/          accounts: create with a generated password, reset, delete
src/app/decks/[id]/     word editor, review queue, paste-import, settings, delete
src/app/decks/[id]/export/route.ts   the .txt download
src/app/api/decks/                   catalog, one dictionary, submissions
db/schema.sql           decks + entries + submissions + languages + users
scripts/migrate.mjs     applies schema.sql
scripts/seed.mjs        imports ../samples/*.txt
scripts/create-user.mjs creates an account or changes its password
tests/deckFormat.test.ts   format round-trip against the real sample files
tests/duplicates.test.ts   repeated-word grouping, incl. the real sample's counts
tests/auth.test.ts         password hashing + session tokens + generated passwords
tests/accountGuards.test.ts  no allowed move leaves the editor without an admin
tests/api.test.ts          submission validation
```

## One-time setup

### 1. Database

In the Vercel dashboard → **Storage** → **Create Database** → **Neon Postgres**,
attach it to this project. Vercel injects `DATABASE_URL` into the deployment.

### 2. Environment variables

Set these in Vercel → **Settings** → **Environment Variables** (all
environments), and copy `.env.example` to `.env.local` for local work:

| Variable       | What it is                                                     |
| -------------- | -------------------------------------------------------------- |
| `DATABASE_URL` | Neon connection string (auto-set by Vercel)                     |
| `AUTH_SECRET`  | random 32-byte hex, signs every session token — browser and app |

```sh
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Changing `AUTH_SECRET` signs everyone out: existing tokens stop verifying, so
the editor asks for a password again and each phone has to sign in again.

### 3. Vercel project root

This repo's root is an Xcode project, so point Vercel at this folder:
**Settings** → **Build and Deployment** → **Root Directory** → `web`.

### 4. Create the tables and load the samples

With `.env.local` filled in (use the same `DATABASE_URL` as production, or a
separate Neon branch):

```sh
npm install
npm run db:migrate   # creates the tables, adds decks.version and the language list
npm run db:seed      # imports every ../samples/*.txt, skipping decks that exist
```

`db:migrate` is idempotent and additive — re-run it after pulling changes that
touch `db/schema.sql`.

### 5. Create your first account

There is no signup page. The first admin has to come from the command line,
because there is nobody yet who could sign in and make one:

```sh
npm run user:create -- <username> '<password>' --admin
```

After that, use **Accounts** in the editor's header. It creates accounts with a
generated password shown once, resets a password the same way, switches an
account between admin and member, and deletes one. It refuses any move that
would leave no admin — you cannot delete or demote your own account, or the
last admin — because an editor with no admin cannot be repaired from the editor.

Deleting an account leaves the words it proposed in the review queue, with no
name against them.

`user:create` stays as the way back in: it needs `DATABASE_URL` and nothing
else, so it still works when nobody can sign in. Re-running it for an existing
username changes that account's password **and its role**, so pass `--admin`
again unless you mean to demote it.

## Daily use

```sh
npm run dev          # http://localhost:3000
npm test             # format round-trip tests, no database needed
npm run build        # what Vercel runs
```

1. Sign in with your username and password.
2. Pick a dictionary, or create one (name + the two languages, chosen from the
   menus **Languages** fills — see below).
3. Add words one at a time, or paste a whole list into **Paste a list**.
4. Approve or reject anything sitting in **From the app — waiting for review**.
5. Settle anything in **Repeated words** (see below).
6. **download .txt** → open it in Vohe via **+**, or just let the phone pull the
   new version.

## Languages

A dictionary's front and back are picked from a list the admin keeps in
**Languages** (linked from the header), not typed per dictionary, so the same
language is spelled the same way everywhere and the exported header line stays
valid. The rules are checked once, when a language is added: no hyphen, no
leading `#`, no line break.

Adding is free-form; deleting is refused while any dictionary is set to that
language, and the list says how many use it. There is no rename — renaming would
silently rewrite the header of every dictionary using it. To retire a label,
point the dictionaries at another one first, then delete it.

`db:migrate` seeds the list from the languages already in use, so existing
dictionaries keep their pair, and `db:seed` adds whatever its sample files name.

## Repeated words

The app keys a card on the word, so a dictionary carrying the same word twice
becomes one card, not two — a 757-word dictionary imports as 637 cards. Nothing
here rejects a repeat, because the second row often holds the better
translation; instead the deck page lists them under **Repeated words**, and the
header and dictionary list show both numbers (`757 words · 637 cards on the
phone`).

Two kinds, handled differently:

- **identical copies** — same word, same translation. One button clears the
  extras and keeps the earliest. Nothing is lost and the phone sees no change,
  since it was already ignoring those rows.
- **rows that disagree** — same word, different translations. These are listed
  one word at a time with every competing translation in an editable field.
  **Keep this one** makes that row the survivor and deletes the other copies of
  that word, so you can also merge by hand first (`mese` + `mese/luna` →
  `mese/luna`). Only the last row of a disagreeing word currently reaches the
  phone, so leaving these unresolved means the phone keeps whichever the export
  happens to end on.

Both bump the dictionary version, so the phone offers the update.

Signing in on the iPhone works the same way: open the site in Safari, sign in,
tap **download .txt**, then import from Files.

## The app's API

The app signs in once and then sends the token it gets back as
`Authorization: Bearer <token>`; without a valid one every route answers `401`.
These are the only routes not behind the session cookie. A token minted for the
app is not accepted as a browser session, and vice versa.

| Route | What it does |
| ----- | ------------ |
| `POST /api/session` | `{"username","password"}` → `{"token"}`, valid for a year. The only route needing no header |
| `GET /api/decks` | catalog: `id`, `name`, languages, `version`, `wordCount` |
| `GET /api/decks/:id` | one dictionary with every approved word |
| `POST /api/decks/:id/submissions` | `{"entries":[{"word","translation"}]}` → review queue, credited to the account that sent it |

`version` starts at 1 and increases on every approved change to a dictionary —
adding, editing or deleting a word, approving a proposal, or renaming it. The app
stores the version it pulled and badges the deck when the catalog shows a higher
one; the user chooses when to take the update.

Submissions never touch `entries`, so they appear in no export, no API read, and
no other device until approved here. Re-sending a proposal that is still waiting
is a no-op; once rejected, the same word can be proposed again.

```sh
TOKEN=$(curl -s -X POST https://your-app.vercel.app/api/session \
  -H 'content-type: application/json' \
  -d '{"username":"you","password":"…"}' | jq -r .token)
curl -H "Authorization: Bearer $TOKEN" https://your-app.vercel.app/api/decks
```

## Format rules the editor enforces

Because the app splits each line on the first **spaced** hyphen ` - ` (falling
back to the first bare `-` when there is none):

- both sides may contain `-` (`così-così - tako-tako`);
- the word side may not contain ` - `, which is the separator itself;
- neither language label may contain `-`, since the header line has no spaces;
- nothing may start with `#` (comment) or be empty.

Pasted text is rejected as a whole if any line breaks these rules, so a bad
paste never half-imports.

## Moving a running deployment onto accounts

One-time, and the order is what matters: the schema is additive and the old code
ignores it, so the database can be prepared while production still serves the old
build — but deploying the new build before an admin account exists locks the
editor against its own owner.

1. `npm run db:migrate` against production — adds `users` and
   `submissions.submitted_by`, changing nothing the running build reads.
2. `npm run user:create -- <username> '<password>' --admin` against production.
3. Confirm the row is there (`select username, role from users`).
   **Do not start step 4 until steps 1 and 2 are done.**
4. Deploy the new build — web and API move to accounts together.
5. Sign in to the editor with the username and password from step 2.
6. Install the matching app build and sign in on the phone; pull a dictionary.
7. Delete `API_TOKEN` and `ADMIN_PASSWORD` from the Vercel environment. Nothing
   should break — no code path reads them any more.

The app build from before this change authenticates with the old `API_TOKEN`, so
it stops working at step 4 and starts again at step 6. Ship both together.

**If you lock yourself out anyway:** `create-user.mjs` needs only
`DATABASE_URL`, so run step 2 from your machine against the production database
and sign in again. To roll back instead, revert the deployment and restore the
two environment variables — the old build reads neither new column, and nothing
was deleted from the database.

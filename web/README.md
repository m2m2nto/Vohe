# Vohe Dictionaries — web editor and backend

A small password-protected Next.js app that stores Vohe dictionaries in Postgres,
exports each one as a `.txt` file in exactly the format
[`DeckParser.swift`](../Vohe/Services/DeckParser.swift) imports, and serves them
to the iOS app over a token-authenticated JSON API.

Two ways to get words onto the phone: download the `.txt` and import it with the
**+** button, or point the app at this server and pull dictionaries directly.
Words added on the phone come back here as **proposals** and join the dictionary
only once you approve them.

```
src/lib/deckFormat.ts   mirror of DeckParser.swift (parse, serialize, validate)
src/lib/duplicates.ts   groups repeated words into "identical" and "needs review"
src/lib/auth.ts         password session cookie (HMAC-signed) + API bearer token
src/lib/api.ts          JSON API shapes and submission validation
src/lib/db.ts           Neon Postgres queries
src/proxy.ts            locks every route except /login and /api
src/app/SubmitButton.tsx submit button that locks and spins while its action runs
src/app/page.tsx        dictionary list + create
src/app/decks/[id]/     word editor, review queue, paste-import, settings, delete
src/app/decks/[id]/export/route.ts   the .txt download
src/app/api/decks/                   catalog, one dictionary, submissions
db/schema.sql           decks + entries + submissions
scripts/migrate.mjs     applies schema.sql
scripts/seed.mjs        imports ../samples/*.txt
tests/deckFormat.test.ts   format round-trip against the real sample files
tests/duplicates.test.ts   repeated-word grouping, incl. the real sample's counts
tests/api.test.ts          token check + submission validation
```

## One-time setup

### 1. Database

In the Vercel dashboard → **Storage** → **Create Database** → **Neon Postgres**,
attach it to this project. Vercel injects `DATABASE_URL` into the deployment.

### 2. Environment variables

Set these in Vercel → **Settings** → **Environment Variables** (all
environments), and copy `.env.example` to `.env.local` for local work:

| Variable         | What it is                                        |
| ---------------- | ------------------------------------------------- |
| `DATABASE_URL`   | Neon connection string (auto-set by Vercel)       |
| `ADMIN_PASSWORD` | the password that unlocks the editor              |
| `AUTH_SECRET`    | random 32-byte hex, signs the session cookie      |
| `API_TOKEN`      | random 32-byte hex, what the iOS app sends to `/api/*` |

```sh
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

### 3. Vercel project root

This repo's root is an Xcode project, so point Vercel at this folder:
**Settings** → **Build and Deployment** → **Root Directory** → `web`.

### 4. Create the tables and load the samples

With `.env.local` filled in (use the same `DATABASE_URL` as production, or a
separate Neon branch):

```sh
npm install
npm run db:migrate   # creates decks + entries + submissions, adds decks.version
npm run db:seed      # imports every ../samples/*.txt, skipping decks that exist
```

`db:migrate` is idempotent and additive — re-run it after pulling changes that
touch `db/schema.sql`.

## Daily use

```sh
npm run dev          # http://localhost:3000
npm test             # format round-trip tests, no database needed
npm run build        # what Vercel runs
```

1. Sign in with `ADMIN_PASSWORD`.
2. Pick a dictionary, or create one (name + the two language labels).
3. Add words one at a time, or paste a whole list into **Paste a list**.
4. Approve or reject anything sitting in **From the app — waiting for review**.
5. Settle anything in **Repeated words** (see below).
6. **download .txt** → open it in Vohe via **+**, or just let the phone pull the
   new version.

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

Every route needs `Authorization: Bearer $API_TOKEN`; without a valid token they
answer `401`. They are the only routes not behind the password cookie.

| Route | What it does |
| ----- | ------------ |
| `GET /api/decks` | catalog: `id`, `name`, languages, `version`, `wordCount` |
| `GET /api/decks/:id` | one dictionary with every approved word |
| `POST /api/decks/:id/submissions` | `{"entries":[{"word","translation"}]}` → review queue |

`version` starts at 1 and increases on every approved change to a dictionary —
adding, editing or deleting a word, approving a proposal, or renaming it. The app
stores the version it pulled and badges the deck when the catalog shows a higher
one; the user chooses when to take the update.

Submissions never touch `entries`, so they appear in no export, no API read, and
no other device until approved here. Re-sending a proposal that is still waiting
is a no-op; once rejected, the same word can be proposed again.

```sh
curl -H "Authorization: Bearer $API_TOKEN" https://your-app.vercel.app/api/decks
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

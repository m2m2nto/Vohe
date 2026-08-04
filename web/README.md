# Vohe Dictionaries — web editor

A small password-protected Next.js app that stores Vohe dictionaries in Postgres
and exports each one as a `.txt` file in exactly the format
[`DeckParser.swift`](../Vohe/Services/DeckParser.swift) imports.

The iOS app is untouched: you edit words here, download the `.txt`, and import
it in Vohe with the **+** button as before.

```
src/lib/deckFormat.ts   mirror of DeckParser.swift (parse, serialize, validate)
src/lib/auth.ts         single-password session cookie (HMAC-signed)
src/lib/db.ts           Neon Postgres queries
src/middleware.ts       locks every route except /login
src/app/page.tsx        dictionary list + create
src/app/decks/[id]/     word editor, paste-import, settings, delete
src/app/decks/[id]/export/route.ts   the .txt download
db/schema.sql           decks + entries
scripts/migrate.mjs     applies schema.sql
scripts/seed.mjs        imports ../samples/*.txt
tests/deckFormat.test.ts   format round-trip against the real sample files
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
npm run db:migrate   # creates decks + entries
npm run db:seed      # imports every ../samples/*.txt, skipping decks that exist
```

## Daily use

```sh
npm run dev          # http://localhost:3000
npm test             # format round-trip tests, no database needed
npm run build        # what Vercel runs
```

1. Sign in with `ADMIN_PASSWORD`.
2. Pick a dictionary, or create one (name + the two language labels).
3. Add words one at a time, or paste a whole list into **Paste a list**.
4. **download .txt** → open it in Vohe via **+**.

Signing in on the iPhone works the same way: open the site in Safari, sign in,
tap **download .txt**, then import from Files.

## Format rules the editor enforces

Because the app splits each line on the **first** hyphen:

- the word side may not contain `-` (the translation side may: `cane - pas-tu`);
- neither language label may contain `-`;
- nothing may start with `#` (comment) or be empty.

Pasted text is rejected as a whole if any line breaks these rules, so a bad
paste never half-imports.

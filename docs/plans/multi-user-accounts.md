# Implementation Plan: Multi-User Accounts (Workstream A)

## Overview

Replace the two parallel single-secret auth systems — `ADMIN_PASSWORD` for the browser, `API_TOKEN` for the iOS app — with named user accounts held in Postgres. One signed token format serves both surfaces. Proposals become attributable to the user who sent them.

Accounts are a **server-side identity only**. Decks, cards, boxes, due dates, session history and `difficulty.json` stay exactly where they are: on the device. Nothing in `DictionarySync`, `LeitnerScheduler`, `DifficultyStore` or any `@Model` is touched by this work.

**Explicitly out of scope** (workstream B and later): CloudKit sync of practice data, per-user practice data on the server, passkeys, self-service signup, self-service password reset, in-app account deletion. Passkeys are deliberately deferred rather than designed around — they attach to a `users` row as a second credential type, so nothing here blocks them.

## Success Criteria

1. `npm run db:migrate` creates `users` and adds `submissions.submitted_by`, and is still safely re-runnable.
2. A password verifies against its own hash and fails against any other; the stored hash is self-describing (algorithm, iterations, salt) so parameters can be raised later without a data migration.
3. A session token names its user; a token with any byte altered is rejected; a token past its max age is rejected.
4. A token minted for the app is rejected by the browser session check, and vice versa.
5. Signing in to the web editor requires a username and a password, and only a user with `role = 'admin'` reaches any editor page.
6. `POST /api/session` returns a token for correct credentials and 401 for anything else.
7. Every route under `/api` accepts a valid user token and rejects a missing, malformed, expired or wrong-audience one.
8. A proposal sent from the app records which user sent it, and the review queue shows that name.
9. The iOS app signs in with username and password, stores only the returned token in the keychain, and never asks for a 64-character token again.
10. A 401 from any backend call leaves the app usable offline and tells the user to sign in again.
11. `API_TOKEN` appears nowhere in the codebase or the README when the work is done.
12. No regression: with the server unreachable or not configured, the app behaves exactly as the on-device app in `SPEC.md`.

## Architecture Decisions

- **One token format, two audiences.** `<audience>.<userId>.<issuedAt>.<mac>`, where `mac = HMAC-SHA256(AUTH_SECRET, "<audience>.<userId>.<issuedAt>")` — the same `sign()` that signs today's cookie. `audience` is `web` or `app`. It exists to give the two surfaces different lifetimes (30 days for the browser, as today; 365 days for the app, because re-typing a password on a phone is the friction this whole workstream is meant to remove) and to stop a long-lived app token being replayed as a browser session. Everything else about the token is unchanged from the current cookie design.
- **`auth.ts` stays database-free.** Its header comment — "Web Crypto only, so this also runs in middleware" — is load-bearing: `proxy.ts` imports it on every request. Resolving a token to a user row needs the database, so that lives in a new `src/lib/session.ts` which imports both. `proxy.ts` keeps doing signature, expiry and audience only, with no query.
- **The web editor is admin-only.** Members exist to use the app; they have no reason to open the editor, and giving them a read-only view is unrequested surface. `proxy.ts` bounces the signed-out to `/login`; pages and actions additionally require `role = 'admin'`.
- **Role is checked against the database, not read from the token.** A token carries a user id and nothing else, so demoting or deleting a user takes effect on their next request instead of when their token expires. Pages and actions already query the database, so this is free.
- **PBKDF2-HMAC-SHA256 via Web Crypto, 600,000 iterations, 16-byte random salt.** No new dependency, and it keeps `auth.ts` runnable anywhere. Stored as `pbkdf2$sha256$<iterations>$<saltHex>$<hashHex>`. Derivation runs only in the two sign-in paths, never per-request.
- **Admin creates accounts from the command line.** No signup page, no email, no reset flow, no rate-limiting question to answer. `scripts/create-user.mjs` is the whole user-management story for v1; resetting a password means re-running it.
- **One pending proposal per word stays one pending proposal.** `submissions_pending_unique` is unchanged, so if two users propose the same word for the same dictionary, the second call still reports `alreadyPending` and `submitted_by` records the first sender. This is the existing behavior and the right one; it is called out so it is not mistaken for a bug later.

## Task List

### Phase 1: Foundation (no user-visible change)

#### Task 1: `users` table and proposal attribution

**Description:** Additive schema only. Existing rows keep working: `submitted_by` is nullable, so every proposal already in the queue stays valid and displays as an unattributed proposal.

**Acceptance criteria:**
- [ ] `db/schema.sql` adds `users (id serial pk, username text not null unique, password_hash text not null, role text not null default 'member', created_at timestamptz not null default now())`.
- [ ] `db/schema.sql` adds `submissions.submitted_by integer references users(id)`, nullable, via `alter table ... add column if not exists`.
- [ ] No statement in the added SQL, **including its comments**, contains a semicolon — `migrate.mjs` splits the file on `;`. (schema.sql already warns about this.)
- [ ] Every added statement is `if not exists` / `add column if not exists`. (**Success criterion 1**)

**Verification:**
- [ ] `npm run db:migrate` against a local Neon branch succeeds; run it a second time and confirm it succeeds again with no error.
- [ ] `select * from submissions` still returns the pre-existing rows.

**Dependencies:** None.

**Files likely touched:** `web/db/schema.sql`.

**Scope:** XS.

---

#### Task 2: Password hashing in `auth.ts`

**Description:** `hashPassword(plain)` and `verifyPassword(plain, stored)`, PBKDF2 via Web Crypto. Reuse the existing `constantTimeEqual`. No imports beyond what the file already has.

**Acceptance criteria:**
- [ ] `hashPassword` returns `pbkdf2$sha256$600000$<saltHex>$<hashHex>` with a fresh 16-byte random salt each call.
- [ ] The same password hashed twice yields two different strings, and each verifies. (**Success criterion 2**)
- [ ] `verifyPassword` reads the iteration count and salt out of the stored string rather than assuming today's constants. (**Success criterion 2**)
- [ ] `verifyPassword` returns false — never throws — for a malformed or empty stored hash.
- [ ] The final comparison is constant-time.

**Verification:**
- [ ] New `web/tests/auth.test.ts`: round-trip, wrong password, two hashes of one password differ, malformed stored hash, a hash string with a lower iteration count still verifies.
- [ ] `npm test` passes (no database needed, matching the existing tests).
- [ ] Log the wall-clock cost of one `hashPassword` call in the test run; if it exceeds ~1s, drop to 300,000 iterations and note it in the plan.

**Dependencies:** None.

**Files likely touched:** `web/src/lib/auth.ts`, `web/tests/auth.test.ts` (new).

**Scope:** S.

---

#### Task 3: User-scoped session tokens

**Description:** Widen the token from `<issuedAt>.<mac>` to `<audience>.<userId>.<issuedAt>.<mac>`. This replaces `createSessionCookie` / `isValidSessionCookie` rather than adding alongside them — there is one deployment, one user, and no old token worth honouring.

**Acceptance criteria:**
- [ ] `createToken(audience, userId, issuedAtMs)` and `readToken(value, nowMs)` replace the two cookie functions; `readToken` returns `{ audience, userId }` or null.
- [ ] Max age is 30 days for `web` and 365 days for `app`, enforced inside `readToken`.
- [ ] A token whose mac, user id, issued-at or audience has been altered is rejected. (**Success criterion 3**)
- [ ] A token whose issued-at is in the future is rejected (the existing `ageSeconds >= 0` guard is preserved).
- [ ] `isCorrectPassword` and `isValidApiToken` are deleted. (**Success criterion 11**)

**Verification:**
- [ ] `web/tests/auth.test.ts` covers: round-trip per audience, tampered mac, tampered user id, expired at each max age, future issued-at, a `web` token read while expecting `app` and vice versa (**Success criterion 4**), garbage input.
- [ ] `npm test` passes.

**Dependencies:** None (can run parallel with Task 2).

**Files likely touched:** `web/src/lib/auth.ts`, `web/tests/auth.test.ts`, `web/tests/api.test.ts` (its `isValidApiToken` block is removed).

**Scope:** S.

---

#### Task 4: `create-user.mjs`

**Description:** The entire account-management surface. Creates a user, or updates the password of an existing one.

**Acceptance criteria:**
- [ ] `npm run user:create -- <username> <password> [--admin]` inserts the user with a hashed password and the right role.
- [ ] Re-running it for an existing username updates that user's password and role instead of failing.
- [ ] The script needs `DATABASE_URL` only — never `AUTH_SECRET`, since hashing doesn't sign anything.
- [ ] The `user:create` npm script passes `--experimental-strip-types` (it imports `src/lib/auth.ts`, as `seed.mjs` does) and `--env-file-if-exists=.env.local`.
- [ ] The plaintext password is never echoed back to the terminal.

**Verification:**
- [ ] Create an admin locally; `select username, role from users` shows the row.
- [ ] Re-run with a different password; verify the hash changed and `verifyPassword` accepts the new one and rejects the old.

**Dependencies:** Tasks 1, 2.

**Files likely touched:** `web/scripts/create-user.mjs` (new), `web/package.json`.

**Scope:** S.

---

### Checkpoint: Foundation

- [ ] `npm test` passes; `npm run db:migrate` is idempotent; an admin user exists in the local database.
- [ ] `npm run dev` still serves the editor unchanged — nothing user-facing has moved yet.

---

### Phase 2: The web editor moves to accounts

#### Task 5: User queries and `currentUser()`

**Description:** `db.ts` gains the two queries; a new `src/lib/session.ts` joins token-reading to the database. `auth.ts` gains no database import.

**Acceptance criteria:**
- [ ] `db.ts` exports `UserRow`, `findUserByUsername(username)` and `getUser(id)`.
- [ ] `src/lib/session.ts` exports `currentUser()` (reads the cookie, `web` audience) and `apiUser(request)` (reads the `Authorization` header, `app` audience), both returning `UserRow | null`.
- [ ] `src/lib/auth.ts` imports nothing from `db.ts`, and `proxy.ts` imports nothing from `db.ts` or `session.ts`.
- [ ] A token naming a user id that no longer exists resolves to null.

**Verification:**
- [ ] `grep -n "db" web/src/lib/auth.ts web/src/proxy.ts` returns no import of the database module.
- [ ] `npm run build` succeeds — a database import leaking into the proxy would surface here.

**Dependencies:** Tasks 1, 3.

**Files likely touched:** `web/src/lib/db.ts`, `web/src/lib/session.ts` (new).

**Scope:** S.

---

#### Task 6: Username + password sign-in for the editor

**Description:** `/login` gains a username field; the `login` action looks the user up, verifies the password, and mints a `web` token. `proxy.ts` verifies audience `web`. Admin-only enforcement lands in the pages and actions.

**Acceptance criteria:**
- [ ] `/login` posts `username` and `password`; a wrong username and a wrong password produce the same "Wrong username or password." message and the same response time path (both run `verifyPassword` — hash a dummy when the user is missing, so the failure isn't distinguishable by timing).
- [ ] The cookie keeps its current flags (`httpOnly`, `sameSite: lax`, `secure` in production) and carries the new token.
- [ ] `proxy.ts` redirects to `/login` unless the cookie holds a valid `web` token. (**Success criterion 4**)
- [ ] Every editor page and every server action in `actions.ts` that mutates data requires `role = 'admin'`; a signed-in member is shown a plain "This account can't use the editor." page rather than a redirect loop. (**Success criterion 5**)
- [ ] `ADMIN_PASSWORD` is gone from the codebase.

**Verification:**
- [ ] Manual: sign in as the admin → dictionary list. Sign out (clear the cookie) → any URL redirects to `/login`.
- [ ] Manual: create a member with `create-user.mjs`, sign in as them → refused; confirm no editor action succeeds by posting one directly.
- [ ] Manual: wrong password → error, no cookie set.
- [ ] `npm run build` succeeds.

**Dependencies:** Tasks 4, 5.

**Files likely touched:** `web/src/app/login/page.tsx`, `web/src/app/actions.ts`, `web/src/proxy.ts`, `web/src/app/page.tsx`, `web/src/app/languages/page.tsx`, `web/src/app/decks/[id]/page.tsx`.

**Scope:** M.

---

### Checkpoint: Editor

- [ ] The editor is reachable only by an admin signing in with a username and a password.
- [ ] `/api/*` is untouched and still answers the old `API_TOKEN` — the app keeps working while Phase 3 is built.

---

### Phase 3: The API moves to accounts

#### Task 7: `POST /api/session`

**Description:** The app's sign-in endpoint. Lives under `/api`, which `proxy.ts` already exempts, so no routing change.

**Acceptance criteria:**
- [ ] `{ "username": ..., "password": ... }` → `200 { "token": ... }` with an `app` token. (**Success criterion 6**)
- [ ] Anything else → `401` via the existing `jsonError` shape, with the same message for unknown user and wrong password.
- [ ] Non-JSON or missing fields → `400`, matching how `submissions/route.ts` handles a bad body.
- [ ] The route does not require an `Authorization` header.

**Verification:**
- [ ] `curl` with correct credentials returns a token; that token opens `GET /api/decks`.
- [ ] `curl` with a wrong password returns 401 and no token.
- [ ] `curl` with `{}` returns 400.

**Dependencies:** Task 5.

**Files likely touched:** `web/src/app/api/session/route.ts` (new).

**Scope:** S.

---

#### Task 8: API routes authenticate a user; proposals get an author

**Description:** Swap `isValidApiToken` for `apiUser(request)` in all three API routes, thread the user id into `insertSubmissions`, and show the name in the review queue.

**Acceptance criteria:**
- [ ] `/api/decks`, `/api/decks/[id]` and `/api/decks/[id]/submissions` return `UNAUTHORIZED()` unless `apiUser` resolves a user. (**Success criterion 7**)
- [ ] `insertSubmissions(deckId, entries, userId)` writes `submitted_by`. (**Success criterion 8**)
- [ ] `SubmissionRow` gains the proposer's username; the review queue in `decks/[id]/page.tsx` shows it, and renders proposals with a null `submitted_by` without breaking. (**Success criterion 8**)
- [ ] The submission response shape (`accepted` / `alreadyPending` / `invalid`) is unchanged, so `SubmissionReceipt` in the app still decodes.

**Verification:**
- [ ] `curl` each route with: no header, `Bearer garbage`, a `web` token, a valid `app` token — first three 401, last one 200.
- [ ] Send a proposal with a user's token; the review queue shows that username next to it.
- [ ] `npm test` passes (the `api.test.ts` submission-parsing tests are unaffected).

**Dependencies:** Tasks 5, 7.

**Files likely touched:** `web/src/app/api/decks/route.ts`, `web/src/app/api/decks/[id]/route.ts`, `web/src/app/api/decks/[id]/submissions/route.ts`, `web/src/lib/db.ts`, `web/src/app/decks/[id]/page.tsx`.

**Scope:** M.

---

### Checkpoint: API

- [ ] The old `API_TOKEN` no longer opens anything; a signed-in user's token opens everything the app needs.
- [ ] The iOS app is now broken against this backend, and stays broken until Phase 4 ships. Do not deploy Phases 2–3 to production before Phase 4 is ready — see the runbook in Task 12.

---

### Phase 4: The app signs in

#### Task 9: `BackendSettings` holds a username; `BackendClient` can sign in

**Description:** The keychain slot keeps holding a token — it is just now a session token instead of a shared secret, so the keychain code is unchanged. The username is a preference alongside the address.

**Acceptance criteria:**
- [ ] `BackendSettings` gains `username: String`, persisted in `UserDefaults` next to `address`; `token` keeps its keychain slot and its `edited` semantics.
- [ ] `BackendClient.signIn(username:password:)` posts to `/api/session` without an `Authorization` header and returns the token; a 401 surfaces as `BackendError.unauthorized`.
- [ ] `isConfigured` still means "address and token present", so `catalog`, `dictionary` and `submit` are untouched. (**Success criterion 12**)
- [ ] `BackendError.unauthorized`'s message becomes a sign-in prompt rather than "the server rejected the access token".

**Verification:**
- [ ] Build clean.
- [ ] Unit test in `VoheTests` for the settings round-trip (username persisted, token still keychain-backed, clearing stays cleared).

**Dependencies:** Task 7.

**Files likely touched:** `Vohe/Services/BackendSettings.swift`, `Vohe/Services/BackendClient.swift`, `VoheTests/BackendSettingsTests.swift` (new or extended).

**Scope:** S.

---

#### Task 10: `BackendSettingsSheet` becomes a sign-in form

**Description:** Address, username, password, "Sign in". The password is never persisted — only the token that comes back. "Test connection" becomes redundant with a sign-in that reports its own result; it is replaced rather than kept alongside.

**Acceptance criteria:**
- [ ] The token `SecureField` is gone; the sheet shows address, username, and a password `SecureField`. (**Success criterion 9**)
- [ ] "Sign in" is disabled until address, username and password are all non-empty, and shows a spinner while the call is in flight.
- [ ] Success saves address, username and token, reports "Signed in as <username>", and dismisses.
- [ ] Failure leaves everything as it was and shows the error, distinguishing unreachable from rejected credentials.
- [ ] When a token is already stored, the sheet shows who is signed in and offers "Sign out", which clears the keychain token and leaves address and username in place.
- [ ] The password is held only in `@State` for the life of the sheet.

**Verification:**
- [ ] Manual on device: sign in, pull a dictionary, send a word for review, confirm it appears in the review queue attributed to that user. (**Success criteria 8, 9**)
- [ ] Manual: sign in with a wrong password → error, no token stored, app still usable offline.
- [ ] Manual: sign out → the dictionary browser reports it needs a sign-in; Library, sessions, import and export all still work. (**Success criteria 10, 12**)
- [ ] Manual: point the app at an unreachable address → "can't reach" wording, not "sign in again".

**Dependencies:** Task 9.

**Files likely touched:** `Vohe/Views/BackendSettingsSheet.swift`, `Vohe/Views/RemoteDictionariesView.swift` (only where it surfaces `BackendError.unauthorized`).

**Scope:** M.

---

#### Task 11: Retire the build-time token

**Description:** `BackendDefaults` exists so a fresh install doesn't have to type a 64-character token. With a username and a password there is nothing long to type, so the token default has no reason to exist.

**Acceptance criteria:**
- [ ] `BackendDefaults.token` is removed from the template; `address` stays.
- [ ] `BackendSettings.load()` no longer reads a default token.
- [ ] The template's comments describe the new setup.

**Verification:**
- [ ] Build clean with the real (gitignored) `BackendDefaults.swift` reduced to an address. **Hand off to the user:** that file is local and user-maintained; I'll update the `.template` and say what to change in the copy.

**Dependencies:** Task 10.

**Files likely touched:** `Vohe/Services/BackendDefaults.swift.template`, `Vohe/Services/BackendSettings.swift`.

**Scope:** XS.

---

### Checkpoint: App

- [ ] `xcodebuild build` and `xcodebuild test` pass.
- [ ] A full round trip works on a device against a locally-run backend: sign in → browse → pull → propose → approve in the editor → update in the app.

---

### Phase 5: Cutover

#### Task 12: Production rollout

**Description:** The order matters. The new schema is additive and the old code ignores it, so the database can be prepared while production still runs the old build — but deploying the web change before an admin exists locks the editor against its own owner.

**Acceptance criteria:**
- [ ] Runbook recorded in `web/README.md`, in this order: (1) `npm run db:migrate` against production, (2) `npm run user:create` for the admin against production, (3) verify the row exists, (4) deploy, (5) sign in to the editor, (6) install the app build and sign in, (7) delete `API_TOKEN` and `ADMIN_PASSWORD` from the Vercel environment.
- [ ] Steps 1 and 2 are confirmed done before step 4 is started.

**Verification:**
- [ ] Manual, following the runbook. After step 5, the editor opens. After step 6, the app pulls a dictionary. After step 7, nothing breaks — confirming no code path still reads the old variables.

**Dependencies:** All previous tasks.

**Files likely touched:** `web/README.md`.

**Scope:** S.

---

#### Task 13: Documentation

**Acceptance criteria:**
- [ ] `web/README.md`: the environment table drops `API_TOKEN` and `ADMIN_PASSWORD`, keeps `DATABASE_URL` and `AUTH_SECRET`, and gains the account-creation step; the file map gains `src/lib/session.ts` and `scripts/create-user.mjs`; the `src/lib/auth.ts` line is reworded.
- [ ] `CONTEXT.md` gains glossary entries under a new "Accounts" heading for **Account**, **Admin**, **Member** and **Sign-in**, in the existing style (definition plus an _Avoid_ line).
- [ ] `README.md` (root): the sentence describing how the app reaches the server mentions signing in rather than a token, if it says anything about it.
- [ ] `grep -ri "api_token\|admin_password" .` returns nothing outside git history. (**Success criterion 11**)

**Verification:**
- [ ] The grep above is clean.
- [ ] Read the README setup section start to finish and confirm someone could stand the backend up from scratch with it.

**Dependencies:** Task 12.

**Files likely touched:** `web/README.md`, `CONTEXT.md`, `README.md`.

**Scope:** S.

---

## Risks

- **Locking yourself out of the editor.** The single highest-consequence failure here, and it is pure sequencing: deploying Phase 2 before an admin row exists. Task 12 exists to prevent it. Recovery if it happens anyway: run `create-user.mjs` against production, which needs only `DATABASE_URL`.
- **The app is broken between Phase 3 and Phase 4.** Phases 2–3 remove the `API_TOKEN` that the shipped app uses. Build all four phases before deploying anything. This is why the API checkpoint carries a do-not-deploy note.
- **`/api/session` accepts unlimited password guesses.** So does `/login`, today — this adds a second door onto the same room rather than a new class of exposure, and admin-set passwords can simply be long. Worth revisiting if accounts ever outgrow people you know; not worth building a rate limiter for in v1.
- **PBKDF2 cost on a serverless function.** 600k iterations is roughly a few hundred milliseconds. It runs on sign-in only — never in `proxy.ts`, never per-request. Task 2 measures it rather than assuming.
- **Timing-distinguishable usernames.** Returning early when the username is unknown reveals which usernames exist. Task 6 hashes a dummy password in that branch, which costs one derivation on a failed login and nothing on a successful one.

## Rollback

Every step is reversible without data loss, because nothing is deleted from the database and the schema change is additive:

- **Before Task 12:** revert the branch. `users` and `submissions.submitted_by` sit unused.
- **After deploying:** revert the deployment in Vercel and re-add `API_TOKEN` and `ADMIN_PASSWORD` to the environment (keep them until step 7 of the runbook has been verified). The old build reads neither new column.
- **iOS:** the previous build reads the same keychain slot, so it will find a session token where it expects a shared secret and get a 401 — recovery is re-entering the old `API_TOKEN` in the old sheet, which still exists in that build.

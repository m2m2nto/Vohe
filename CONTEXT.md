# Vohe — Domain Glossary

Vohe is a personal iOS flashcard app for daily vocabulary practice. This glossary fixes the language used across code, specs, plans, PRs, and conversations. It is **not** a spec — it defines terms, not behavior.

## Language

### Entities

**Deck**:
A named collection of Cards sharing one language pair (e.g. "Croatian–Italian"), imported from a `.txt` file via the iOS Files picker and mirrored back to a file by `DeckFileStore`.
_Avoid_: "list", "set", "collection".

**Card**:
A `(front, back)` text pair belonging to exactly one Deck. Carries scheduling state (`Box`, `nextDue`) and a `wrongLastSession` flag (see Wrong-last-session).
_Avoid_: "entry", "word", "pair", "flashcard" (use Card).

### Session

**Session**:
One activity of swiping through an ordered list of Cards from start to end. Every Session has a Mode, a Slot, a Direction, and an Outcome. Resuming a `PausedSession` continues the **same** Session — the once-per-Card scheduling guard and Reinforcement counters persist across the pause.
_Avoid_: "run", "drill", "round".

**Mode**:
The Session's pool: `perDeck(Deck)` draws from a single Deck; `global([Card])` draws from a pre-built cross-deck list (currently used only by Review).
_Avoid_: "scope", "kind".

**Direction**:
**Forward** = front shows `language1`. **Inverted** = front shows `language2`. Stored as `inverted: Bool`. Global Sessions are always Forward.

**Slot**:
The session-length cap. Values: `5`, `20`, `50`, `100`, or `All` (sentinel `0`). Stored as `wordCount: Int`. Reinforcement re-queues can push the final `order.count` above Slot.
_Avoid_: "word count", "session size".

**Outcome**:
What persists at end-of-Session. A perDeck Session ends as `SessionResult` (completed), `PausedSession` (paused), or nothing (discarded). A global Session is **ephemeral**: it produces no `SessionResult` and cannot be paused — only completed (no record) or discarded.
_Avoid_: "result" (overloaded — `SessionResult` is one specific Outcome).

**Review**:
The Library-level entry point that opens a global Session over all currently-Due Cards across all Decks. Always Forward, ephemeral. Row label hides the count when N > 100.
_Avoid_: "global review", "review session" (the row is "Review"; the Session it opens is a global Session).

**Practice Hardest**:
A kind of perDeck Session with `onlyHardest = true`. Orders cards by `DifficultyStore` wrong-rate descending; ignores Box state and Due dates. A Card enters the order only if it is Rankable (`seen ≥ 3`) **and** has a wrong-rate above 0 — a Card you have never missed is never drilled here. The button unlocks as soon as the Deck holds one such Card: `DifficultyStore.hardestCount` applies the same predicate as the session's own filter, so an enabled button always means a non-empty Session.
_Avoid_: "hardest mode", "hard practice".

**Quick session**:
A perDeck Session with Slot 5, started by tapping a reminder notification, run on the most-recently-Practiced Deck — or, when no Deck has ever been Practiced, on the newest Deck.
_Avoid_: "notification session", "5-card session".

**Practice**:
The act of completing a perDeck Session (writing a `SessionResult`). Review Sessions deliberately **do not count** as Practice — they are ephemeral by design. `lastPracticedDeck` and `lastPracticedAt` both consider only `SessionResult` rows.
_Avoid_: using "practice" to describe Review or partial sessions in code/spec prose.

### Scheduling

**Box**:
A Card's place in the Leitner ladder. Index 0–5. Box 0 = New (never graded). Boxes 1–5 = Scheduled, with intervals 1, 3, 7, 21, 60 days respectively.
_Avoid_: "level", "stage", "bucket".

**New**:
A Card in Box 0, never graded. `nextDue = .distantPast`. Eligible the moment it's imported. New cards are **not** Due — Due means Scheduled-and-eligible. Either Grade (Again or Good) promotes a New card to Box 1 on its first grading.
_Avoid_: "unseen", "never-reviewed", "fresh".

**Scheduled**:
A Card in Box 1–5. Has a meaningful `nextDue`.
_Avoid_: "in rotation", "active", "tracked".

**Due**:
A Scheduled Card whose `nextDue` is strictly before the start of the next calendar day (today or earlier). New Cards are explicitly **not** Due — they are New. A perDeck Session order partitions Cards into three disjoint sets: **Due**, **New**, **Undue**.
_Avoid_: "eligible", "ready".

**Overdue**:
A Due Card with `nextDue < startOfDay(today)` — strictly before today's start. Every Due Card is either Overdue or due-today.

**Overdueness**:
The magnitude `startOfDay(today) - nextDue` (days). Descending sort key within the Due bucket.

**Undue**:
A Scheduled Card with `nextDue >= tomorrowStart`. Used as filler at the end of a perDeck Session order when Due + New don't fill the Slot.

**Grade**:
The binary outcome of one swipe. Two values: **Good** (right swipe — knew it) and **Again** (left swipe — didn't know it). Matches `LeitnerScheduler.Grade`. UI badges may read "CORRECT" / "WRONG"; code prose, specs, and PRs use Grade vocabulary.
_Avoid_: "wrong", "correct", "right", "left", "wasCorrect", "answer", "score".

**Reinforcement**:
The in-Session re-queue behavior: when a Card is graded Again, it's appended back into `order` so the user sees it again before the Session ends. Capped at 2 extra appearances per Card per Session (`reinforcementCap`). Internal term — never user-facing.
_Avoid_: "re-queue" (use Reinforcement in prose; "re-queue" is fine when describing the mechanic).

**Backfill**:
The one-shot operation (`SchedulerMigration.run`) that, on first launch after upgrading to Leitner, assigns initial `boxIndex` and `nextDue` to every existing Card based on its `DifficultyStore` wrong-rate. Distinct from SwiftData schema migration: schema migration adds the *fields*; Backfill populates them.
_Avoid_: "migration" alone (ambiguous with schema migration).

### Translation

**Suggestion**:
A `back` value produced by the on-device model (`Translator`, built on `FoundationModels`) instead of typed by the user. Offered only when adding a Card and only while the `back` field is empty. Every failure — Apple Intelligence unavailable, device ineligible, language refused, empty answer — collapses to "no Suggestion", and the user types the translation themselves.
_Avoid_: "translation" alone (ambiguous with the `back` field of any Card).

**Unvalidated**:
A Card whose `back` is still exactly the Suggestion the model produced (`Card.needsValidation == true`). Surfaced by a "Not validated" badge on the Card face showing `card.back` and a `sparkles` marker in the cards list. Two things clear the flag: tapping **Translation looks right** mid-Session, or saving the Card from the editor — reviewing it in the editor *is* validation, whether or not the text changed.
_Avoid_: "unconfirmed", "pending" (Pending is reserved for a captured word with no translation at all).

**Validation hold**:
The rule that an Unvalidated Card cannot be promoted past Box 1 (`LeitnerScheduler.apply(isValidated:)`), however often it's graded Good. Prevents an unchecked Suggestion from drifting out to a 60-day interval before the user has ever looked at it. Again Grades behave normally.

> **Language support caveat:** Apple's on-device model officially covers only the Apple Intelligence locales, which do **not** include Croatian. Suggestions are requested with an English-language prompt that *names* the languages, so an unsupported language appears only as the subject of the request — this may work, but Apple guarantees nothing about the quality. The Validation hold exists precisely because of this.

### Shared dictionaries

**Dictionary**:
A word list held by the backend (`web/`), the shared counterpart of a Deck. A Dictionary has an `id`, a name, a language pair, a Version, and its approved words. Optional: a Deck may exist with no Dictionary behind it, and the app runs entirely without a backend.
_Avoid_: using "Deck" for the server-side list, or "Dictionary" for the on-device one.

**Linked**:
A Deck that carries a Dictionary's `id` (`Deck.remoteID`). Linking happens when the Dictionary is added from the browse screen; an existing unlinked Deck of the same name is adopted rather than duplicated, so its Stats and Boxes carry over.
_Avoid_: "synced" (a Linked Deck may be many Versions behind, on purpose).

**Version**:
A Dictionary's change counter (`decks.version`), starting at 1 and rising on every approved change to its words or labels. The Deck stores the Version it pulled (`syncedVersion`) and the highest one seen in the catalog (`latestRemoteVersion`).

**Update available**:
`latestRemoteVersion > syncedVersion` on a Linked Deck. Surfaced as an "Update" badge on the Library row and an Update button in Deck Detail. Taking the update is always the user's action — the app never rewrites words on its own.
_Avoid_: "out of sync", "stale".

**Local-only**:
A Card in a Linked Deck that the Dictionary doesn't carry (`Card.remoteBack == nil`) — either added on the device or dropped from the Dictionary upstream. Marked with an `iphone` icon in the cards list. Updates never delete Cards, so this is how "the Dictionary lost it, you didn't" is expressed.

**Proposal**:
A word waiting in the backend's review queue (`submissions` table, `status = 'pending'`) — sent from the app, or pasted into the editor for review rather than added. A Proposal is invisible to every export, API read, and other device until approved in the editor. Approving applies it to the Dictionary and bumps the Version; rejecting leaves the Dictionary untouched and the Card local. Approving a batch bumps the Version once.
_Avoid_: "upload", "push", "sync up" — nothing the app sends becomes shared by itself.

**Waiting for review**:
A Card whose current text has been sent as a Proposal (`Card.pendingReview`). An update leaves such a Card's text alone until the review lands, so pressing Update never discards the edit being reviewed. Everything else diverging from the Dictionary is replaced by it.

### Accounts

**Account**:
A named user held by the backend (`users` table): a username, a hashed password, and a role. One Account serves both surfaces — the web editor and the app — and exists only on the server. Nothing about a Deck, a Card, a Box or the Stats belongs to an Account; those stay on the device.
_Avoid_: "profile", "login" as a noun, or implying practice data follows an Account between devices.

**Admin**:
An Account with `role = 'admin'`. The only role that opens the editor, where dictionaries are written, Proposals are approved, and Accounts are managed. There is no signup page and no self-service reset: an Admin creates every Account, and only an Admin can change one.
_Avoid_: "owner", "superuser".

**Temporary password**:
The password the editor generates when an Admin creates an Account or resets one. Shown once, on the page that made it, and never again — only its hash is stored. "Temporary" is a convention, not a rule: nothing forces a change, because a Member has no surface on which to change one. Losing it means resetting it.
_Avoid_: "initial password", "default password" (there is no default), implying the holder must or can rotate it.

**Member**:
An Account with any other role. It signs in from the app, pulls Dictionaries and sends Proposals, and is refused by the editor with a plain page rather than a redirect.
_Avoid_: "user" when the distinction from Admin matters, "guest" (a Member is not anonymous).

**Sign-in**:
Trading a username and a password for a session token — in the browser at `/login`, in the app at `POST /api/session`. The token names its Account and its surface, lasts 30 days for the browser and a year for the app, and is the only thing the app stores (in the keychain); the password is never kept. Signing out drops the token and leaves every Deck and all Stats untouched.
_Avoid_: "access token" or "API token" (both retired), "authentication" where "signing in" reads plainly.

### Stats & ranking

**Stats**:
The per-Card historical counters (`seen`, `wrong`) held by `DifficultyStore` and persisted to `difficulty.json`. Keyed by `(deckName, front, back)` — independent of the Card's SwiftData UUID. Survives Card edit and Deck rename via `DifficultyStore.rename` / `renameDeck`.
_Avoid_: "history", "metrics".

**Wrong-rate**:
`wrong / seen`. Defined only when `seen ≥ 3` (`DifficultyStore.minSeenForRanking`). Sort key for Practice Hardest. Backfill bucket boundaries: `<0.2 → Box 3`, `<0.4 → Box 2`, else `Box 1`.
_Avoid_: "difficulty score" (use Wrong-rate; "difficulty score" is the same value but the noun isn't useful elsewhere).

**Rankable**:
A Card with enough samples for its Wrong-rate to be defined — i.e. `seen ≥ 3` (`DifficultyStore.minSeenForRanking`). Necessary but not sufficient for Practice Hardest, which also requires Wrong-rate > 0.

**Timed sample**:
The pair of durations one Good Grade contributes to a Card's Stats: **Time to flip** (Card appearing → tap that reveals it) and **Time to swipe** (that reveal → the swipe). Only a Card's **first showing in a Session** is sampled: Again Grades never are, and neither are the Reinforcement repeats that follow one, because by the time a re-queued Card comes round its answer has just been read. Only the first reveal of a showing starts the swipe clock, and a half longer than 60s is dropped rather than recorded — a Card left on screen while the app is backgrounded is not a reaction. Sampled alongside `seen`/`wrong` in `DifficultyStore`, under the same key, so a Card edit or Deck rename carries the samples along.
_Avoid_: "response time", "latency".

**Reaction Times**:
The Library screen listing every Card with at least one Timed sample: its average Time to flip, its average Time to swipe, and how many samples back them. Read-only — it reports the numbers so a "learned" threshold can be chosen from them; nothing in a Session behaves differently because of it.

**Wrong-last-session**:
A per-Card sticky flag (`Card.wrongLastSession`) that is set to `true` on every Again Grade and `false` on every Good Grade. Cards never touched in any Session retain the default `false`. Surfaced by `DeckDetailView`'s "Wrong last session" row and the `WrongCardsView` list. Independent of Box state — a Card can be in Box 5 *and* have `wrongLastSession == true` if its most recent Grade was Again. The name is slightly misleading: the value reflects "the most recent Grade was Again," not "Again in the last completed Session."
_Avoid_: treating this as a session-scoped flag — it is per-Card.

### Reminders & notifications

**Reminder**:
A scheduled local notification that asks the user to start a short Session. Reminders are produced by `ReminderScheduler` from a single user-configured **Reminder settings** record.
_Avoid_: using "notification" for the user-facing concept; "Reminder" is the user-facing word (bell icon, "Daily reminders" toggle, Reminder settings sheet).

**Reminder settings**:
The user's single configuration record (`ReminderSettings`), persisted to `UserDefaults`. Specifies `enabled`, `mode` (Random or Exact), `count`, and either a window (for Random) or specific times (for Exact).

**Notification**:
The iOS-level delivery mechanism (`UNUserNotification`). Use this word only when discussing iOS plumbing — authorization, delegate callbacks, pending requests. The user-facing concept is a Reminder.

### Library surfaces

**Library**:
The home screen (`LibraryView`) — list of Decks plus the Review row and the In Progress section. The `+` toolbar button opens the iOS file importer to create a Deck from a `.txt` vocabulary file.

**In Progress**:
The Library section listing `PausedSession`s. Capped at 5 (`PausedSession.cap`); when the cap is hit, new perDeck Sessions cannot be paused (they can still complete or be discarded).

**Active session**:
The currently-presented Session sheet, one of: Quick session (`.quickDeck`), Resumed Paused Session (`.resume`), or Review (`.globalReview`). Per-deck "Start Session" is launched from `DeckDetailView`, not Library.

## Example dialogue

> **Dev:** I imported the new Spanish deck yesterday and graded 20 cards. This morning Library says "Review (3 due)." Why only 3?
>
> **Designer:** Because those 20 you graded yesterday are now Scheduled, in Box 1, with `nextDue = tomorrow`. They're Undue today. The 3 Due Cards must be from an older Deck whose Scheduled Cards crossed their `nextDue` overnight. Your Spanish deck still has lots of New Cards too — those are eligible but won't show in the Review count, because Review only counts Due.
>
> **Dev:** Got it. If I tap Review and finish all 3 Cards, will it count as my Practice for today?
>
> **Designer:** No. Review is ephemeral — no `SessionResult` is written, so `lastPracticedAt` doesn't move. To count as Practice today, start a perDeck Session from one of the Decks and complete it. The Quick session from your next reminder tap will still open on whichever Deck you Practiced most recently.
>
> **Dev:** And if I swipe Again on the first card three times in a row?
>
> **Designer:** Reinforcement caps at 2 extras. First Again — Card requeues at the end, Box becomes 1, `nextDue` = tomorrow. Second Again on the same Card — requeues again. Third Again — Box stays 1, `nextDue` stays tomorrow, but no third requeue. Subsequent grades on that Card record Stats but don't touch Box or `nextDue` — Reinforcement is a learning step, not a scheduling event.

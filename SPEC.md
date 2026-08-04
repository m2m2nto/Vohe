# Vohe — Vocabulary Flashcard App (Spec)

> **Superseded sections:** The "Session Logic" section below, the "wrong words carry over to next session" line under "Scope (v1)", and the "Spaced repetition algorithm" line under "Out of Scope (v1)" are superseded by [`docs/specs/spaced-repetition-leitner.md`](docs/specs/spaced-repetition-leitner.md) — per-card Leitner scheduling replaces wrong-word carryover, and a Library-level "Review (N due)" surface was added. The "Editing cards or decks in-app" line under "Out of Scope (v1)" is also superseded: cards can now be added, edited (including mid-session), and deleted in-app, and decks can be renamed and exported. "Data Model" and "Screens" below have been updated to match the shipped app; [`CONTEXT.md`](CONTEXT.md) is the authoritative glossary for the terms they use. The rest of this v1 spec still holds.

## Goal
Personal iOS app to memorize vocabulary in new languages via flashcards. Installed directly via Xcode (no App Store).

## Scope (v1)
- Single user, on-device only, no backend, no iCloud sync. (Superseded: the app can now pull dictionaries from the optional [`web/`](web/README.md) backend and send words back for review — see the "Shared dictionaries" section of [`CONTEXT.md`](CONTEXT.md). It stays optional: with no server configured the app is exactly the on-device app described here.)
- Library of multiple decks, imported from text files via the iOS Files picker.
- Flashcard sessions with swipe scoring. (v1: wrong words carry over to the next session — superseded by per-card Leitner scheduling.)
- UI in English. Vocabulary content is language-agnostic.

## Out of Scope (v1)
- Spaced repetition algorithm (SM-2, Anki-style) — wrong-word carryover is the only memory mechanism.
- Audio/pronunciation, images, example sentences.
- Editing cards or decks in-app (re-import the file to update).
- Sharing, accounts, cloud backup.
- App Store distribution.

## Tech Stack
- **Platform:** iOS 26+
- **UI:** SwiftUI
- **Persistence:** SwiftData
- **File import:** SwiftUI `.fileImporter` modifier (UTType `.plainText` and `.text`)
- **Project:** Single Xcode project, no SPM packages beyond Apple frameworks
- **Distribution:** Personal sideload via Xcode (free Apple Developer account works; 7-day re-sign cycle)

## File Format (Strict)
- UTF-8 plain text, `.txt` extension.
- Line 1: `language1-language2` (e.g. `Italian-Croatian`). These label the front/back of the cards.
- Lines 2+: `word-translation` (one per line). Multiple translations: comma-separated within the translation field (e.g. `cane-pas, kuca`).
- Separator is a literal hyphen `-`. Entries containing hyphens are **not supported** in v1.
- Blank lines and lines starting with `#` are ignored.
- Validation on import: reject and show error if line 1 is malformed or fewer than 1 vocabulary line.

## Data Model
- **Deck**: `id`, `name` (filename without extension), `language1`, `language2`, `createdAt`, `cards: [Card]`, `sessions: [SessionResult]`.
- **Card**: `id`, `front` (language1 word), `back` (language2 word), `wrongLastSession: Bool`, `boxIndex: Int` (0 = new, 1–5 = scheduled), `nextDue: Date` (`.distantPast` when new), `deck`.
- **SessionResult**: `id`, `total`, `correct`, `inverted: Bool`, `startedAt`, `completedAt`, `wrongCardIDs: [UUID]`, `deck` (relationship, not a raw id).
- **PausedSession**: `id`, `cardOrderIDs: [UUID]` (may contain duplicates from reinforcement), `currentIndex`, `correct`, `inverted`, `wordCount`, `startedAt`, `pausedAt`, `wrongCardIDs`, `gradedCardIDs`, `againCounts` (stored as parallel id/value arrays), `deck`. At most `PausedSession.cap` (5) exist at once.

Per-card historical stats (`seen` / `wrong`) live outside SwiftData, in `Documents/difficulty.json` (`DifficultyStore`).

## Screens

### 1. Library (Home)
- "Review (N due)" row at the very top, shown only when N > 0; label drops the count when N > 100. Opens a cross-deck, forward-only, ephemeral session over due cards.
- "In Progress" section listing paused sessions (max 5); tap to resume, swipe to delete.
- List of decks: name, language pair, card count, last-session score.
- Tap a deck → Deck Detail. Swipe a deck to delete.
- Toolbar: bell button → Reminder settings; `+` button → file importer.

### 2. Deck Detail
- Shows deck name (tap to rename), language pair, card count (tap → cards list), count of wrong-last-session cards (tap → wrong-cards list).
- Session section: slot picker (5 / 20 / 50 / 100 / All), "Inverted (show <language2> first)" toggle, "Start Session", and "Practice Hardest" (enabled once the deck holds at least one card seen ≥ 3 times that you've missed at least once).
- List of last 5 session results; tap one → Session Detail (duration + missed words).
- "Delete Deck" at the bottom, behind a confirmation. Removes the deck, its cards, its session history and its paused session from this device only — a linked shared dictionary is left untouched on the server. Also available by swiping the row in Library.
- Toolbar: `+` add card; Share to export the deck's `.txt` mirror.

### 3. Flashcard Session
- One card at a time, centered.
- Tap card → flip animation reveals the other side.
- After flip, swipe right = correct, swipe left = wrong (gestures disabled until flip). A wrong card is re-queued later in the same session, at most twice.
- Progress indicator: `card N of total` (total grows when a card is re-queued).
- Live score (correct so far / shown so far).
- Pencil button edits the current card mid-session.
- Cancel button (top-left) opens a dialog: Pause (per-deck sessions only, and only under the paused-session cap) / Discard / Keep going.

### 4. Session Results
- Total cards, correct count, percentage.
- "Done" returns to Deck Detail.
- Saves a SessionResult — except for Review sessions, which are ephemeral and record nothing at the session level.

## Session Logic
1. Collect all cards in deck.
2. Build session order: cards with `wrongLastSession == true` first, then remaining cards. Within each group, shuffle randomly (`Array.shuffled()`).
3. Reset all `wrongLastSession` flags to false at session start.
4. On swipe-right: leave flag false. On swipe-left: set `wrongLastSession = true`.
5. Session length = entire deck (one pass). No re-queue within session.
6. On finish, persist SessionResult.

## Acceptance Criteria
1. Importing a valid file creates a deck visible in the Library.
2. Importing a malformed file shows a clear error and creates nothing.
3. Starting a session shuffles cards (verified by running twice, observing different order).
4. Tap reveals back; swipe-right increments correct; swipe-left does not.
5. After finishing a session with N wrong cards, those N cards appear first in the next session.
6. Inverted toggle swaps front/back display for the entire session.
7. Score display matches actual swipe count.
8. Deleting a deck removes it and its session history.
9. App launches to Library with empty state if no decks exist.
10. App relaunches preserve all decks, cards, wrongLastSession flags, and session history.

## Sample File (for testing)
```
Italian-Croatian
cane-pas
gatto-mačka
casa-kuća
acqua-voda
pane-kruh
```

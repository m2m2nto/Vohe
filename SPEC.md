# Vohe — Vocabulary Flashcard App (Spec)

## Goal
Personal iOS app to memorize vocabulary in new languages via flashcards. Installed directly via Xcode (no App Store).

## Scope (v1)
- Single user, on-device only, no backend, no iCloud sync.
- Library of multiple decks, imported from text files via the iOS Files picker.
- Flashcard sessions with swipe scoring; wrong words carry over to next session.
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
- **Deck**: `id`, `name` (filename without extension), `language1`, `language2`, `createdAt`, `cards: [Card]`.
- **Card**: `id`, `front` (language1 word), `back` (language2 word), `wrongLastSession: Bool`, `deck`.
- **SessionResult**: `id`, `deckId`, `total`, `correct`, `inverted: Bool`, `completedAt`.

## Screens

### 1. Library (Home)
- List of decks: name, language pair, card count, last-session score.
- Tap a deck → Deck Detail.
- Toolbar: `+` button → file importer.

### 2. Deck Detail
- Shows deck name, language pair, card count, count of wrong-last-session cards.
- "Start Session" button.
- Toggle: "Inverted (show translation first)".
- List of last 5 session results.
- Toolbar: Delete deck (with confirmation).

### 3. Flashcard Session
- One card at a time, centered.
- Tap card → flip animation reveals the other side.
- After flip, swipe right = correct, swipe left = wrong (gestures disabled until flip).
- Progress indicator: `card N of total`.
- Live score (correct so far / shown so far).
- Cancel button (top-left) returns to Deck Detail without saving results.

### 4. Session Results
- Total cards, correct count, percentage.
- "Done" returns to Deck Detail.
- Saves SessionResult.

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

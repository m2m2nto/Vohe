# Implementation Plan: Reference Dictionary (v2 — unification)

> **v2 (2026-05-29):** Plan replacing the v1 task list. v1's T1-T4 and T7-T8 stay landed; T5 (CopyToDeckSheet) and T6 (DeckExporter + per-Deck send section) are removed by U1 below. New work brings the model in line with [`docs/specs/dictionary.md`](../specs/dictionary.md) v2 and [`docs/adr/0004-dictionary-projection-and-unified-suggestions.md`](../adr/0004-dictionary-projection-and-unified-suggestions.md).

## Overview

Pivot from "Dictionary as reference + Deck as curated subset" to "Dictionary as source of truth + Deck as projection." User additions and edits unify into a per-pair suggestions queue stored at `<App Support>/Dictionaries/<pair>.suggestions.json`, applied on read by `DictionaryStore`, and shipped to the maintainer via the iOS share sheet from `DictionaryView`. File imports create user-owned Dictionaries (not curated Decks). A one-shot `UnificationMigration` collapses multi-deck-per-pair situations into single Decks.

Source spec: [`docs/specs/dictionary.md`](../specs/dictionary.md) v2.
Source ADRs: [`docs/adr/0002`](../adr/0002-dictionary-contributions-via-share-sheet.md), [`docs/adr/0003`](../adr/0003-dictionary-updates-via-runtime-pull.md), [`docs/adr/0004`](../adr/0004-dictionary-projection-and-unified-suggestions.md).

## Architecture Decisions

- **One Dictionary per pair; at most one Deck per pair.** Migration enforces this.
- **Storage:** canonical `<P>.txt` (managed by `DictionarySync`) + user `<P>.suggestions.json` (managed by `DictionarySuggestionStore`). DictionaryStore reads both and merges on every `reload()`. On dedup, user addition wins over identical canonical (origin stays `userAddition` until post-sync cleanup prunes the addition).
- **`DictionaryEntry` gains an `origin` enum** so the UI can distinguish canonical / userAddition / canonicalWithEdit (e.g., show a small indicator on user-added entries).
- **`DeckDictionaryProjector` is a stateless service** invoked after every reload. Its job: ensure every Dictionary entry of pair P has a corresponding Card in every Deck of P, with edits propagated and Leitner state preserved.
- **Migration is destructive on a single dimension only:** multi-deck-per-pair collapses. Cards never disappear; Leitner state per `(front, back)` is preserved as best-of.
- **Card edit flow:** the existing `CardEditorSheet` keeps its UI. The save handler now also logs the edit as a suggestion. Card delete is removed everywhere — no swipe-to-delete on Card lists, no delete button in the card editor.
- **No file imports.** `.fileImporter` is removed from `LibraryView`. The only source of new language pairs is the maintainer publishing them via the manifest. `NewDeckPickerSheet` is replaced by a simpler `DictionaryPickerSheet` that picks among locally-available canonical pairs.
- **Post-sync cleanup:** after each successful `DictionarySync` per-pair download, `DictionarySuggestionStore.cleanup(pair:canonicalEntries:)` prunes suggestions that canonical has adopted (addition matches a canonical entry; edit's `edited` values appear in canonical, OR edit's `original` is gone).
- **User-mine indicator:** `DictionaryEntryRow` shows a blue dot for `.userAddition` and a blue pencil for `.canonicalWithEdit`. The same marker appears on the projected Card row in `CardsListView`.
- **Edit discovery in DictionaryView is a trailing swipe**, not a long-press.
- **Send pending button** shows a red-dot badge when the queue is non-empty.
- **Suggestion deduplication is read-time only** — `.suggestions.json` is append-only. Dedup happens during `DictionaryStore.load()`.
- **No new dependencies.** CryptoKit and URLSession already cover everything.

## Task List

### Phase 0: Cleanup (delete v1 dead code)

#### U1: Remove T5 and T6 surfaces

**Description:** Remove the v1 `CopyToDeckSheet` flow from `DictionaryView`; remove the "Community Dictionary" section from `DeckDetailView`; delete `DeckExporter.swift` and its test file. Keep `ShareSheetView.swift` (reused by `DictionaryView`'s "Send pending" in U6).

**Acceptance criteria:**
- [ ] `Vohe/Views/DictionaryView.swift` no longer references `CopyToDeckSheet` and the `copyTarget` state. Context menu on `DictionaryEntryRow` is removed (replaced in U5 with a trailing-swipe → Edit).
- [ ] `Vohe/Views/DeckDetailView.swift` no longer has the "Community Dictionary" section or `suggestionShareURL` state.
- [ ] `Vohe/Services/DeckExporter.swift` deleted.
- [ ] `VoheTests/DeckExporterTests.swift` deleted.
- [ ] `Vohe/Services/DeckFileStore.swift` retains `serialize` and `sanitize` as `internal` — used by other code paths.

**Verification:**
- [ ] Build: `xcodebuild ... build CODE_SIGNING_ALLOWED=NO`.
- [ ] Test: `xcodebuild test` passes (DictionarySync, DictionaryManifest, DictionaryStore tests still green).
- [ ] Manual: open the app, confirm the Deck detail page no longer has the "Send to maintainer" affordance; confirm long-press on a Dictionary entry does NOT show "Copy to Deck".

**Dependencies:** None (works against the current state).

**Files touched:** `DictionaryView.swift`, `DeckDetailView.swift`. Files deleted: `DeckExporter.swift`, `DeckExporterTests.swift`.

**Scope:** S.

---

### Phase 1: Model + storage refactor

#### U2: Suggestions storage (`DictionarySuggestions` + `DictionarySuggestionStore`)

**Description:** New model + new file-backed store. The model is a `Codable` value type matching the schema in the spec; the store reads, writes, and appends per-pair JSON files at `<App Support>/Dictionaries/<pair>.suggestions.json`.

**Acceptance criteria:**
- [ ] `Vohe/Models/DictionarySuggestions.swift` defines `struct DictionarySuggestions: Codable, Equatable` with `additions: [Entry]` and `edits: [Edit]`, where `Entry { front: String; back: String }` and `Edit { original: Entry; edited: Entry }`.
- [ ] `Vohe/Services/DictionarySuggestionStore.swift` is an `enum` with `static` methods:
  - `read(pair: String, directory: URL) -> DictionarySuggestions` (returns empty on missing/malformed)
  - `appendAddition(pair: String, _ entry: DictionarySuggestions.Entry, directory: URL) throws`
  - `appendEdit(pair: String, _ edit: DictionarySuggestions.Edit, directory: URL) throws`
  - `tempfileURL(pair: String, today: Date) -> URL` — returns `<tempDir>/vohe-<pair>-suggestions-<yyyy-MM-dd>.json`
  - `exportTempfile(pair: String, directory: URL, today: Date) throws -> URL` — writes `<pair>.suggestions.json` bytes to tempfile, returns URL
- [ ] All file writes use atomic write. Malformed JSON is treated as empty (no throw on read).
- [ ] Tests in `VoheTests/DictionarySuggestionStoreTests.swift` cover: read missing → empty; read malformed → empty (no throw); append-without-clobber (additions list grows); roundtrip via Codable; export tempfile matches source bytes.

**Verification:**
- [ ] `xcodebuild test -only-testing:VoheTests/DictionarySuggestionStoreTests` passes.

**Dependencies:** U1.

**Files touched:** `DictionarySuggestions.swift` (new), `DictionarySuggestionStore.swift` (new), `DictionarySuggestionStoreTests.swift` (new).

**Scope:** S.

---

#### U3: `DictionaryEntry.origin` + `DictionaryStore` merge logic

**Description:** Add an `origin` enum to `DictionaryEntry`. Rewrite `DictionaryStore.load()` to merge canonical + suggestions per pair, marking each entry's origin.

**Acceptance criteria:**
- [ ] `Vohe/Models/DictionaryEntry.swift` adds `enum Origin { case canonical, userAddition, canonicalWithEdit }` and `let origin: Origin` (default `.canonical` for existing callers).
- [ ] `Vohe/Services/DictionaryStore.swift` updated:
  - On `load()`, for each pair enumerated from `<pair>.txt`, perform the merge per spec § Read-time merge. (Suggestions files only exist alongside a canonical `<pair>.txt` — there are no suggestions-only pairs to enumerate.)
  - Entries deduplicated by `(front, back)` — the **user addition wins** over an identical canonical entry; the kept entry has `origin = .userAddition` and stays marked "mine" until post-sync cleanup prunes the adopted addition.
  - Stale edits (no matching canonical) silently dropped.
- [ ] `entries(for pair: String)` still returns `[DictionaryEntry]`. Order: canonical entries (in file order, with edits applied in place) followed by additions (in append order).
- [ ] `DictionaryStoreTests` expanded to cover spec criteria 1-6.

**Verification:**
- [ ] `xcodebuild test -only-testing:VoheTests/DictionaryStoreTests` passes.

**Dependencies:** U2.

**Files touched:** `DictionaryEntry.swift` (changed), `DictionaryStore.swift` (changed), `DictionaryStoreTests.swift` (changed).

**Scope:** M.

---

### Phase 2: Deck projection

#### U4: `DeckDictionaryProjector`

**Description:** Stateless service that reconciles a Deck's Cards against its pair's Dictionary entries — additive on new entries, propagates edits, preserves Leitner state, never deletes Cards.

**Acceptance criteria:**
- [ ] `Vohe/Services/DeckDictionaryProjector.swift` exposes `static func sync(_ deck: Deck, context: ModelContext, store: DictionaryStore)`:
  - For every Dictionary entry not represented by any Card in `deck.cards` → insert a new `Card` with `boxIndex=0, nextDue=.distantPast, wrongLastSession=false`, linked to `deck`.
  - For every Card whose `(front, back)` matches an `edit.original` in the pair's suggestions → rewrite `front`/`back` to `edited` values. Leitner state preserved.
  - Cards in the Deck with no matching Dictionary entry: left untouched.
  - Calls `try? context.save()` at end.
- [ ] Tests in `VoheTests/DeckDictionaryProjectorTests.swift` cover spec criteria 7-10 using an in-memory `ModelConfiguration(isStoredInMemoryOnly: true)`.

**Verification:**
- [ ] `xcodebuild test -only-testing:VoheTests/DeckDictionaryProjectorTests` passes.

**Dependencies:** U3.

**Files touched:** `DeckDictionaryProjector.swift` (new), `DeckDictionaryProjectorTests.swift` (new).

**Scope:** M.

---

### Phase 3: DictionaryView UI (Add entry, Send pending, Edit)

#### U5: Add entry + edit existing in DictionaryView (+ mine indicator)

**Description:** New `AddDictionaryEntrySheet` for both creating and editing. Pair section in `DictionaryView` gains a `+` (Add) button. Each row exposes Edit via a trailing-swipe action (not long-press, not context menu). `DictionaryEntryRow` renders an origin marker (blue dot / blue pencil) for non-canonical entries. Add and Edit both write to `DictionarySuggestionStore`, then reload + project.

**Acceptance criteria:**
- [ ] `Vohe/Views/AddDictionaryEntrySheet.swift`: a sheet with `front` and `back` text fields and a Save button. Initialised with empty values for new, or pre-filled for edit.
- [ ] On save (new): calls `DictionarySuggestionStore.appendAddition(...)`, then `DictionaryStore.shared.reload()`, then `DeckDictionaryProjector.sync(D, ...)` for any Deck of that pair.
- [ ] On save (edit): calls `DictionarySuggestionStore.appendEdit(original: ..., edited: ...)`, same reload + project pipeline.
- [ ] `DictionaryEntryRow` exposes `.swipeActions(edge: .trailing)` with a single "Edit" button that opens the sheet pre-filled. **No long-press, no context menu.**
- [ ] `DictionaryEntryRow` shows a leading-edge marker: blue dot for `.userAddition`, blue pencil-tip (`pencil.tip`) for `.canonicalWithEdit`, nothing for `.canonical`.
- [ ] `DictionaryView` pair section has a `+` button (header or a top row) that opens the sheet for that pair.
- [ ] No tests required for the View itself; logic is in U2/U3/U4/U10. Manual smoke covers the integration.

**Verification:**
- [ ] Build clean.
- [ ] Manual: open Dictionary → tap `+` on Croatian-Italian → enter "test-front" / "test-back" → Save. Entry appears in the list. Open the matching Deck → new Card visible with box 0.
- [ ] Manual: trailing-swipe an entry → Edit → change "back" → Save. Entry updates; matching Card in Deck shows new value.

**Dependencies:** U4.

**Files touched:** `AddDictionaryEntrySheet.swift` (new), `DictionaryView.swift` (changed), `DictionaryEntryRow.swift` (changed).

**Scope:** M.

---

#### U6: Per-pair "Send pending" in DictionaryView (+ red-dot badge)

**Description:** Each pair section gets a button that, when tapped, exports `<P>.suggestions.json` as a tempfile via `ShareSheetView`. Hidden when the pair has zero pending suggestions. The button shows a red-dot badge whenever pending count > 0.

**Acceptance criteria:**
- [ ] `DictionaryView` per-pair section header shows a button labelled "Send pending (\(n))" where `n` is `additions.count + edits.count`. **Always visible; disabled when `n == 0`.**
- [ ] The button shows a **red-dot badge** when `n > 0`. Implementation: `.badge(...)` modifier on the label (preferred) or an overlay red `Circle()` 8pt diameter top-trailing. Badge disappears when `n == 0`.
- [ ] Tapping it calls `DictionarySuggestionStore.exportTempfile(pair:directory:today:)` and presents a sheet hosting `ShareSheetView(items: [url])`.
- [ ] After share-sheet dismissal, the local `<P>.suggestions.json` is unchanged.
- [ ] Tests in `DictionarySuggestionStoreTests` cover the export path (already in U2).

**Verification:**
- [ ] Build clean.
- [ ] Manual: add an entry to Croatian-Italian → confirm "Send pending (1)" button visible → tap → share sheet opens with `vohe-Croatian-Italian-suggestions-<today>.json`.

**Dependencies:** U5.

**Files touched:** `DictionaryView.swift` (changed).

**Scope:** S.

---

### Phase 4: CardEditorSheet hook + delete removal

#### U7: Route Deck card edits through suggestions; remove delete; surface mine-indicator on Cards

**Description:** When `CardEditorSheet` saves an edit on a dictionary-backed Card (i.e., a Card whose `(front, back)` matches a Dictionary entry of its Deck's pair), also log the edit in `DictionarySuggestionStore`. Remove the card-delete UI app-wide. Surface the user-mine indicator on each Card row in `CardsListView` mirroring the Dictionary's origin marker.

**Acceptance criteria:**
- [ ] `Vohe/Views/CardEditorSheet.swift` save handler: if the Card's original `(front, back)` matches a current Dictionary entry of the Deck's pair, call `DictionarySuggestionStore.appendEdit(...)`. Reload + project as in U5.
- [ ] If the Card has no matching Dictionary entry (defensive, post-migration only), the edit is purely local on the Card object — no suggestion logged.
- [ ] Card delete affordance removed **everywhere**: no `.onDelete` on Card lists in `CardsListView`, `WrongCardsView`, `DeckDetailView`, or any other surface. No "delete" button in `CardEditorSheet`. Manual scan to confirm none remain.
- [ ] `CardsListView` row shows the same leading-edge marker (blue dot / pencil) used by `DictionaryEntryRow`, looked up via `DictionaryStore.shared.entries(for: pair)` for the Deck's pair.
- [ ] No test changes required — the existing CardEditorSheet has no test target; manual smoke covers it.

**Verification:**
- [ ] Build clean.
- [ ] Manual: open a Deck card via the card editor → change "back" → Save. Confirm the card displays new value; open Dictionary → entry shows new value too; "Send pending (1)" button appears.
- [ ] Manual: try to delete a card from `CardsListView` → no delete affordance visible.

**Dependencies:** U6.

**Files touched:** `CardEditorSheet.swift` (changed), `CardsListView.swift` (changed if it has delete UI), `DeckDetailView.swift` (changed if applicable).

**Scope:** S.

---

### Phase 5: LibraryView New Deck flow

#### U8: `DictionaryPickerSheet` + LibraryView `+` rewiring; remove file import

**Description:** Replace the toolbar `+` direct file-import with a sheet that picks over locally-known canonical Dictionaries. **The `.fileImporter` and `handleImport` paths are deleted from `LibraryView`.**

**Acceptance criteria:**
- [ ] `Vohe/Views/DictionaryPickerSheet.swift` shows a list of all locally-known canonical pairs (parsed from `DictionaryStore.shared.allPairs()`). Each row → tap to open/create the Deck for that pair and navigate.
- [ ] `LibraryView`'s `+` toolbar button presents `DictionaryPickerSheet` instead of the direct file importer.
- [ ] `LibraryView` has **no** `.fileImporter` modifier and no `handleImport` function.
- [ ] If the user picks a pair with an existing Deck, navigate to that Deck (no duplicate creation).
- [ ] If the user picks a pair with no existing Deck, create a Deck named `<pair>` with parsed `language1`, `language2`, then run `DeckDictionaryProjector.sync(deck, ...)` so it's pre-populated.
- [ ] The pre-existing alert state for `importError` is removed (no more import failures to report).

**Verification:**
- [ ] Build clean.
- [ ] Manual: tap `+` → see picker → pick "Croatian-Italian" → Deck opens with all dictionary cards.
- [ ] Manual: confirm no UI path now triggers a Files-picker.

**Dependencies:** U7.

**Files touched:** `DictionaryPickerSheet.swift` (new), `LibraryView.swift` (changed).

**Scope:** S.

---

### Phase 5b: Post-sync cleanup

#### U10: `DictionarySuggestionStore.cleanup` + `DictionarySync` hook

**Description:** After a successful per-pair download in `DictionarySync.refresh`, run a cleanup pass that prunes suggestions canonical has adopted. Cleanup mutates `<P>.suggestions.json` (rewriting it with only still-pending entries).

**Acceptance criteria:**
- [ ] `DictionarySuggestionStore.cleanup(pair: P, canonicalEntries: [DictionarySuggestions.Entry], directory: URL) throws` removes:
  - additions whose `(f, b)` is now in canonical;
  - edits whose `edited` `(f, b)` is now in canonical (adopted — regardless of whether `original` also remains);
  - edits whose `original` and `edited` are both gone (stale).
  - Keeps only edits whose `original` is still in canonical AND `edited` is absent (still pending).
- [ ] `DictionarySync.refresh(...)` invokes cleanup for every pair it successfully updated, immediately after the atomic file swap and local-manifest write.
- [ ] After cleanup runs, `DictionaryStore.shared.reload()` is called (already done after a successful sync).
- [ ] Tests in `DictionarySuggestionStoreTests` cover the four cleanup outcomes (adopted addition; adopted edit; stale edit; still-pending edit).
- [ ] Tests in `DictionarySyncTests` cover the integration: after a sync that bumps a pair containing an addition matching the new canonical content, the addition file shrinks accordingly.

**Verification:**
- [ ] `xcodebuild test -only-testing:VoheTests/DictionarySuggestionStoreTests -only-testing:VoheTests/DictionarySyncTests` passes.
- [ ] Manual: add an entry that matches an upcoming canonical addition, simulate a sync that brings that entry into canonical, confirm the "mine" indicator disappears and the Send count drops by 1.

**Dependencies:** U6 (suggestions storage already exists; this extends it).

**Files touched:** `DictionarySuggestionStore.swift` (changed), `DictionarySync.swift` (changed), `DictionarySuggestionStoreTests.swift` (changed), `DictionarySyncTests.swift` (changed).

**Scope:** M.

---

### Phase 6: Migration (DESTRUCTIVE — review carefully)

#### U9: `UnificationMigration` — collapse multi-deck-per-pair, write non-canonical Cards to suggestions

**Description:** One-shot migration, gated by `UserDefaults.standard.bool(forKey: "vohe.dictionaryUnificationMigrationCompleted.v1")`. Invoked from `VoheApp.init` after the Leitner backfill.

**Acceptance criteria:**
- [ ] `Vohe/Services/UnificationMigration.swift` exposes `static func run(context: ModelContext, store: DictionaryStore, suggestionDirectory: URL)`:
  - Group all `Deck`s by `language1-language2`.
  - For each group with N≥1 Decks of pair P:
    - **If pair `P` has no canonical `<P>.txt`: delete every Deck in the group and skip the rest of the steps (orphan-pair drop, spec criterion 27). Do not create a `<P>.suggestions.json`.**
    - Pick the survivor: oldest `createdAt`.
    - Collect every Card's `(front, back)` across all decks in the group.
    - For each unique `(front, back)` not in the current canonical entries for P: append to `<P>.suggestions.json` as an addition (deduped against existing additions).
    - For each non-survivor deck D2: reassign its cards to the survivor, merging on `(front, back)` and preserving best-of Leitner state (max `boxIndex`, max `nextDue`, OR'd `wrongLastSession`). Delete D2.
  - Reload DictionaryStore.
  - For each surviving Deck, run `DeckDictionaryProjector.sync(D, ...)`.
- [ ] `VoheApp.init` calls migration after `runSchedulerBackfillIfNeeded` (and before kicking off `DictionarySync.refresh`).
- [ ] Tests in `VoheTests/UnificationMigrationTests.swift` cover spec criteria 23-28 using in-memory SwiftData.

**Verification:**
- [ ] `xcodebuild test -only-testing:VoheTests/UnificationMigrationTests` passes.
- [ ] Manual: with multiple Croatian-Italian decks pre-created, install build → first launch runs migration → confirm only one Croatian-Italian Deck remains; cards consolidated; Leitner state preserved for cards that had it.

**Dependencies:** U8.

**Files touched:** `UnificationMigration.swift` (new), `UnificationMigrationTests.swift` (new), `VoheApp.swift` (changed).

**Scope:** M-L. **DESTRUCTIVE — review this code separately before merging.**

---

### Checkpoint: Feature complete

- [ ] All spec criteria 1-29 verified manually or via tests.
- [ ] Migration smoke-tested with the actual on-device data (or at minimum a representative test fixture).
- [ ] Build clean, all tests pass.
- [ ] Follow-up: update `CONTEXT.md` glossary with Dictionary (canonical / user-owned), DictionaryEntry origin, Suggestion (additions + edits), Projection, Pending suggestions.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Migration eats user data (multi-deck collapse, Leitner state) | High | UnificationMigration tests cover best-of merge. Recommend user backup the SwiftData store before the first launch with migration. Migration is gated and idempotent. |
| Orphan-pair drop deletes decks for pairs with no canonical dictionary (criterion 27) | High | Intentional per the 2026-05-29 decision — DESTRUCTIVE and irreversible. Croatian-Italian is the only canonical pair today, so any other previously-imported pair is erased. Recommend the user back up the SwiftData store (and export any non-canonical deck) before first launch. Gated and idempotent. |
| Card edit recorded as a suggestion when the user meant a private fix | Medium | Edits are visible in the per-pair "Send pending" count; user can decide not to send. v3 could add "Discard this suggestion" UI. |
| Stale-edit drop confuses the user ("I made this change last week, it vanished after a sync") | Medium | Visible only after `DictionarySync` rewrites the canonical file. Add a CONTEXT.md note; revisit if it becomes a real complaint. |
| Cleanup race: sync runs concurrently with user adding a suggestion | Low | Cleanup is invoked from `DictionarySync.refresh` after the file swap, on the same Task. User Add via DictionaryView runs on MainActor. If the user adds an entry while sync is mid-flight, the addition lands after cleanup completes (next reload picks it up). No conflict. |
| Deduplication misses (canonical `(f, b)` differs from addition `(f, b)` by whitespace or case) | Low | Use trimmed, exact case comparison consistent with `DeckParser`. Spec already says "deduplicate by `(front, back)`" — exact-match. |
| Card delete removal breaks existing user reflex | Low | Document in release notes. Users who hit Box 5 too often can rely on Good-grading to keep cards parked. |

## Open Questions

- **Migration: rename survivor Deck or keep its existing name?** Survivor keeps its name by default. If the user has multiple decks named distinctly ("Croatian-Italian-Beginner" and "Croatian-Italian-Advanced"), the older one's name survives. Acceptable trade-off; user can rename post-migration.
- **`+ Add entry` UI placement** — top of each pair section, footer, or floating action button? Decide visually during U5.
- **Suggestion file location vs. canonical file** — same directory. Naming convention `<P>.suggestions.json` keeps them adjacent. Reasonable.
- ~~**CONTEXT.md update** — defer until U9 lands.~~ **Done (2026-05-29)** ahead of U9: glossary updated for the Dictionary/projection model.

## Parallelization Opportunities

- **U1 (cleanup)** is independent of everything; can run while Phase 1 is being implemented in a second session.
- **U2, U3** must be sequential (U3 depends on U2's types).
- **U4** depends on U3.
- **U5, U6, U7** can be done in parallel with each other if needed, but each depends on U4.
- **U8** depends on U7 (clean state in DeckDetailView).
- **U9** is last — destructive, depends on the entire new model being in place.

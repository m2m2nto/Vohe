# Spec: Reference Dictionary (v2)

> **v2 (2026-05-29):** Major restructuring. Decks are now projections of Dictionaries (1:1 per language pair). User edits and additions both flow through a unified per-pair suggestions queue sent to the maintainer. The v1 "Copy entry to Deck" affordance and per-Deck "Send to maintainer" surface are removed. See [`docs/adr/0004-dictionary-projection-and-unified-suggestions.md`](../adr/0004-dictionary-projection-and-unified-suggestions.md).

## Objective

Vohe's vocabulary data model unifies around language pairs. For each pair (`Croatian-Italian`, `Italian-French`, …) there is exactly one Dictionary and at most one Deck. The Dictionary holds the vocabulary content; the Deck is a projection that adds Leitner state. Users browse and grow the Dictionary inside `DictionaryView`; they learn in `SessionView` driven by the projected Deck.

**All Dictionaries are canonical** — bundled with the app and refreshed at runtime via the manifest pull from ADR-0003. There is no user-owned Dictionary concept. The maintainer is the sole source of new language pairs. The `.fileImporter`-based "import a .txt" path is removed.

The user can:

- Add a new entry via `DictionaryView` → appears immediately in the Dictionary and in the matching Deck, marked as the user's own (blue dot) until post-sync cleanup adopts it.
- Edit an existing entry's front/back (either in `DictionaryView` directly OR in the existing `CardEditorSheet` inside a Deck) → appears immediately, marked as the user's own (blue pencil), AND is logged as a "suggested correction" for the maintainer.
- Tap **Send pending to maintainer** on a Dictionary section → iOS share sheet exports just that pair's suggestions (additions + edits) for the maintainer to hand-merge. The Send button shows a **red-dot badge** while there's at least one pending suggestion in that pair.

**Card deletion is removed app-wide.** Decks mirror Dictionaries; deleting a Card would just be re-added on the next reload. The card-delete affordance is also removed from `CardsListView` and any other surface that previously offered swipe-to-delete on Cards. Users who want a smaller learning queue rely on Leitner (Good-grading pushes a card to Box 5; it surfaces every 60 days).

**See also:**
- [`docs/adr/0002-dictionary-contributions-via-share-sheet.md`](../adr/0002-dictionary-contributions-via-share-sheet.md) — contribution mechanism (share sheet) still stands; only the granularity changes.
- [`docs/adr/0003-dictionary-updates-via-runtime-pull.md`](../adr/0003-dictionary-updates-via-runtime-pull.md) — runtime pull mechanism unchanged.
- [`docs/adr/0004-dictionary-projection-and-unified-suggestions.md`](../adr/0004-dictionary-projection-and-unified-suggestions.md) — this pivot.

## Tech Stack

Unchanged: SwiftUI + SwiftData, iOS 26, xcodegen. Remote sync via `URLSession.shared` against `raw.githubusercontent.com`.

## Project Structure (new + changed since v1)

```
Vohe/
  Models/
    DictionaryEntry.swift            [CHANGED] adds `origin: Origin` enum (canonical, userAddition, canonicalWithEdit)
    DictionaryManifest.swift         [UNCHANGED]
    DictionarySuggestions.swift      [NEW]     per-pair Codable bag of additions + edits
    Card.swift                       [UNCHANGED] but Leitner state now coexists with auto-add from Dict
    Deck.swift                       [UNCHANGED]
  Services/
    DictionaryStore.swift            [CHANGED] reads canonical + suggestions per pair, merges, exposes per-pair entries
    DictionarySync.swift             [CHANGED] invokes SuggestionCleanup after a successful per-pair download
    DictionarySuggestionStore.swift  [NEW]     read/write/cleanup <pair>.suggestions.json
    DeckExporter.swift               [REMOVED] superseded by DictionarySuggestionStore + the in-Dictionary share path
    DeckDictionaryProjector.swift    [NEW]     reconciles a Deck's Cards against its pair's Dictionary entries
    UnificationMigration.swift       [NEW]     one-shot: collapse multi-deck-per-pair into single Decks
  Views/
    DictionaryView.swift             [CHANGED] adds Add Entry sheet + Send Pending button per pair, with badge
    DictionaryEntryRow.swift         [CHANGED] adds origin marker (blue dot / pencil); swipe-trailing → Edit
    AddDictionaryEntrySheet.swift    [NEW]     simple form: front + back, used for both add and edit
    LibraryView.swift                [CHANGED] `+` opens DictionaryPickerSheet; .fileImporter removed
    DictionaryPickerSheet.swift      [NEW]     picker over locally-known canonical Dictionaries
    DeckDetailView.swift             [CHANGED] removes "Send to maintainer" section; removes card delete affordance
    CardsListView.swift              [CHANGED] removes swipe-to-delete; surfaces origin marker per Card row
    CardEditorSheet.swift            [CHANGED] when editing a dictionary-backed card, save also logs a suggestion edit
    ShareSheetView.swift             [UNCHANGED]
  VoheApp.swift                      [CHANGED] runs UnificationMigration once after Leitner backfill

VoheTests/
  DictionaryStoreTests.swift         [CHANGED] expanded coverage for merge logic (canonical + suggestions)
  DictionarySuggestionStoreTests.swift [NEW]
  DeckDictionaryProjectorTests.swift [NEW]
  UnificationMigrationTests.swift   [NEW]
  DeckExporterTests.swift            [REMOVED]
```

## Code Style

Unchanged. New types follow the same patterns: value structs for pure data, `enum` services with `static` functions, `final class` only for stateful singletons.

## Behavior Specification

### Storage layout

```
<App Support>/Dictionaries/
  manifest.json                          ← canonical manifest (versions per pair, written by sync)
  Croatian-Italian.txt                   ← canonical entries (sync overwrites wholesale)
  Croatian-Italian.suggestions.json      ← user adds + edits for this pair (sync never touches)
```

**Every pair is canonical** — listed in `manifest.json` with a `<pair>.txt` file maintained by `DictionarySync`. A `<pair>.suggestions.json` only ever accompanies a canonical `<pair>.txt`; there are **no suggestions-only (user-owned) pairs**. Migration drops any legacy Deck whose pair has no canonical dictionary (criterion 27), so this invariant holds from first launch.

### Suggestion schema

`<pair>.suggestions.json`:

```json
{
  "additions": [
    { "front": "fluxus", "back": "flusso" }
  ],
  "edits": [
    { "original": { "front": "rosso", "back": "red"  },
      "edited":   { "front": "rosso", "back": "rosa" } }
  ]
}
```

- **Additions** are net-new entries the user created. They have no canonical counterpart.
- **Edits** record a replacement: the canonical `original` is rewritten to `edited` for display and projection purposes.
- Both lists are appended to (never reordered or compacted by the app). Deduplication on send happens client-side; the maintainer is the canonical reconciler.

### Read-time merge (DictionaryStore.load)

For each pair `P`:

1. Read canonical entries from `<P>.txt` if present.
2. Read `<P>.suggestions.json` if present.
3. Apply each `edit`: find a canonical entry where `(front, back) == edit.original`; replace its values with `edit.edited`. If no matching canonical entry exists, drop the edit silently (it's stale — the maintainer already adopted or rejected it, and remote pull rewrote the file).
4. Append each `addition` as a `DictionaryEntry` with `origin = .userAddition`.
5. Canonical entries that were edited are marked `origin = .canonicalWithEdit`. Untouched canonical entries are `origin = .canonical`.
6. Deduplicate by `(front, back)`: when both a canonical entry and a user addition share the same `(front, back)`, **the user addition wins over canonical**. The kept entry has `origin = .userAddition`. The user's local annotation (the "mine" indicator) persists until the next post-sync cleanup determines the addition has been adopted upstream and prunes it from `<P>.suggestions.json`.

### Deck-Dictionary projection (DeckDictionaryProjector.sync)

Invoked on every `DictionaryStore.reload()` and from `UnificationMigration`:

For each Deck `D` of pair `P`:

- For every Dictionary entry `E` in `P` not represented by a Card in `D` → insert a new Card with `E.front`, `E.back`, `boxIndex = 0`, `nextDue = .distantPast`.
- For every Card `C` whose `(front, back)` matches an `edit.original` in `P`'s suggestions → rewrite `C.front, C.back` to the `edited` values. **Leitner state preserved.**
- Cards in `D` that have no matching Dictionary entry **are left untouched** (defensive — they pre-existed from a pre-migration deck or from a card the user just typed in `CardEditorSheet`).

### User actions

**Add entry (`DictionaryView` → `+ Add`):**
1. Sheet collects `front`, `back`.
2. Append to `<P>.suggestions.json` additions.
3. `DictionaryStore.reload()` → in-memory list now includes it.
4. `DeckDictionaryProjector.sync(D)` for each Deck of pair `P` → Deck gains a new box-0 Card.

**Edit entry (`DictionaryView` → trailing swipe → Edit, OR `CardEditorSheet` save on a dictionary-backed Card):**

Discovery: the `Edit` action is exposed via SwiftUI `.swipeActions(edge: .trailing)` on each `DictionaryEntryRow` — no long-press. Tapping it opens the same sheet used for `+ Add`, pre-populated with the entry's current values.
1. Capture `originalFront, originalBack, newFront, newBack`.
2. If `original == new`, no-op.
3. Append to `<P>.suggestions.json` edits.
4. `DictionaryStore.reload()` → entry now displays edited values.
5. `DeckDictionaryProjector.sync(D)` → matching Card's `front`/`back` updated, Leitner state preserved.

**Send pending suggestions (`DictionaryView` → `↑ Send` button on a pair's section):**
1. Read `<P>.suggestions.json`.
2. Write a tempfile `vohe-<pair>-suggestions-<yyyy-MM-dd>.json` to `FileManager.default.temporaryDirectory`.
3. Present iOS share sheet via `ShareSheetView` with the tempfile URL.
4. Local suggestions file is **not** mutated on send. Entries stay locally until the post-sync cleanup determines they've been adopted upstream.

**Send button badge.** When pair `P` has at least one pending suggestion (`additions.count + edits.count > 0`), the Send button shows a **red dot badge** (`.badge` modifier or an overlay red circle in the top-right of the button) to draw attention. The badge disappears when the queue empties — either because the user-cleaned everything OR because post-sync cleanup pruned all adopted suggestions. The badge is purely visual; the count is still shown inline as `Send pending (n)` for clarity.

**Post-sync suggestion cleanup:**
After every successful `DictionarySync.refresh()` that writes a new `<P>.txt`, a cleanup pass runs against `<P>.suggestions.json`:

- For each **addition** `(f, b)`: if canonical `<P>.txt` now contains `(f, b)`, the addition is **removed** from the suggestions file. The maintainer adopted it.
- For each **edit** `{ original: (f1, b1), edited: (f2, b2) }` — **keep only when still pending, i.e. `(f1, b1)` is in canonical AND `(f2, b2)` is not; otherwise remove:**
  - If canonical now contains `(f2, b2)`, the edit is treated as adopted → **remove** — *regardless of whether `(f1, b1)` also remains*. (The edited value appearing in canonical is taken as adoption.)
  - If canonical contains neither `(f1, b1)` nor `(f2, b2)` (entry dropped entirely, or maintainer changed it to something else), the edit is stale → **remove**. User can re-suggest if needed.
  - Otherwise (`(f1, b1)` present, `(f2, b2)` absent), the edit is still pending → **keep**.

After cleanup, `DictionaryStore.reload()` runs. The user's "mine" indicator disappears for entries that were pruned — the user-perceived effect is: "my suggestion was accepted and is now part of the official dictionary."

Cleanup is purely a write operation on `.suggestions.json`; canonical `.txt` is never touched by cleanup. If cleanup fails (write error), the next sync will retry — no data loss, just one extra cycle of the indicator visible.

### Visual marking of user entries

Entries in `DictionaryView` are visually marked according to their `origin`:

| Origin | Mark | Meaning |
|---|---|---|
| `.canonical` | none | Standard entry from the bundled/synced dictionary. |
| `.userAddition` | leading-edge **blue dot** | User added this; still pending upstream adoption. |
| `.canonicalWithEdit` | leading-edge **blue pencil** (`pencil.tip`) | Canonical entry the user has rewritten; still pending. |

The same marking carries to the projected Card row in `CardsListView` so the user always knows which content is theirs vs. the maintainer's. (In-Session card front and `WrongCardsView` are out of scope for v2.) The mark disappears the moment post-sync cleanup adopts the entry into canonical.

### Library entry-points

`LibraryView`'s `+` toolbar button opens a **picker over locally-available canonical Dictionaries**. Picking a pair:
- If a Deck for that pair already exists → push `DeckDetailView` for it.
- Otherwise → create a Deck named `<pair>` with parsed `language1, language2`, run `DeckDictionaryProjector.sync(deck, ...)` to pre-populate it with all current Dictionary entries, then push.

**File import is removed.** The `.fileImporter` modifier and `handleImport` flow in `LibraryView` are deleted. The only path for new vocabulary content into the app is the maintainer publishing it via the runtime manifest pull (ADR-0003). Users who want a new language pair: ask the maintainer.

### Sync behavior (unchanged from v1)

`DictionarySync.refresh()` is unchanged: fetch remote manifest, per-pair version compare, download newer, SHA verify, atomic swap, update local manifest. Only canonical `<pair>.txt` files are touched. `.suggestions.json` files are inert to sync.

### Out of scope for v2

- File import path (`.fileImporter`, `handleImport`) — removed entirely. All vocabulary content now flows from the maintainer via the runtime manifest.
- User-owned Dictionaries (Dictionaries with no canonical `<P>.txt`) — concept removed; the only Dictionaries are canonical.
- Per-Card "soft hide" (a way to exclude a Card from a Deck's queue without deleting it). Cards retreat to Box 5 via Leitner; that's the only escape. Revisit if it becomes a friction point.
- Suggestion conflict resolution where canonical contains `(f, b)` with a different value than the user's addition for the same `(f, b)`. v2 keeps the user addition (per merge rule § Read-time merge step 6); the user can decide to drop their addition by editing it out via the Dictionary UI (no-op delete TBD if needed).
- Manual "Promote my suggestion to local-only" (i.e., reject the canonical version and keep my edit). Edits live until canonical pull moves past them; no way to pin.
- Multi-pair "Send all my suggestions" — send is per-pair.
- Suggestion editing/deleting before send (you commit when you tap save). Revisit if false-positive suggestions become an issue.

## Testing Strategy

Add tests under the existing `VoheTests` target:

- `VoheTests/DictionaryStoreTests.swift` — **expanded.** Merge logic: canonical only; canonical + additions; canonical + edits; canonical + both; user-owned (no canonical); stale-edit drop on canonical change.
- `VoheTests/DictionarySuggestionStoreTests.swift` — **new.** Read/write round-trip; append-without-clobber; pair-of-doesnt-exist-yet creation; malformed JSON tolerance.
- `VoheTests/DeckDictionaryProjectorTests.swift` — **new.** New Dictionary entry → new Card box 0; edit propagates front/back keeping Leitner state; pre-existing card not matching any entry is left untouched; multiple Decks of same pair (transitional) both get the new Card.
- `VoheTests/UnificationMigrationTests.swift` — **new.** Single deck per pair (no-op); multiple decks per pair (merge to one, best-of Leitner state); decks with cards not in canonical (entries land in `.suggestions.json` as additions); idempotent (running twice no-ops).
- `VoheTests/DeckExporterTests.swift` — **removed.**

## Boundaries

**Always:**
- Use `DeckParser.parse` for canonical `.txt` files. `DictionarySuggestionStore` uses its own JSON path (Codable).
- `DictionarySync` writes only to `<pair>.txt` and `manifest.json`. It invokes `DictionarySuggestionStore.cleanup(pair:canonicalEntries:)` after a successful per-pair download, but cleanup is the sole legitimate caller that writes to `.suggestions.json` outside user actions.
- `DeckDictionaryProjector.sync(D)` must be additive on entries (never delete a Card whose entry is gone — it might be from a future canonical-pull that dropped the entry, but the user's Leitner state still has value).
- `UnificationMigration` is one-shot, gated by `UserDefaults.standard.bool(forKey: "vohe.dictionaryUnificationMigrationCompleted.v1")`.
- Card deletion is **never** offered in any UI (DeckDetailView, CardsListView, WrongCardsView, CardEditorSheet). Swipe-to-delete is removed from every Card list.

**Ask first:**
- Adding a "Pending suggestions" badge to the Library row showing the count of un-sent suggestions across pairs.
- Adding a way to inspect or delete individual pending suggestions before sending.
- Re-introducing any path that lets the user add a language pair the maintainer hasn't shipped (e.g., a "create new pair" affordance).

**Never:**
- Mutate `<pair>.suggestions.json` from any code path other than user actions in `DictionaryView` / `CardEditorSheet` OR `DictionarySuggestionStore.cleanup` invoked from `DictionarySync`.
- Trust the suggestions file's contents implicitly when reading. Malformed JSON → treat as empty suggestions for that pair, log, continue.
- Apply suggestions from one pair to a different pair. Edits and additions are pair-local.
- Re-introduce a Card delete affordance anywhere in the UI.

## Success Criteria

Numbered for traceability.

### Storage and merge

1. **Canonical-only load.** Pair with `<P>.txt` and no `.suggestions.json` loads to N entries, all `origin = .canonical`.
2. **Addition shows up.** After `DictionarySuggestionStore.appendAddition(pair: P, front: f, back: b)`, `DictionaryStore.reload()` exposes the pair with N+1 entries; the new one has `origin = .userAddition`.
3. **Edit replaces canonical display.** After `appendEdit(pair: P, original: (f1,b1), edited: (f2,b2))`, the entry that was `(f1,b1)` now reads `(f2,b2)` with `origin = .canonicalWithEdit`. Total entry count unchanged.
4. **Stale edit drop.** If canonical no longer contains an entry matching `edit.original` (because remote sync replaced the file), the edit is silently dropped on next reload (entry list shows no ghost of it).
5. **Deduplication — user addition wins.** If canonical contains `(f,b)` and an addition is `(f,b)`, the merged result has exactly one entry, marked `origin = .userAddition`. The user's "mine" indicator stays visible until post-sync cleanup determines the addition has been adopted and prunes it.
6. **Origin marker on every row.** `DictionaryEntryRow` shows a blue dot for `.userAddition`, a blue pencil for `.canonicalWithEdit`, and nothing for `.canonical`. The same marker appears on the corresponding `Card` row in `CardsListView`.

### Deck projection

7. **New entry → new Card.** Adding an entry to Dictionary `P` results in every Deck of pair `P` gaining a Card with the new `(front, back)`, `boxIndex = 0`, `nextDue = .distantPast`.
8. **Edit propagates to Cards keeping Leitner state.** A Card at `(f1, b1)` with `boxIndex = 3, nextDue = 2026-06-15` after an edit to `(f2, b2)` becomes a Card with `(f2, b2), boxIndex = 3, nextDue = 2026-06-15`.
9. **Pre-existing non-matching Cards untouched.** A Card with `(front, back)` not in any Dictionary entry of its pair remains in the Deck with full state (defensive — only happens transitionally).
10. **Idempotent projection.** Running `DeckDictionaryProjector.sync(D)` twice in a row yields the same Deck state.

### Suggestions send and cleanup

11. **Send exports tempfile.** Tapping "Send pending" on pair `P` writes `vohe-<P>-suggestions-<yyyy-MM-dd>.json` to tempdir matching `<P>.suggestions.json` bytes (Codable round-trip), and presents the iOS share sheet with that file URL.
12. **Send is non-destructive.** After send, `<P>.suggestions.json` is byte-identical to before. Entries persist until post-sync cleanup adopts them.
13. **Send button always visible; badge carries the signal.** The per-pair "Send pending (n)" button is always shown. When pair `P` has zero additions and zero edits it carries **no** badge and is disabled (tapping it does nothing); the red-dot badge and an active tap appear only when there's at least one pending suggestion.
14. **Send button red-dot badge.** When pair `P` has at least one pending suggestion, the Send button shows a red-dot badge. The badge disappears when the queue empties (user removed entries OR post-sync cleanup pruned them).
15. **Post-sync addition cleanup.** After `DictionarySync.refresh()` successfully writes a new `<P>.txt`, every addition whose `(f, b)` is now present in canonical is removed from `<P>.suggestions.json`.
16. **Post-sync edit cleanup.** After sync, an edit is **kept only if its `original` is still present in canonical AND its `edited` values are absent** (still pending). Every edit whose `edited` values appear in canonical is removed (adopted), even if `original` also remains. Edits whose `original` and `edited` are both absent are removed (stale).

### Library / Deck creation

17. **Open Dictionary as Deck — new.** Picker shows all canonical pairs known locally. Tapping a pair with no existing Deck creates one named `<P>` with `(language1, language2)` parsed from the pair string, and immediately projects every Dictionary entry into Cards.
18. **Open Dictionary as Deck — existing.** Tapping a pair that already has a Deck pushes that Deck's detail view; no duplicate created.
19. **No file import path.** `LibraryView` has no `.fileImporter` modifier; tapping `+` opens only the dictionary picker. There is no UI for adding a language pair the maintainer hasn't shipped.

### Card delete removal

20. **No swipe-to-delete on Cards.** `CardsListView`, `WrongCardsView`, and any other Card list expose no delete affordance. SwiftUI `.onDelete` modifiers on Card rows are removed.
21. **No card-delete button in CardEditorSheet.** The card editor exposes only Save and Cancel; no destructive action.
22. **DeckDetailView no longer has a per-Card delete in any contextual menu.** Deck-level delete (removing an entire Deck) is **not affected** by this rule — that's a separate, intentional affordance.

### Migration

23. **Migration gate.** `UnificationMigration.run` is invoked once from `VoheApp.init` after the Leitner backfill, gated by `UserDefaults.standard.bool(forKey: "vohe.dictionaryUnificationMigrationCompleted.v1")`. Subsequent launches no-op.
24. **Single-deck-per-pair no-op.** If existing decks already satisfy 1-per-pair, migration only ensures projection (no Card data lost, no Deck deleted).
25. **Multi-deck-per-pair merge.** If two Decks `D1` and `D2` exist for pair `P`, migration produces one Deck (the older `createdAt` survives by default). Cards unioned by `(front, back)`. For duplicates, Leitner state = best-of: max `boxIndex`, max `nextDue`, `wrongLastSession = D1.flag OR D2.flag`. `D2` is deleted.
26. **Migration captures non-canonical entries.** Cards in pre-migration decks whose `(front, back)` is not in canonical `<P>.txt` are written to `<P>.suggestions.json` as additions, deduplicated against any already-present additions.
27. **Migration drops orphan pairs.** Pre-migration Decks for a pair that has **no canonical `<P>.txt`** (e.g. a legacy file-imported pair the maintainer never shipped) are **deleted** during migration, along with every card they hold. No `.suggestions.json` is written for such a pair. A `.suggestions.json` therefore only ever exists alongside a canonical `<P>.txt`. This drop is destructive, one-shot, and gated by the same migration flag — see the migration risk note in the plan.
28. **Migration is idempotent.** Re-running (via toggling the UserDefaults flag for tests) produces no further changes.

### Regression guards

29. **Existing acceptance criteria.** All criteria in `SPEC.md` and `docs/specs/spaced-repetition-leitner.md` continue to hold post-migration. Sessions still launch, reminders still fire, Practice Hardest still uses `DifficultyStore`.

## Resolved Decisions (carried + new)

Carried from v1:
- Canonical pair v1: `Croatian-Italian`, bundled verbatim from `samples/Croatian-Italian.txt`.
- Hosting: `raw.githubusercontent.com/m2m2nto/Vohe/main/Vohe/Resources/Dictionaries/manifest.json`.
- Sync trigger: launch fire-and-forget + DictionaryView pull-to-refresh.
- DictionaryStore lifecycle: eager `shared`.
- Sync failure handling: silent.

New in v2:
- Decks are 1:1 with Dictionaries by language pair. Existing multi-deck-per-pair user data is hard-merged on first launch post-pivot.
- Card edits flow through the per-pair suggestion queue (additions + edits unified).
- Card delete affordance removed everywhere (no swipe-to-delete on any Card list, no delete button in card editor).
- File import path removed entirely. The only source of new language pairs is the maintainer publishing via the runtime manifest.
- "Send to maintainer" moves from `DeckDetailView` to `DictionaryView`, per pair, with a red-dot badge while there are pending entries.
- Dictionary deduplication: user addition wins over canonical (origin stays `userAddition`); a post-sync cleanup pass prunes adopted additions/edits from `<P>.suggestions.json`.
- Visual: user-added entries show a blue dot, user-edited entries show a blue pencil, on both DictionaryEntryRow and the corresponding CardsListView row.
- Edit affordance in DictionaryView is a trailing-swipe action (not long-press).
- T5 (CopyToDeckSheet) and T6 (DeckExporter + per-Deck send section) deleted.
- **Orphan pairs are dropped on migration** (2026-05-29). Decks for a pair with no canonical dictionary are deleted; suggestions-only (user-owned) pairs do not exist. The "user-owned Dictionary" concept is fully removed, not just frozen — destructive, accepted because the user is the sole data owner and Croatian-Italian is the only canonical pair today.
- **Edit-adoption rule is `edited`-present** (2026-05-29). Post-sync cleanup treats an edit as adopted whenever its `edited` value appears in canonical, regardless of whether `original` also remains. Keep an edit only while `original` is present and `edited` is absent.

## Open Questions

- **Deck rename under the new model.** Allowed (user can rename freely) but the pair binding is immutable. UI for changing pair would mean migrating Leitner state — not in v2.
- **"Send all pairs in one shot" affordance.** Could exist alongside per-pair send if the user contributes to many pairs. Not in v2.
- **Soft-hide (exclude card from queue without delete).** Worth revisiting if Box-5 backlog becomes a real friction.
- **Discarding a pending suggestion before send.** Currently no UI to undo an addition or edit before send. If false-positive suggestions become an issue, add per-row delete in the "pending" view.
- **Suggestion-conflict semantics.** When canonical adopts a `(f, b)` with a different value than the user's pending addition for the same `(f, b)`, current rule keeps the user's value. If this surfaces real confusion, revisit (warn? show both? force-resolve?).
- ~~**CONTEXT.md updates.**~~ **Done (2026-05-29):** glossary gained a Dictionary section (Dictionary, DictionaryEntry, Origin, Projection, Suggestion, Pending suggestions, Post-sync cleanup), the Deck/Card terms were updated for the projection model, and "Library surfaces" notes the `+` picker.

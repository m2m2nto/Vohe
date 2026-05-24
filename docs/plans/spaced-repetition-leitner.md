# Implementation Plan: Spaced Repetition (Calendar-Leitner)

## Overview

Replace the wrong-last-session carryover with a 5-box calendar-Leitner scheduler. Add a global "Review (N due)" surface on Library home. State lives on the SwiftData `Card` model; backfill runs once on first launch after upgrade.

Source spec: [`docs/specs/spaced-repetition-leitner.md`](../specs/spaced-repetition-leitner.md). Source one-pager: [`docs/ideas/spaced-repetition-leitner.md`](../ideas/spaced-repetition-leitner.md).

## Architecture Decisions

- **Scheduler state on `Card`, not in JSON.** `boxIndex: Int = 0, nextDue: Date = .distantPast`. Required because the global Review query needs a fast cross-deck predicate; per-card JSON would force N file reads on every Library refresh.
- **One-shot migration gated by UserDefaults flag** (`vohe.schedulerBackfillCompleted.v1`). Runs synchronously on first launch post-upgrade. No UI.
- **`SessionView` becomes deck-optional.** v1 supports per-deck and global modes. Global mode disables pause/resume (Cancel only offers Discard) AND does not persist `SessionResult`. Per-card writes (box/due/wrongLastSession/DifficultyStore) still happen on every swipe.
- **"Review (N due)" hides its count when N > 100** (row reads "Review"); avoids the streak-anxiety the README disclaims. Underlying queue size is still N.
- **Within-session reinforcement is in-memory only.** Re-queue appends to `order: [Card]`; `againCountThisSession: [UUID: Int]` is `@State`, not persisted. Box/due update writes happen on the *first* grade per card per session.
- **Tests:** Add a `VoheTests` XCTest target via `project.yml` + xcodegen. Scheduler and migration get unit tests; UI changes get manual smoke tests.

## Task List

### Phase 1: Foundation

#### Task 1: Add `VoheTests` target

**Description:** Add an XCTest target via `project.yml` so the rest of the work can be test-driven. Regenerate the Xcode project via xcodegen. Write a one-line smoke test to confirm the test target runs.

**Acceptance criteria:**
- [ ] `project.yml` declares a `VoheTests` target of type `bundle.unit-test`, sources from `VoheTests/`, host = `Vohe`.
- [ ] `xcodegen generate` succeeds without disturbing the existing `Vohe` target's signing/team/bundleID block (memory note: signing config is hand-maintained).
- [ ] `VoheTests/SmokeTest.swift` contains a trivial test (`XCTAssertEqual(1+1, 2)`) that passes.

**Verification:**
- [ ] Build: `xcodebuild -project Vohe.xcodeproj -scheme Vohe -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO`
- [ ] Test: `xcodebuild test -project Vohe.xcodeproj -scheme Vohe -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0'`
- [ ] Manual: open `project.yml` and confirm the `Vohe` target's settings block (DEVELOPMENT_TEAM, CODE_SIGN_STYLE, etc.) is byte-for-byte unchanged. **Hand off to user for this verification — signing config is user-maintained.**

**Dependencies:** None.

**Files likely touched:** `project.yml`, `VoheTests/SmokeTest.swift` (new), regenerated `Vohe.xcodeproj/` (gitignored).

**Scope:** S.

---

#### Task 2: Add `boxIndex` and `nextDue` to `Card`

**Description:** Add two SwiftData properties to `Card` with defaults. Verify lightweight migration succeeds against an existing store.

**Acceptance criteria:**
- [ ] `Card.swift` declares `var boxIndex: Int = 0` and `var nextDue: Date = .distantPast`.
- [ ] The `init(front:back:)` constructor leaves both at their defaults (no signature change).
- [ ] Existing stored cards from a pre-upgrade DB open without error after upgrade. (**Success criterion 1**)

**Verification:**
- [ ] Build clean.
- [ ] Manual smoke: install the current `main` build, import the 745-card Croatian-Italian deck, quit. Switch to this branch, build & run. Library shows the deck; opening it shows all cards intact.

**Dependencies:** Task 1.

**Files likely touched:** `Vohe/Models/Card.swift`.

**Scope:** XS.

---

#### Task 3: Implement `LeitnerScheduler` with unit tests

**Description:** A pure `enum` with no SwiftData/UI dependencies. Handles box transitions and due-date math, anchored on local start-of-day.

**Acceptance criteria:**
- [ ] `Vohe/Services/LeitnerScheduler.swift` exposes `intervalsByBox: [Int]`, `maxBox: Int`, `Grade { case again, good }`, and `apply(grade:currentBox:now:calendar:) -> (box: Int, due: Date)`.
- [ ] `apply(grade: .good, currentBox: 2, ...)` returns box 3, due = startOfDay(now) + 7d. (**Success criterion 4**)
- [ ] `apply(grade: .good, currentBox: 5, ...)` returns box 5, due = startOfDay(now) + 60d (no overflow). (**Success criterion 4**)
- [ ] `apply(grade: .again, currentBox: <any>, ...)` returns box 1, due = startOfDay(now) + 1d. (**Success criterion 5**)
- [ ] Calling `apply` at 23:55 with a +1d interval returns a due date equal to `startOfDay(today) + 1d` (= midnight tomorrow), so a card reviewed late at night is due at 00:00. (**Success criterion 15**)

**Verification:**
- [ ] Unit tests in `VoheTests/LeitnerSchedulerTests.swift` covering each criterion above. All pass via `xcodebuild test`.
- [ ] Build clean.

**Dependencies:** Task 1.

**Files likely touched:** `Vohe/Services/LeitnerScheduler.swift` (new), `VoheTests/LeitnerSchedulerTests.swift` (new).

**Scope:** S.

---

### Checkpoint: Foundation

- [ ] `xcodebuild build` and `xcodebuild test` both succeed.
- [ ] `git diff project.yml` shows ONLY a `VoheTests:` target addition — no changes to the `Vohe:` target's `settings.base` block.
- [ ] Existing app still launches and shows existing decks.

---

### Phase 2: Backfill

#### Task 4: Implement `SchedulerMigration` with unit tests

**Description:** Pure function (or static method) that takes the SwiftData `ModelContext` and `DifficultyStore`, walks all `Card`s, and assigns `boxIndex` + `nextDue` per the spec's wrong-rate buckets. Stagger non-zero boxes randomly across the next 7 days.

**Acceptance criteria:**
- [ ] `Vohe/Services/SchedulerMigration.swift` exposes a static method `run(context: ModelContext, store: DifficultyStore, today: Date = .now)`.
- [ ] Cards with no stats or `seen < 3` → `boxIndex = 0, nextDue = .distantPast`. (**Success criterion 2**)
- [ ] Cards with `wrongRate < 0.2` → `boxIndex = 3`; `< 0.4` → `boxIndex = 2`; else → `boxIndex = 1`. (**Success criterion 2**)
- [ ] All assigned cards (box 1–3) have `nextDue ∈ [startOfDay(today), startOfDay(today) + 7d)`. No more than `ceil(assignedCount / 7)` cards share the same `nextDue`. (**Success criterion 3**)

**Verification:**
- [ ] Unit tests in `VoheTests/SchedulerMigrationTests.swift`: build an in-memory `ModelContainer`, insert decks + cards, seed `DifficultyStore` with known stats, run migration, assert box assignments + staggering.
- [ ] Tests pass via `xcodebuild test`.

**Dependencies:** Tasks 2, 3.

**Files likely touched:** `Vohe/Services/SchedulerMigration.swift` (new), `VoheTests/SchedulerMigrationTests.swift` (new).

**Scope:** S.

---

#### Task 5: Wire migration into app launch

**Description:** Call `SchedulerMigration.run` once on first launch after upgrade, gated by a `UserDefaults` flag. Migration must complete before the first view appears.

**Acceptance criteria:**
- [ ] On a fresh install, `UserDefaults.standard.bool(forKey: "vohe.schedulerBackfillCompleted.v1") == true` after first launch.
- [ ] On a second launch, migration does not run again (verified by adding a `print`/breakpoint, or by `DifficultyStore` not being re-read — easiest via instrumentation in dev only).
- [ ] On an upgrade from current `main` (with 745 imported cards), the migration completes in under 1s and the Library appears with cards box-classified per Task 4. (**Success criterion 1, 2, 3**)

**Verification:**
- [ ] Manual smoke: install `main` build, import the sample 745-card deck, quit. Build this branch, run. Inspect a few cards via a debug print or SwiftUI dev menu showing `boxIndex` (or check via DB inspector). Confirm ~5–7 buckets of due dates spread across the week.

**Dependencies:** Task 4.

**Files likely touched:** `Vohe/VoheApp.swift`.

**Scope:** XS.

---

### Checkpoint: Backfill

- [ ] Manual smoke: upgrade path shows expected backfill behavior on the real 745-card deck.
- [ ] No more than `ceil(N/7)` cards share a `nextDue` date.
- [ ] `xcodebuild test` still passes.

---

### Phase 3: Per-deck session integration

#### Task 6: `SessionView.buildOrder` uses scheduler (per-deck non-`onlyHardest` path)

**Description:** Replace the current `wrong + rest` ordering with `due + new + undue` partitioning. Update `advance(wasCorrect:)` to call `LeitnerScheduler.apply` and persist the new box/due via the existing `context.save()` chain. Leave `wrongLastSession` writes in place (per spec — keep around for rollback).

**Acceptance criteria:**
- [ ] In `SessionView.buildOrder()`, the non-`onlyHardest` path partitions `deck.cards` into `due` / `new` / `undue` per spec. Order = due (overdueness desc) ++ new (shuffled) ++ undue (shuffled), truncated to `wordCount`. (**Success criterion 6**)
- [ ] `advance(wasCorrect:)` calls `LeitnerScheduler.apply` and sets `card.boxIndex` + `card.nextDue` accordingly. The `DifficultyStore.recordAnswer` and `wrongLastSession = !wasCorrect` calls remain unchanged. (**Success criteria 4, 5**)
- [ ] Box/due writes persist before the next card is shown (force-quit immediately after a swipe preserves state). (**Success criterion 11**)
- [ ] `onlyHardest` path is untouched. (**Success criterion 13**)

**Verification:**
- [ ] Build clean.
- [ ] Manual smoke: on the migrated 745-card deck, start a per-deck session with slot=20. Confirm first cards shown are the most overdue. Swipe right on a box-2 card; quit; relaunch; verify its `boxIndex` is now 3 and `nextDue` ≈ today + 7d (via Practice Hardest or a debug print).

**Dependencies:** Tasks 3, 5.

**Files likely touched:** `Vohe/Views/SessionView.swift`.

**Scope:** M.

---

#### Task 7: Within-session reinforcement

**Description:** When a card is graded Again, append it to `order` and increment `againCountThisSession[card.id]`. Cap at 2 extra appearances. Re-appearances do NOT trigger another box/due write — only `DifficultyStore.recordAnswer` is called on re-grades within the same session.

**Acceptance criteria:**
- [ ] `SessionView` gains a `@State private var againCountThisSession: [UUID: Int] = [:]`.
- [ ] On swipe-left: if `againCountThisSession[card.id] < 2`, append the card to `order` and increment the counter. (**Success criterion 8**)
- [ ] The progress indicator (`N / total`) updates to reflect the new total when a card is re-queued.
- [ ] Subsequent grades on a re-queued card call `DifficultyStore.recordAnswer` but do NOT mutate `card.boxIndex` or `card.nextDue`. Box/due are written exactly once per card per session — on the first grade. (**Success criterion 9**)
- [ ] Resume from `PausedSession` restores the order including any re-queued duplicates; `againCountThisSession` resets to `[:]` on resume. (**Success criterion 12**)

**Verification:**
- [ ] Build clean.
- [ ] Manual smoke: start a 5-card session. Swipe left on the first card three times consecutively (it'll keep coming back). Confirm: first two left-swipes re-queue (total grows to 6, then 7); third left-swipe does NOT re-queue (total stays at 7); the card's `boxIndex` is 1 after the first swipe and stays 1 after each subsequent swipe.
- [ ] Manual smoke: start a session, swipe-left to re-queue once, pause via Cancel → Pause, resume from Library. Confirm the duplicate is still in order; swipe-left on it twice more and observe the cap kicks in (since counter reset on resume, you can re-queue 2 more times — this matches spec).

**Dependencies:** Task 6.

**Files likely touched:** `Vohe/Views/SessionView.swift`.

**Scope:** M.

---

### Checkpoint: Per-deck integration

- [ ] All existing per-deck flows (Start Session, Practice Hardest, Inverted toggle, Pause/Resume) work.
- [ ] All existing SPEC.md acceptance criteria 1–10 still hold (except the superseded session-logic ones, replaced by spec-Leitner criteria 4–8).
- [ ] `xcodebuild test` passes.

---

### Phase 4: Global Review surface

#### Task 8: Global Review path — `SessionView` refactor + Library entry

**Description:** Make `SessionView` accept either a deck (existing behavior) or an explicit `[Card]` list (new global mode). In global mode: no `SessionResult` is persisted, no `PausedSession` is ever created (Cancel offers Discard / Keep going only), inverted is forced false, and the order is built from due cards across all decks sorted by overdueness. Add a "Review (N due)" row at the top of Library that opens the global session; collapse the count to just "Review" when N > 100.

**Acceptance criteria:**
- [ ] `SessionView` gains an internal `Mode` enum: `.perDeck(Deck)` or `.global(cards: [Card])`. Existing call sites continue to compile (use `.perDeck` shorthand or keep the `deck:` initializer as a convenience).
- [ ] In `.global` mode, `buildOrder` uses the explicit cards list (no `new` / `undue` fillers); the exit confirmation dialog shows only "Discard" and "Keep going" (no "Pause").
- [ ] In `.global` mode, **no `SessionResult` is inserted into the context on completion, and no `PausedSession` is ever created**. Per-card writes (box/due/wrongLastSession/DifficultyStore) still happen on every swipe. (**Success criterion 16**)
- [ ] `LibraryView` adds a `Section` (or list row at the very top, above "In Progress") showing "Review (N due)" where N = count of cards across all decks with `boxIndex >= 1 && nextDue <= startOfDay(today) + 24h`. Row is hidden when N == 0. When N > 100, the label reads "Review" with no count; the row still works the same. (**Success criterion 7**)
- [ ] Tapping the row presents `SessionView` in `.global` mode with cards sorted by overdueness desc. Direction is forward, no toggle. (**Success criterion 10**)
- [ ] Slot size for the global session uses `UserDefaults.standard.integer(forKey: "vohe.lastSlotSize")` defaulting to 20. (Out-of-spec convenience: store last-used slot when starting any session. Acceptable per spec which says "user's last-used slot value … default 20".)

**Verification:**
- [ ] Build clean.
- [ ] Manual smoke 1: with the migrated 745-card deck where ~100 cards are due today, Library shows "Review (100 due)". Tap → session opens with up to 20 cards (or the configured slot), most-overdue first.
- [ ] Manual smoke 2: complete a global session. Confirm no new `SessionResult` row appears in any deck's history (DeckDetailView's "Last 5 sessions" list is unchanged after the global session). Confirm no entry appears in Library's "In Progress" section.
- [ ] Manual smoke 3: start a global session, tap Cancel — confirm only "Discard" and "Keep going" appear (no "Pause").
- [ ] Manual smoke 4: per-deck Start Session still works exactly as before, including SessionResult creation and pause/resume.
- [ ] Manual smoke 5: when due-count exceeds 100, the Library row reads just "Review" with no count.

**Dependencies:** Tasks 6, 7.

**Files likely touched:** `Vohe/Views/SessionView.swift`, `Vohe/Views/LibraryView.swift`.

**Scope:** M (2 files, but the SessionView refactor is the riskiest single change in the plan).

---

### Checkpoint: Global Review

- [ ] All five manual smokes pass.
- [ ] `xcodebuild test` passes (unit tests unchanged but still green).
- [ ] No regression in per-deck or Practice Hardest flows.

---

### Phase 5: Final verification

#### Task 9: Full criteria walk + regression sweep

**Description:** Walk every numbered success criterion in `docs/specs/spaced-repetition-leitner.md` (criteria 1–16) and every criterion in the existing `SPEC.md` (criteria 1–10). Confirm each holds. Document any deltas.

**Acceptance criteria:**
- [ ] Each of the 16 spec criteria has a `pass` / `fail` mark with one-line evidence.
- [ ] Each of the 10 existing SPEC.md criteria has a `pass` / `superseded` mark with one-line note.
- [ ] Any `fail` items are turned into follow-up tasks or fixed in this session.

**Verification:**
- [ ] Written checklist committed (e.g. in the PR description or `docs/plans/spaced-repetition-checklist.md`).
- [ ] `xcodebuild test` passes; manual smoke for criteria 11, 12, 13, 15, 16.

**Dependencies:** Task 8.

**Files likely touched:** Possibly `docs/plans/spaced-repetition-checklist.md` (new) or just the PR body.

**Scope:** S (verification, not new code unless fails surface).

---

### Checkpoint: Complete

- [ ] All 16 spec criteria pass.
- [ ] All existing non-superseded SPEC.md criteria pass.
- [ ] Ready for merge.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `project.yml` edit accidentally disturbs the `Vohe` target's signing block | High (user pain — re-sign breaks personal device install) | Pre-edit: copy current file. Post-edit: verify byte-for-byte that the `Vohe` target settings block is unchanged. Hand off this verification to the user (memory: signing config is user-maintained). |
| SwiftData lightweight migration fails to add `boxIndex`/`nextDue` silently | High (data loss on upgrade) | Test on a pre-populated DB in Task 2. If migration fails, write an explicit `VersionedSchema` + `MigrationPlan` (escalation path). |
| `SessionView` refactor (Task 8) breaks existing per-deck/resume call sites | Medium (regression on the existing daily-use flow) | Keep a convenience initializer `init(deck:inverted:wordCount:onlyHardest:resume:)` for the existing call sites; only the global mode goes through the new `Mode` enum constructor. |
| Global Review pulls a huge queue (e.g. 200 due cards) and feels overwhelming | Low (just for first few sessions post-migration) | Slot size cap is honored (default 20). The 7-day staggering on backfill already mitigates wall-of-cards. The N>100 count-hide rule prevents the number itself from inducing anxiety. |
| Within-session reinforcement infinite loop if a bug skips the cap check | Medium | Manually verified in Task 7's smoke. Defensive: hard upper bound on `order.count` (e.g. `2 * initialCount`). Skip if not needed. |
| Backfill bucket thresholds turn out to feel wrong after 1–2 weeks | Low | Thresholds are constants in `SchedulerMigration.swift`; trivially tunable. Re-run via temporary debug toggle if needed. |

## Open Questions

None — all planning-phase questions resolved:
- Global session `SessionResult` persistence → not persisted (criterion 16).
- "Review (N due)" count visibility above 100 → hide count (criterion 7).

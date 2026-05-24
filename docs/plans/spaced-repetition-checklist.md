# Spaced Repetition — Criteria Verification Checklist

Walks every numbered success criterion in `docs/specs/spaced-repetition-leitner.md`
and every criterion in the existing `SPEC.md`. Use this to gate the final
manual smoke pass on a real device or simulator.

Legend:
- ✅ **Pass** — verified by an automated test or trivially provable from the code.
- 🔍 **Needs manual smoke** — code matches the criterion; behavior must be confirmed in a running app.
- ⏭️ **Superseded** — the spec change replaces this criterion.

## docs/specs/spaced-repetition-leitner.md — Criteria 1-16

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Schema migration (lightweight) | 🔍 | Card has `boxIndex: Int = 0` and `nextDue: Date = .distantPast` defaults; build succeeds. Manual: install pre-upgrade build, import deck, quit; build new branch, run; confirm Library shows the deck. |
| 2 | Backfill bucket assignment | ✅ | `SchedulerMigrationTests.testBoxAssignmentByWrongRate` covers `<0.2 → 3`, `<0.4 → 2`, else `1`, plus `seen < 3 → 0`, plus strict `<` at 0.2 and 0.4. `testUnseenStaysAtDistantPast` covers no-stats path. |
| 3 | Backfill staggering (≤ ceil(N/7) per bucket) | ✅ | `SchedulerMigrationTests.testStaggeringDistribution` asserts the bound + 7-day window. |
| 4 | Box transitions (Good) | ✅ | `LeitnerSchedulerTests.testGoodFromBox2` (2 → 3, +7d) and `testGoodFromBox5DoesNotOverflow` (5 stays 5, +60d). |
| 5 | Box transitions (Again) | ✅ | `LeitnerSchedulerTests.testAgainResetsToBox1` covers boxes 1-5. |
| 6 | Due query, per-deck (due → new → undue, truncated) | 🔍 | `SessionView.buildOrder()` else-branch partitions per spec; shuffles ties; sorts due ascending by `nextDue`. Manual: open migrated deck, slot=20; confirm most-overdue cards appear first. |
| 7 | Due query, global ("Review N due" hides count > 100, hides row when 0) | 🔍 | `LibraryView.dueCount` + `reviewRowLabel`; row gated by `if dueCount > 0`. Manual: confirm row visible only when due cards exist; force a >100 state to verify label collapses. |
| 8 | Within-session reinforcement (cap 2 extra appearances) | 🔍 | `SessionView.advance()` appends to `order` when `againCountThisSession[id] < reinforcementCap` (=2). Manual: 5-card session, swipe left on first card 3× — first 2 re-queue (total grows to 6, 7), 3rd doesn't (stays 7). |
| 9 | Reinforcement does not advance box | 🔍 | `gradedThisSession: Set<UUID>` guards the `LeitnerScheduler.apply` block in `advance()`. Manual: swipe-left then swipe-right on same re-queued card; verify card's `boxIndex` stays 1 after both grades. |
| 10 | Global Review direction = forward, no toggle | 🔍 | `SessionView.init(globalCards:wordCount:)` hardcodes `inverted = false`. Manual: tap Review row, confirm front side shows `language1` text. |
| 11 | Persistence (force-quit preserves new box/due) | 🔍 | `advance()` calls `try? context.save()` after every grade. Manual: swipe right on a box-2 card, force-quit, relaunch; verify card now box 3. |
| 12 | Pause/resume mid-reinforcement preserves duplicates | 🔍 | `PausedSession.cardOrderIDs = order.map { $0.id }` serializes duplicates; resume's `compactMap { byID[$0] }` restores them. `againCountThisSession` is `@State` so resets on resume per spec. Manual: re-queue a card, pause, resume; verify duplicate present and counter behavior. |
| 13 | "Practice Hardest" unchanged | ✅ (code review) + 🔍 | `onlyHardest` branch in `buildOrder` is byte-for-byte unchanged (still uses `DifficultyStore.difficultyScore`). Manual: confirm Practice Hardest still orders by wrong-rate, ignoring boxes/due. |
| 14 | No regression in existing SPEC.md criteria 1-10 | 🔍 | See "Legacy SPEC.md" table below. |
| 15 | Timezone correctness (23:55 + 1d → midnight next day) | ✅ | `LeitnerSchedulerTests.testTimezoneAnchorsToLocalStartOfDay`. |
| 16 | Global session ephemerality (no SessionResult, no PausedSession) | 🔍 | `advance()`'s end-of-session block is wrapped in `if !isGlobal`; `pauseAndExit()` is unreachable because the Pause button is conditionally rendered (`if !isGlobal`). Manual: complete a global session; verify no row appears in any deck's "Recent Results" and no "In Progress" entry appears. |

## SPEC.md — Legacy Criteria 1-10

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | Importing a valid file creates a deck | 🔍 | Untouched. |
| 2 | Importing malformed file shows error, creates nothing | 🔍 | Untouched. |
| 3 | Session shuffles | ⏭️ | Superseded by spec criterion 6 (due + new + undue with shuffles within each tier). |
| 4 | Tap reveals back; swipe-right scores correct | 🔍 | Untouched; swipe handling unchanged. |
| 5 | Wrong cards from last session appear first | ⏭️ | Superseded by spec criterion 6 (due cards from scheduler appear first). `wrongLastSession` is still written on each grade for rollback safety; new code ignores it. |
| 6 | Inverted toggle swaps front/back | 🔍 | Untouched in per-deck mode. Global mode is always forward (spec criterion 10). |
| 7 | Score matches swipe count | 🔍 | `correct` is still incremented per right-swipe. With reinforcement, the displayed total can grow mid-session — `total` and `correct` in the saved SessionResult reflect actual swipe counts. |
| 8 | Delete deck removes deck + history | 🔍 | Cascade delete relationships untouched. |
| 9 | App launches to Library with empty state | 🔍 | Untouched. |
| 10 | Relaunch preserves all state | 🔍 | Now also includes `boxIndex` and `nextDue` per spec criterion 11. |

## Manual smoke script (one focused session)

Suggested 5-minute pass against a fresh build:

1. **Install pre-change build** (current `main`), import the sample Croatian-Italian deck, complete one 20-card session so some cards have `seen` history, quit.
2. **Switch to this branch, build & run.** Library should appear with the deck listed.
3. **Open the deck.** Card count matches. Recent Results row is unchanged.
4. **Start a 20-card session.** Confirm the most-overdue cards (or new ones if all backfilled to box 0) appear first.
5. **Swipe right on first card → quit → relaunch.** Reopen deck. Card's box should have advanced (verifiable by starting another session and seeing that card not show up immediately).
6. **In a new 5-card session, swipe left on card 1 three times.** Verify the progress bar (`N/total`) grew from 5 → 6 → 7 after the first two left-swipes, and stayed at 7 after the third.
7. **Go back to Library.** "Review (N due)" row should be visible if any cards have `nextDue ≤ tomorrow`.
8. **Tap Review.** Session opens, forward direction. Cancel → confirm only "Discard" and "Keep going" (no "Pause"). Resume the session and finish it.
9. **Return to Library.** Confirm no new "In Progress" entry and no new "Recent Results" row in any deck.
10. **Verify Practice Hardest still works** on the deck (orders by wrong-rate).

If all 10 steps pass, the implementation is ready for commit.

## Known edge cases (accepted, documented)

- **Resumed session resets reinforcement counters.** A re-queued card present in `cardOrderIDs` at pause time will, after resume, be treated as a "first grade" by `gradedThisSession`. Subsequent grades will re-write `boxIndex`/`nextDue`. Spec criterion 12 explicitly accepts the `againCountThisSession` reset; this is the analogous behavior for `gradedThisSession`.
- **Global session count is computed at presentation time.** If midnight passes mid-session, newly-due cards are not added to the in-flight session; user sees them on the next Library refresh.
- **`UserDefaults.lastSlotSize` stores `0` if the user last picked "All".** Global Review will then run all due cards — arguably the right behavior for a user who explicitly preferred "All".

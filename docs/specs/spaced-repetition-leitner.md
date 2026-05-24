# Spec: Spaced Repetition (Calendar-Leitner)

## Objective

Replace the current "wrong-last-session carryover" memory model with a 5-box Calendar-Leitner scheduler so that daily 2-minute sessions yield substantially higher long-term retention. Cards the user knows well are deferred for days or weeks; cards the user is struggling with surface every day. Within a session, any wrong-graded card is re-queued at the end of the same session until it's gotten right (capped at 2 extras per card per session).

A new Library-level "Review (N due)" surface exposes due cards across all decks at a glance. Per-deck "Start Session" and "Practice Hardest" continue to exist unchanged.

**Why now:** The current carryover model only remembers the last session. Cards "learned" three months ago silently rot. The daily session also wastes swipes on cards the user knows cold. Both problems vanish with per-card scheduling.

**Supersedes** in `SPEC.md`:
- "Out of Scope (v1) → Spaced repetition algorithm"
- "Session Logic" (steps 1–6)

## Tech Stack

Unchanged from existing project: SwiftUI + SwiftData, iOS 26, xcodegen. No new dependencies.

## Commands

Unchanged. Build/verify per README:
```
xcodebuild -project Vohe.xcodeproj -scheme Vohe \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

If a test target is added (see Boundaries → "Ask first"):
```
xcodebuild test -project Vohe.xcodeproj -scheme Vohe \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0'
```

## Project Structure (new + changed files)

```
Vohe/
  Models/
    Card.swift                    [CHANGED] add boxIndex, nextDue
  Services/
    LeitnerScheduler.swift        [NEW]     box transitions, due-date math
    SchedulerMigration.swift      [NEW]     one-shot backfill from difficulty.json
  Views/
    LibraryView.swift             [CHANGED] add "Review (N due)" row
    SessionView.swift             [CHANGED] buildOrder + within-session reinforcement
    DeckDetailView.swift          [UNCHANGED]
  VoheApp.swift                   [CHANGED] run SchedulerMigration on launch

docs/
  specs/
    spaced-repetition-leitner.md  [NEW]     this file
  ideas/
    spaced-repetition-leitner.md  [EXISTS]  upstream one-pager

SPEC.md                           [CHANGED] add "Superseded sections" pointer
```

## Code Style

Unchanged from the existing codebase. Match the patterns already in `DifficultyStore.swift` and `SessionView.swift` — value types for pure logic, `@Model` classes for SwiftData entities, services as plain `final class` with a `static let shared` singleton when stateful.

Example of the scheduler shape this spec expects:

```swift
// Vohe/Services/LeitnerScheduler.swift
import Foundation

enum LeitnerScheduler {
    /// Intervals in days, indexed by box (0 = unseen, 1..5 = scheduled).
    /// Box 0 has no interval — new cards are always due.
    static let intervalsByBox: [Int] = [0, 1, 3, 7, 21, 60]

    static let maxBox = 5

    /// Apply a grade and return (new box, new due date).
    static func apply(grade: Grade, currentBox: Int, now: Date = .now,
                      calendar: Calendar = .current) -> (box: Int, due: Date) {
        switch grade {
        case .again:
            return (1, startOfNextDay(after: now, calendar: calendar, addingDays: intervalsByBox[1]))
        case .good:
            let next = min(currentBox + 1, maxBox)
            return (next, startOfNextDay(after: now, calendar: calendar, addingDays: intervalsByBox[next]))
        }
    }

    enum Grade { case again, good }

    private static func startOfNextDay(after date: Date, calendar: Calendar, addingDays days: Int) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: days, to: dayStart) ?? date
    }
}
```

## Algorithm Specification

### Data model

`Card` gains two properties:

```swift
var boxIndex: Int = 0          // 0 = unseen/new, 1..5 = scheduled
var nextDue: Date = .distantPast   // distantPast for unseen → always "due"
```

SwiftData lightweight migration handles the schema change automatically because both have Swift-level defaults.

### Box intervals

| Box | Interval | Meaning |
|---|---|---|
| 0 | (n/a) | New / never reviewed. Always eligible. |
| 1 | 1 day | Struggling — see again tomorrow. |
| 2 | 3 days | Learning. |
| 3 | 7 days | Familiar. |
| 4 | 21 days | Known. |
| 5 | 60 days | Mature. |

### Grade transitions

Given the binary swipe:
- **Swipe right (Good):** box = min(box + 1, 5); due = startOfDay(today) + intervalsByBox[newBox] days.
- **Swipe left (Again):** box = 1; due = startOfDay(today) + 1 day. Re-queue the card at the end of the current in-memory session (see reinforcement below).

A box-5 card swiped right stays at box 5 with due = today + 60d. There is no box 6.

### "Due today" definition

A card is due if `nextDue <= startOfDay(now) + 24h` (i.e., due today or earlier). New cards (`boxIndex == 0`) are always due.

Overdueness sort: descending by `(today - nextDue)` — the most overdue card surfaces first.

### Session order construction (replaces existing `buildOrder` for non-`onlyHardest` paths)

For a **per-deck session** with chosen slot size N:

1. Pool = cards in this deck.
2. Partition into: `due` (boxIndex ≥ 1 and nextDue ≤ today), `new` (boxIndex == 0), `undue` (the rest).
3. Sort `due` by overdueness desc, then shuffle within equal overdueness.
4. Shuffle `new` and `undue` independently.
5. Final order = `due` ++ `new` ++ `undue`, truncated to N (where N==0 means "All").

For a **global Review session** triggered from Library:

1. Pool = `due` cards across all decks (boxIndex ≥ 1 and nextDue ≤ today).
2. Sort by overdueness desc, shuffle within equal overdueness.
3. Slot size is fixed at the user's last-used slot value (read from `UserDefaults`, default 20). No filler from new/undue cards — global Review is "due only."
4. Direction is forward (non-inverted), no toggle.
5. Global sessions are ephemeral: **no `SessionResult` is persisted on completion**, and **no `PausedSession` is ever created** (the Cancel dialog offers Discard / Keep going only — no Pause). Per-card box/due/wrongLastSession updates and `DifficultyStore` updates still happen on every swipe; only the session-level records are skipped.

The "Practice Hardest" path (`onlyHardest == true`) is unchanged: it uses `DifficultyStore.difficultyScore` and ignores boxes/due dates entirely.

### Within-session reinforcement

When a card is swiped left during a session:
- Record the grade (update `boxIndex` to 1, `nextDue` to today + 1d, persist to SwiftData immediately).
- Re-queue: append the same `Card` to the in-memory `order` array.
- Increment an ephemeral counter `againCountThisSession[card.id] += 1` (a `[UUID: Int]` `@State` dict on `SessionView`, not persisted to SwiftData).
- A card may be re-queued at most **2 extra times per session**. The 3rd "Again" on the same card does not re-queue; the card moves on.
- Re-queued cards retain box state (box 1, due tomorrow) — re-getting them correct within the same session does NOT advance them to box 2. Reinforcement is a *learning step*, not a scheduling event. Only the *first* grade per card per session writes box/due updates; subsequent re-appearances within the same session record `seen`/`wrong` in `DifficultyStore` but do not mutate `boxIndex` or `nextDue`.

### Backfill migration

On first launch after the upgrade, gated by `UserDefaults.standard.bool(forKey: "vohe.schedulerBackfillCompleted.v1")`:

1. For each `Card` in SwiftData:
   - Look up `DifficultyStore.shared.stats(deckName, front, back)`.
   - If stats missing or `seen < 3`: `boxIndex = 0`, `nextDue = .distantPast`.
   - Else compute `wrongRate = wrong / seen`:
     - `wrongRate < 0.2` → boxIndex = 3
     - `wrongRate < 0.4` → boxIndex = 2
     - else → boxIndex = 1
   - For cards assigned to box 1–3: stagger `nextDue` randomly across the next 7 days (`startOfDay(today) + Int.random(in: 0..<7) days`) to avoid a wall of due cards.
2. Save context.
3. Set the UserDefaults flag.

The migration runs synchronously before the first view appears (called from `VoheApp.init` or the SwiftData container setup). For typical deck sizes (under a few thousand cards), this is sub-second.

## Testing Strategy

Vohe has no test target today. Two options:

**Option A (Recommended): Add a `VoheTests` XCTest target.**
- Worth the project.yml change because the Leitner logic is pure, deterministic, and easy to get subtly wrong (off-by-one in box transitions, timezone bugs in due-date math, re-queue cap math).
- Tests live in `VoheTests/LeitnerSchedulerTests.swift` and `VoheTests/SchedulerMigrationTests.swift`.
- Run via `xcodebuild test` (command above).
- The `LeitnerScheduler` is a pure `enum` with no SwiftData/UI deps, so tests are trivial to write.

**Option B (Fallback): No automated tests; rely on the existing "Acceptance Criteria" manual-check convention in SPEC.md.**

The author should pick A or B before implementation starts. (See Boundaries → "Ask first.")

## Boundaries

**Always:**
- Run `xcodebuild ... build` before claiming a slice is done.
- Match existing code style (final classes, plain enums for stateless services, value types for data).
- Compute all due-date math in `Calendar.current` and anchor on `startOfDay`.
- Persist box/due updates to SwiftData on every grade, immediately (not at session end), so a crash doesn't lose progress.

**Ask first:**
- Adding a `VoheTests` target to `project.yml` (per memory: signing config is hand-maintained — verify the test target additions don't disturb that section).
- Removing the `wrongLastSession` field on `Card` (deferred; keep ignoring it in new code paths).
- Changing reminder/notification logic to surface due-count (out of scope for v1 of this change).
- Adding a daily new-card cap (deliberately out of scope per Phase 1 decision).

**Never:**
- Touch the existing `DifficultyStore` schema or `difficulty.json` format. The backfill *reads* it; it does not modify it.
- Replace `wrongLastSession` writes in this change. It continues to be set on swipe (in case rollback is needed), even though new code no longer reads it.
- Change the per-deck "Start Session" or "Practice Hardest" entry points' visible behavior beyond the new ordering.
- Add escalating notifications based on queue size.

## Success Criteria

Numbered for traceability, matching the style of the existing SPEC.md.

1. **Schema migration.** Adding `boxIndex` and `nextDue` to `Card` does not require a manual migration step. Existing decks open without error after upgrade.
2. **Backfill correctness.** On first launch after upgrade, every existing `Card` with `seen ≥ 3` in `difficulty.json` is assigned a box ∈ {1, 2, 3} per the wrong-rate buckets; every other `Card` has `boxIndex == 0`. The backfill runs exactly once (verified by the UserDefaults flag).
3. **Backfill staggering.** No more than `ceil(totalAssignedCards / 7)` cards have the same `nextDue` date after backfill (cards distribute roughly evenly across the next 7 days). Verified by counting due dates after running the migration on the sample 745-card Croatian-Italian deck.
4. **Box transitions (Good).** Swiping right on a box-2 card sets boxIndex = 3 and nextDue = startOfDay(today) + 7 days. Swiping right on a box-5 card sets boxIndex = 5 (no overflow) and nextDue = today + 60 days.
5. **Box transitions (Again).** Swiping left on a card of any box (1..5) sets boxIndex = 1 and nextDue = today + 1 day.
6. **Due query, per-deck.** A session started on a deck with 3 cards due today, 5 new cards, 7 un-due cards, slot=20 produces an order of length 15: due first (3), then new (5, shuffled), then un-due (7, shuffled), then truncates to 20 (no truncation here, so length 15).
7. **Due query, global.** The "Review (N due)" row on Library shows N = count of cards across all decks where boxIndex ≥ 1 AND nextDue ≤ startOfDay(today) + 24h. The row hides when N == 0. When N > 100, the row reads "Review" with no count (to avoid the streak-anxiety the README disclaims); the underlying queue size is still N. Tapping opens a session whose order length ≤ N, sorted by overdueness desc.
8. **Within-session reinforcement.** A session starts with a card C in position 0. Swiping left on C immediately appends C to the order. The session order length increases by 1. When C resurfaces and is swiped left again, it's appended once more. The third "Again" on C does NOT append again — `againCountThisSession[C.id]` is now 2 and the cap is hit.
9. **Reinforcement does not advance box.** A card swiped left, then right within the same session, ends at boxIndex = 1, nextDue = today + 1 day. The right-swipe within the session only updates `DifficultyStore` seen/correct counts; it does NOT promote the card to box 2.
10. **Global Review direction.** Cards in a global Review session display non-inverted (front shows language1 text). There is no inverted toggle on the global Review row.
11. **Persistence.** Force-quitting the app immediately after swiping a card preserves the new box and due date on next launch.
12. **Pause/resume.** Pausing a session mid-reinforcement (with re-queued duplicates in `order`) and resuming restores the order including duplicates. The `againCountThisSession` resets to 0 on resume.
13. **"Practice Hardest" unchanged.** Selecting Practice Hardest still orders cards by wrong-rate from `DifficultyStore`, ignoring boxes and due dates. Verified by running both modes on the same deck and observing different orders.
14. **No regression in existing acceptance criteria.** All criteria 1–10 in the existing `SPEC.md` continue to hold, except where explicitly superseded (criteria 3 and 5 in the existing spec are replaced by criteria 4–8 above).
15. **Timezone correctness.** Reviewing a card at 23:55 local time and again at 00:05 the next local day shows the card as due (it was rescheduled +1 day = tomorrow start-of-day; "tomorrow" from 23:55 = today's startOfDay + 1d, so it's due at 00:00 the next day).
16. **Global session ephemerality.** Completing or canceling a global Review session does NOT create a `SessionResult` or `PausedSession` record. Per-card writes (boxIndex, nextDue, wrongLastSession, DifficultyStore stats) still occur on every swipe. Verified by completing a global session and confirming no new row appears in any deck's session history and no entry appears in the Library "In Progress" list.

## Open Questions

None — all open questions from the upstream one-pager (`docs/ideas/spaced-repetition-leitner.md`) and from the planning phase were resolved:
- **Backfill thresholds:** Lenient (<0.2 → box 3, <0.4 → box 2, else box 1).
- **Filler priority:** Due → new unseen (no cap) → random un-due, per-deck only. Global Review is due-only.
- **Inverted in global Review:** Always forward, no toggle.
- **Global session SessionResult persistence:** Not persisted (ephemeral). See criterion 16.
- **"Review (N due)" count visibility:** Hidden when N > 100 (row reads "Review"). See criterion 7.
- **Testing strategy:** Option A — `VoheTests` XCTest target will be added (per `docs/plans/spaced-repetition-leitner.md`).

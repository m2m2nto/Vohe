# Spaced Repetition for Vohe (Calendar-Leitner)

## Problem Statement

How might we replace "wrong-last-session carryover" with per-card scheduling that maximizes retention per daily minute, without breaking the plain-text-deck philosophy, the 2-minute habit loop, or the binary-swipe muscle memory?

## Recommended Direction

**5-box Calendar-Leitner + within-session reinforcement, schedule state on the SwiftData `Card` model, with a global "Review" surface on the Library home that does not replace existing per-deck sessions.**

Boxes have fixed intervals: **1d → 3d → 7d → 21d → 60d**. A correct swipe promotes a card one box (capped at 5). A wrong swipe drops it to box 1 *and* re-queues it inside the current session until you get it right (capped at 2 extra appearances per card per session). New cards enter at box 0 (unseen) and graduate to box 1 the first time they're shown.

The choice rejects FSRS not because FSRS is worse, but because binary grading + fixed slot sizes (chosen in Phase 1) neutralize most of FSRS's edge. Leitner with calendar intervals delivers ~80% of the retention benefit in ~30 lines of logic with state a human can read in a JSON dump. If the user later wants 4-level grading, the migration from Leitner to FSRS is a one-time backfill — not an irreversible decision.

The global Review surface is a soft badge on Library: "Review (43 due)." Tapping it opens a session that pulls from all decks, due cards first. Per-deck "Start Session" continues to exist for targeted drilling and stays the entry point from the notification quick-session flow.

## Key Assumptions to Validate

- [ ] **Binary grading + Leitner intervals retains ≥85% at box 5.** Validate by tracking per-box hit rate after ~6 weeks of use. If box-5 retention is materially below 85%, tighten 60d → 45d.
- [ ] **Backfilling existing cards using their `seen`/`wrong` history feels reasonable, not surprising.** Validate by running the migration on a copy of the live data, eyeballing 20 random cards, and asking "would I have predicted this box?"
- [ ] **Box intervals (1/3/7/21/60d) match Croatian retention for a non-immersed learner.** These are Anki/Leitner defaults; non-immersed adult language learning may need tighter intervals. Validate after 6 weeks.
- [ ] **Within-session reinforcement (cap 2 re-appearances) doesn't turn a 20-card session into a 60-card slog on bad days.** Validate by capping and observing actual session length distributions.
- [ ] **A passive "43 due" badge stays ambient and doesn't induce the streak-anxiety the README explicitly disavows.** Validate by self-observation after 2 weeks; if anxiety appears, demote to "Review" with no count.

## MVP Scope

**In:**
- Add `boxIndex: Int` and `nextDue: Date` to `Card` (SwiftData migration).
- Scheduler with 5 boxes, intervals `[1, 3, 7, 21, 60]` days, computed in local-start-of-day.
- `SessionView.buildOrder()` extended: when not `onlyHardest`, fill slot with due cards first (sorted by overdueness), then new unseen, then random un-due fillers.
- Within-session "Again" re-queue, with ephemeral `Card.againCountThisSession` state (not persisted), capped at 2 extra appearances.
- New `LibraryView` row at top: "Review N due" (only shown when N > 0). Opens a multi-deck session.
- Backfill migration: for each card with stats in `difficulty.json`, assign starting box from wrong-rate buckets (`wrong-rate <0.2` → box 3, `<0.4` → box 2, else → box 1); cards with no stats start at box 0; due dates staggered randomly across the next 7 days to avoid a "743 due" wall on first launch.

**Out (deferred or never):**
- Removing the `wrongLastSession` field. Keep it during transition; ignore it in the new code path. Remove in a follow-up once the scheduler is trusted.
- Per-deck schedule sidecar JSON. State lives on SwiftData; the global Review query would force N file reads otherwise. `difficulty.json` continues to be the hand-editable surface for `seen`/`wrong` historical stats only.
- Per-direction scheduling. Inverted toggle remains a session-level choice; whichever direction was reviewed counts.
- Configurable intervals or target retention. Hardcoded for v1; revisit after assumption A2 is validated.
- Notification escalation for due-count. Notifications stay on the existing schedule the user configured; they do not change frequency based on queue size.

## Not Doing (and Why)

- **FSRS-4** — chosen UX (binary grading, fixed slots) blunts its advantages; not worth the dependency or vendored algorithm for the marginal retention gain.
- **SM-2** — middle ground that's worse than Leitner for binary input and worse than FSRS otherwise. No reason to pick it.
- **Per-deck sidecar JSON for schedule state** — contradicts the fast multi-deck query the global Review surface needs. Inspectability argument doesn't survive that.
- **Per-direction (forward/inverted) separate schedules** — user explicitly chose one-schedule-per-card in Phase 1; doubling the queue isn't worth it for a daily-2-minute habit.
- **Replacing fixed slots with "do all due today"** — user explicitly chose to preserve the habit loop. Variable daily volume breaks that.
- **Streak counters, "you have 43 due!" push notifications, or any escalation when the queue grows** — directly contradicts the README's anti-guilt-trip stance.
- **Removing `wrongLastSession` in this change** — keep diff surgical; remove in a separate cleanup once scheduling is trusted.

## Open Questions

- **Backfill exact bucket thresholds.** Proposed default: `wrong-rate <0.2 → box 3, <0.4 → box 2, else → box 1`. Is there a reason to be more or less aggressive? (e.g. user may already know any card with wrong-rate >0 should restart in box 1.)
- **"Filler" priority when due queue runs dry.** Proposed order: due → new unseen → random un-due. Acceptable, or should new cards have a daily cap (Anki-style) to prevent introducing 50 new words in one session?
- **Should the global Review surface honor `inverted` somehow?** Today inverted is a per-session toggle picked before starting. A cross-deck Review session needs a default direction — forward is the conservative answer.

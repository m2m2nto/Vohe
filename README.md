# Vohe

A small iOS flashcard app for learning vocabulary the slow, daily way.

## Why

I believe learning a new language is mostly about repeating words **daily, in small bites, over a long time**. Cramming 200 words in a Sunday session is forgotten by Wednesday. Five words every day at 9:00 and 18:00, for a year, is a vocabulary.

There are plenty of language apps already, but I couldn't find one that combined three things I needed:

1. **You add your own words.** Not a fixed catalog — words from the book you're reading, your in-laws' kitchen, your last trip. Plain text in, deck out.
2. **Daily nudges, not a streak machine.** Two short notifications a day asking for two minutes, not a guilt-trip about an 87-day streak.
3. **Spaced focus on what you actually find hard.** The app tracks per-card success and lets you run sessions that drill only your hardest words.

So I built Vohe. It's a personal project; I use it every day.

## How it works

1. **Make a word list** in plain text — `Croatian-Italian` on the first line, then `word - translation` per line. See [`samples/Croatian-Italian.txt`](samples/Croatian-Italian.txt) for a real ~745-word deck.
2. **Drop the file in iCloud Drive** (or any file provider the iOS Files app sees) and import it via the **+** button in the library.
3. **Run a session**: 5, 20, 50, 100, or All. Tap the card to flip, swipe **right** if you knew it, **left** if you didn't. The app shuffles wrong-last-time cards to the front.
4. **Enable reminders** (bell icon). Pick Random (N times per day inside a window) or Exact (specific HH:MM). Tap a reminder → a 5-word session opens on your most recently practiced deck.
5. **Practice Hardest** once a card has been seen ≥ 3 times — Vohe ranks by wrong-rate and gives you the worst offenders.

That's the whole loop. Open the app, swipe a handful, close it. Tomorrow, same.

## Features

- **Plain-text decks**, manually editable, easy to back up or share.
- **Custom session sizes**: 5 / 20 / 50 / 100 / All.
- **Inverted mode** to drill the other direction (target → source).
- **Pause & resume** up to 5 in-progress sessions.
- **Smart wrong-words queue**: cards you missed last session show up first next time.
- **Difficulty tracking** per card (seen / wrong counts), stored in a user-visible JSON file at `Documents/difficulty.json` so it survives backups and can be hand-edited or moved to iCloud Drive via the Files app.
- **Session history with detail view**: tap any past session to see duration and the exact words you got wrong.
- **Local notifications**, fully configurable, with a "tap to start a quick 5-word session" handoff.

## File format

```
language1-language2
word-translation
word-translation
...
```

- First line: language pair, hyphen-separated.
- Each subsequent line: `word - translation`. Spaces around the hyphen are fine.
- Blank lines and lines starting with `#` are ignored.
- A literal `-` inside a word isn't supported (parser splits on the first hyphen).

Example header + first lines:

```
Croatian-Italian
crvena - rosso
plava - blu
zelena - verde
domaća zadaća - compiti
```

## Building it on your iPhone

You need:
- macOS with Xcode 17+ installed.
- An Apple ID. Free tier works, but the app expires every 7 days and must be re-installed.
- An iPhone running iOS 26+.

Steps:

1. Open the project:
   ```
   open Vohe.xcodeproj
   ```
2. In Xcode → `Vohe` target → **Signing & Capabilities** → set **Team** to your Apple ID. Change the bundle ID to something unique (`com.<yourname>.vohe`) if `com.danilo.vohe` is taken.
3. Plug in your iPhone, trust the computer, pick it as the run destination, **Cmd-R**.
4. On the iPhone, first launch: **Settings → General → VPN & Device Management → Developer App → Trust**.

## Tech notes

- **SwiftUI + SwiftData** on iOS 26.
- **Local notifications** via `UNUserNotificationCenter` with auto-rescheduling on foreground.
- **xcodegen** drives the project — `project.yml` is the source of truth, `Vohe.xcodeproj/` is generated and gitignored.

## Project layout

```
project.yml              xcodegen config
Vohe.xcodeproj/          generated — do NOT edit by hand
Vohe/
  VoheApp.swift          @main entry
  Models/                SwiftData @Model types (Deck, Card, SessionResult, PausedSession)
  Services/              DeckParser, ReminderScheduler, DifficultyStore, NotificationRouter
  Views/                 LibraryView, DeckDetailView, SessionView, ResultsView, SessionDetailView
samples/                 example vocabulary files
SPEC.md                  full functional spec
```

If you add or rename Swift files, re-run `xcodegen generate`.

## Verifying the build (CLI)

```
xcodebuild -project Vohe.xcodeproj -scheme Vohe \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

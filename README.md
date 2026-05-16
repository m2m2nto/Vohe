# Vohe

Personal iOS vocabulary flashcard app. SwiftUI + SwiftData, iOS 17+.

See `SPEC.md` for the full specification.

## Project layout

```
project.yml              xcodegen config
Vohe.xcodeproj/          generated — do NOT edit by hand
Vohe/
  VoheApp.swift          @main entry
  Models/                SwiftData @Model types
  Services/DeckParser.swift
  Views/                 LibraryView, DeckDetailView, SessionView, ResultsView
samples/                 sample vocabulary files for testing
```

If you ever rename or add Swift files, re-run `xcodegen generate`.

## Build & install on your iPhone

You need:
- macOS with Xcode 17+ installed (you have 26.5).
- An Apple ID (free tier works — but the app expires every 7 days and must be re-installed).
- A Lightning/USB-C cable, OR your iPhone on the same Wi-Fi with Xcode device pairing enabled.

Steps:

1. Open the project:
   ```
   open Vohe.xcodeproj
   ```
2. In Xcode, select the `Vohe` target → **Signing & Capabilities** tab.
3. Set **Team** to your personal Apple ID team. Xcode will pick a unique bundle ID if `com.danilo.vohe` conflicts; you can change it to e.g. `com.<yourname>.vohe`.
4. Plug in your iPhone (unlock, "Trust This Computer").
5. Top toolbar: pick your iPhone as the run destination, then **Cmd-R**.
6. First run: on iPhone, open **Settings → General → VPN & Device Management → Developer App → Trust**.

## Loading vocabulary

Copy `samples/Italian-Croatian-Beginner.txt` into iCloud Drive (or your Google Drive folder if you have the Drive app installed and its File Provider enabled). In the app, tap **+** → Files picker → pick the file. The deck appears in the library.

## File format (strict)

```
language1-language2
word-translation
word-translation
...
```

- First line: language pair, hyphen-separated.
- Each subsequent line: a word and its translation, hyphen-separated.
- Blank lines and `#` comments are ignored.
- A literal `-` inside a word is **not supported** (the parser splits on the first hyphen).

## Regenerating the Xcode project

```
xcodegen generate
```

## Verifying the build (CLI)

```
xcodebuild -project Vohe.xcodeproj -scheme Vohe \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

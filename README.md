# OHS Act & Regulations — Flutter App

This is the native Flutter port of the OHS Act & Regulations reference app.
It was hand-written (no Flutter SDK was available to scaffold or test it in
the environment that built it), so the platform folders (`android/`, `ios/`,
etc.) are **not yet generated**. Follow the steps below on your own machine
to get it running.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed
  (`flutter --version` should work in your terminal)
- Android Studio (for Android) and/or Xcode (for iOS, Mac only)

## First-time setup

1. Unzip this project and `cd` into the folder.
2. Generate the missing platform folders — this is safe and won't touch
   the `lib/`, `assets/`, or `pubspec.yaml` files already here:
   ```
   flutter create .
   ```
3. Install dependencies:
   ```
   flutter pub get
   ```
4. Run it on a connected device, simulator, or emulator:
   ```
   flutter run
   ```

## Project structure

```
lib/
  main.dart                    — app entry point, bottom nav shell
  models/entry.dart            — data model for one section/regulation
  data/entries_repository.dart — loads assets/data/entries.json, search & quick-jump logic
  theme/app_theme.dart         — colors, fonts, hazard-stripe header
  screens/
    explore_screen.dart        — Home & Search tabs (category → collection → sections, search)
    detail_screen.dart         — single section/regulation view with Prev/Next
    more_screen.dart           — More tab: Checklist placeholder + bug report form
assets/
  data/entries.json            — all 486 entries (Act + 25 regulation sets)
```

## Things to verify once you can run it

- **Bug report form** (More tab): submits to a Formspree endpoint via a
  direct HTTP POST from the app — this should work correctly now that it's
  a native app rather than a browser-opened local file (the earlier
  referer/CORS restriction was specific to `file://` browser pages). Worth
  testing a real submission once to confirm and to complete Formspree's
  one-time confirmation step if you haven't already.
- **Fonts**: uses `google_fonts`, which downloads font files on first run
  (needs network access once; they're cached after that).
- **App icon, splash screen, and store metadata**: not set up yet — still
  using Flutter's defaults.

## Known gaps vs. the HTML prototype

- No offline font bundling yet (google_fonts fetches on first launch).
- No app icon / launch screen customization yet.
- Checklist feature is still just a "Coming soon" placeholder, matching
  where the HTML prototype left off.

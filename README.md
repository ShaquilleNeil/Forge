# Forge — Powerlifting Training & Coaching

Forge is a Flutter + Firebase powerlifting app with two sides in one account:
a **training side** for the lifter (workouts, programs, rest timer, progress)
and a **coach side** (client pairing by QR code, programs sent to clients).
It syncs with a Google Sheet training log — the sheet is the source of truth
for the program, and the app writes actuals (RPE, bar speed, status, new-best
singles) back to it.

> **Demo data:** everything in this repo is fictional sample data — the
> lifter is "Alex Morgan", the program is "Iron Ascent", and the sample
> 1RMs are 180 / 120 / 200 kg (squat / bench / deadlift). No real training
> data, names, or spreadsheet contents are included.

## Features

**Training**
- **Today** — the next uncompleted program day, PRs, meet countdown, streak
- **Programs** — multi-week programs (weeks → days → exercises), move a
  workout to another day, mix or shift the existing workout
- **Workout runner** — set-by-set logging with rest timer (main 3:00 /
  accessories 1:30, configurable), superset support, bar-speed and RPE
  per set, video attachable to a set (max 60 s)
- **History & Progress** — heaviest sets, top singles, DOTS and GL points,
  bodyweight tracking, volume trends
- **Google Sheets sync** — import a program from a sheet the user picks
  (read-only Drive + Sheets scopes; no spreadsheet ID is hardcoded) and
  write back actuals only into empty cells, never overwriting

**Coaching**
- Pair a client by QR code or pairing code — the coach sees finished
  workouts, sets, and videos
- Build and send programs to a client (never auto-activates on their side)
- Client list with progress and last-workout status

## Screenshots

UI previews generated from the app's design tokens (black `#0A0A0A`,
orange `#FF6B00`).

| Today | Programs | Coach |
| --- | --- | --- |
| ![Today](docs/screenshots/today.png) | ![Programs](docs/screenshots/programs.png) | ![Coach](docs/screenshots/coach.png) |

## Tech stack

- **Flutter** 3.47 / **Dart** 3.13 (single codebase, iOS + Android)
- **Firebase Auth** (email + Google), **Cloud Firestore**, **Cloud Storage**
  (set videos), **Cloud Functions** (server-side sync helpers)
- **Google Sheets / Drive API** (read-only scopes) for the training-log sync
- Kilos are the stored truth; kg/lb is a display preference only
- Epley e1RM, DOTS, and GL-points strength math in `lib/services/strength_math.dart`

## Getting started

```bash
# 1. Install Flutter, then from this folder:
flutter pub get

# 2. Create a Firebase project and wire it up (generates
#    lib/firebase_options.dart, which is git-ignored and NOT in this repo):
dart pub global activate flutterfire_cli
flutterfire configure

# 3. Run it:
flutter run
```

Google sign-in requests Drive + Sheets **read-only** scopes so the
spreadsheet import can read a sheet the user picks.

## Project structure

```
lib/
  main.dart            Firebase init, AuthGate, AppShell (bottom nav:
                       Today, Program, + Start workout, History, Progress)
  theme.dart           ForgeTheme — black/orange design tokens, dark theme
  models/              UserProfile, Program/ProgramWeek/ProgramDay/
                       ProgramExercise, WorkoutSession/SessionSet,
                       Exercise, Record, BodyweightEntry, Submission
  services/            AuthService, FirestoreService, StorageService,
                       PlatesService, StrengthMath (Epley e1RM, DOTS,
                       GL points), SessionStore (crash-safe in-progress
                       workout), SheetImportService (Sheets two-way sync)
  screens/             Today, Program, workout runner, History, Progress,
                       coach screens, settings, tutorial
  widgets/             shared cards, dialogs, timers
functions/             Cloud Functions (sync helpers)
firestore.rules        Firestore security rules
storage.rules          Storage security rules
docs/screenshots/      UI preview images
```

## Notes

- Set videos: max 60 seconds, stored at `users/{uid}/videos/{setId}.mp4`.
- The sample program "Iron Ascent" and the 180/120/200 kg lifts are
  placeholders — replace them with your own program and numbers.

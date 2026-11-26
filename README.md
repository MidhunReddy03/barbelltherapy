# GymDesk 🏋️

An **offline-first gym manager app for a single gym owner** (Android, Flutter).
No cloud, no accounts, no subscriptions — all data lives on the phone with
manual backup/restore. WhatsApp messages are semi-automatic: the app prepares
the message and opens `wa.me`; the owner taps Send.

Built in phases (see `DECISIONS.md`). **Phase 1 (Foundation) is complete.**

## Tech stack

- Flutter (Android only, min SDK 23) + Dart null safety
- `flutter_riverpod` (state), `go_router` (navigation)
- `drift` (SQLite) — schema in `lib/data/database.dart`
- All money as **integer rupees**; all dates as **date-only `yyyy-MM-dd` strings**

## Setup (one-time, ~15 minutes)

### 1. Install Flutter

Follow https://docs.flutter.dev/get-started/install/windows
(SDK + Android Studio; you can defer the Android SDK until you want to build
the APK — `flutter test` works without it).

### 2. Generate the Android platform folder — already done ✓

`flutter create --org com.gymdesk --project-name gymdesk --platforms android .`
has already been run and the `android/` folder is committed. Only re-run it
if you ever delete that folder.

### 3. App-lock biometrics — already applied ✓

`MainActivity.kt` already extends `FlutterFragmentActivity` and the manifest
already declares `USE_BIOMETRIC` + the biometrics uses-feature (required for
`local_auth`). Nothing to do here — this section stays as documentation of
*why* those files are the way they are.

### 4. Fonts (optional, for 100% offline font rendering)

Run the helper script (downloads Inter + Noto Sans Telugu into
`assets/google_fonts/`):

```powershell
powershell -ExecutionPolicy Bypass -File tool\setup_fonts.ps1
```

Then add to `pubspec.yaml` under `flutter:`:

```yaml
  assets:
    - assets/google_fonts/
```

Without this step the app still works: `google_fonts` fetches fonts on first
launch and caches them; Android's built-in Telugu font renders Telugu text.

### 5. Install dependencies and generate the database code — already done ✓

`flutter pub get` and
`dart run build_runner build --delete-conflicting-outputs`
have already been run; `lib/data/database.g.dart` exists. Re-run
`build_runner` after any schema change (`lib/data/database.dart`).

### 6. Run and test

```powershell
flutter test          # unit tests (domain logic: dates, pricing, reminders…)
flutter run           # on a connected device/emulator
flutter build apk --release   # needs the Android SDK installed
```

## Project layout

```
lib/
  core/        theme, constants, router, providers, utils, shared widgets
  data/        drift tables, seed data, repositories
  domain/      pure business logic (status, end dates, pricing, reminders,
               templates) — fully unit-tested
  features/    onboarding/ auth_lock/ home/ members/ reminders/ checkin/ more/
  app.dart main.dart
test/          unit tests
tool/          helper scripts
```

## Daily routine for the owner (short version)

1. Open **Reminders** → send today's messages (WhatsApp opens per member).
2. Use **Check-in** at the desk all day.
3. Weekly: run **Backup** (arrives in Phase 6) to a zip you copy to Drive.

## Status / roadmap

- **Phase 1 — DONE.** Theme, 5-tab navigation shell, drift schema (all
  tables), settings store, first-run wizard, app lock, working Home cards,
  members list (search), basic reminders flow, basic check-in flow, Settings.
- Phase 2 — Plans & add-ons CRUD, full enroll flow, member profile.
- Phase 3 — Payments, dues, freeze, renewal, cancel/archive.
- Phase 4 — Full reminder engine, template editor (EN/TE), announcements.
- Phase 5 — QR check-in, dashboard charts.
- Phase 6 — Reports/exports, backup/restore, polish, QA pass.

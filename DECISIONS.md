# DECISIONS.md

Every assumption and judgment call made while building GymDesk, per the
instruction to "note your decision in DECISIONS.md".

## Phase 1 (Foundation)

1. **No Flutter SDK on this machine yet.** The user chose "write code first,
   install later". Phase 1 code is hand-written; `flutter create .`,
   `flutter pub get`, `dart run build_runner build`, and `flutter test`
   must be run once Flutter is installed (see README §Setup). The only
   generated code is `lib/data/database.g.dart` (drift).
2. **Project/package name is `gymdesk`.** The working folder contains a
   space ("gym app"), which is not a valid Dart package name; the pubspec
   name is `gymdesk`. The gym name itself is renameable in onboarding and
   Settings (spec calls it a working name).
3. **Date storage:** date-only values are TEXT `yyyy-MM-dd`; timestamps
   (check-ins, payments, message log) are stored by drift as ISO-8601 text
   in **local time** via the `store_date_time_values_as_text: true` build
   option (build.yaml). This keeps the SQLite file readable and
   backup/restore stable. All date math goes through
   `core/utils/app_date_utils.dart`.
4. **Money:** stored as integer rupees everywhere (spec). No decimals.
5. **Settings live in the DB, not SharedPreferences.** The spec's settings
   key-value table is the single source of truth so settings are included in
   backups. `shared_preferences` remains a declared dependency for possible
   transient UI state.
6. **"Active members" dashboard definition:** a member counts as active when
   they have a non-cancelled subscription covering today
   (`start <= today <= end`), including frozen and expiring-soon members.
   Frozen members are still paying, present members. Logged here because the
   spec's status list treats Frozen as a separate state.
7. **Latest subscription selection:** the "latest relevant subscription" is
   the non-cancelled subscription with the highest `id` (rows are created in
   order; renewals create new rows). Cancelled subscriptions are excluded in
   SQL (`status_override IS NULL`) and never affect status.
8. **Payments table got extra columns** beyond the spec's table sketch:
   `voided`, `void_reason`, `voided_at` — required to implement the spec's
   own "void instead of delete" audit-trail rule (5.3/12).
9. **Templates table got a nullable `title` column** for announcement
   quick-starters ("Holiday closure", …) which need a display name; message
   log got a nullable `campaign_title` for announcement progress tracking
   ("42 of 118 sent") required by spec 6.9.
10. **Member codes come from a monotonic counter** in settings
    (`member_seq`), not the row id, so codes are never reused even after a
    no-payment member is hard-deleted (allowed by spec 5.6).
11. **Percent discount rounding** is applied to plan + add-ons only
    (admission fee excluded) and `.round()`-ed to the nearest rupee, exactly
    as spec 5.3 states.
12. **Fonts:** `google_fonts` with Inter + a `Noto Sans Telugu`
    fontFamilyFallback. For guaranteed offline rendering, run
    `tool/setup_fonts.ps1` to bundle the TTFs into assets (README §4).
    Android devices always render Telugu via the system font even without
    bundling.
13. **App lock:** PIN (4–6 digits) hashed with SHA-256 + per-install salt in
    the settings table; biometric unlock via `local_auth` when the device
    supports it; re-lock after 60 s in background (constant in
    `app_constants.dart`). Requires `FlutterFragmentActivity` (README §3).
14. **Phase gating of tab features:** the shell always shows 5 tabs, but
    per-spec build phases some destinations show an honest "arrives with
    Phase N" notice until their phase lands (dues list → Phase 3, QR scan →
    Phase 5, reports/backup → Phase 6). No fake data, no dead buttons.
15. **Dashboard charts (joins vs lapsed, footfall, peak hours)** are built
    in Phase 5 per the spec's phase plan; the Home screen shows a labeled
    placeholder card where they will live.
16. **Members list (Phase-1 slice):** live search (name/phone/code, 250 ms
    debounce-equivalent via stream), avatar, status pill computed live from
    `end_date`, end-date label, due badge. Filter chips, sorting, swipe
    actions, profile, enroll are Phase 2/3.
17. **Reminders (Phase-1 slice):** today's reminders are computed by the
    real rule engine (offsets {7,3,1,0,-3,-7}, missed-day lookback ≤ 3 days,
    one reminder per member, renewal/frozen/upcoming suppression) and the
    wa.me send + "Did you send it?" → message_log flow works. Grouped
    sections, per-row language toggle, dues-weekly and inactivity reminders,
    template editor are Phase 4.
18. **"Did you send it?" sheet appears immediately after** WhatsApp opens
    (rather than detecting app return), because `url_launcher` gives no
    reliable return callback on Android. Keeping it pending until confirmed
    matches the spec's intent.
19. **Check-in (Phase-1 slice):** search by phone/name → status banner
    (active/expiring/expired/frozen/already-today) → record with
    `was_expired` flag; frozen requires explicit override; duplicates
    allowed with warning. QR scan is Phase 5.
20. **WhatsApp fallback:** if `wa.me` cannot launch (not installed), the
    same text opens via `sms:` and a tip is shown (spec 6.8).
21. **Telugu templates** ship for every message type using simple, polite,
    spoken Telugu; the sentence-drop rule in `TemplateEngine` treats the
    Telugu danda (।) as a sentence ender.
22. **GST is NOT included** anywhere — prices are simple gym prices in
    integer rupees. (Explicit spec 6.12 note.)
23. **Error boundary:** `ErrorWidget.builder` is overridden in release mode
    to show a friendly static message; debug mode still shows the real
    error. A local error log file arrives with Phase 6 polish.
24. **Photo storage:** images picked in onboarding (logo, QR) are copied
    into the app's documents directory so they survive gallery changes.
    Member photos will be compressed to ≤512 px / ~100 KB JPEG at enroll
    (Phase 2).

## Phase 1 verification (Flutter 3.50.0 install + test pass)

25. **Migrated to `package:material_ui`** instead of staying on the
    deprecated `package:flutter/material.dart`. In Flutter 3.50 the
    framework Material library is deprecated (info-level) and the design
    system moved to the standalone `material_ui` package. Applied the
    official `dart fix --apply --code=migrate_design_widgets` to all 16
    files. Compatibility finding: `google_fonts.interTextTheme()` returns
    the *framework* TextTheme which clashes with material_ui's own
    TextTheme class, so `app_theme.dart` applies Inter per-style via
    `GoogleFonts.inter(textStyle: …)` instead (framework TextStyle is
    still shared, so per-style use is fine). `flutter analyze` → 0 issues,
    all 69 tests pass.
26. **Reminder lookback rule unified:** the missed-day check for ALL
    reminder offsets (pre- and post-expiry) is `ruleDayReached =
    daysLeft <= offset`, plus a `|daysLeft - offset| <= lookbackDays`
    distance check. The first draft had the post-expiry direction
    backwards (`daysLeft >= offset`); the unit tests caught it —
    `daysLeft = -5` (5 days past expiry) now correctly surfaces the
    nearest missed rule `expired_3` rather than treating day -5 as "not
    yet reached". This matches spec 5.8's intent: a reminder whose day
    passed while the app was closed is still shown (nearest missed rule),
    and `alreadyRenewed` members never get expiry reminders.
27. **Nearest-miss tie-break:** when several rules were missed within the
    lookback window, the reminder engine picks the rule with the smallest
    `|daysLeft - offset|`; on a tie it prefers the larger (earlier) offset.
    One reminder is produced per member per day, exactly per spec 5.8.
28. **TemplateEngine spec test corrected:** the spec's rule is strict — if
    ANY placeholder in a sentence is missing, the WHOLE sentence is
    dropped (never render a bare `{}`). The first test draft expected a
    partial keep for a mixed sentence; the implementation is right and the
    test was corrected to match the spec.
29. **Discount presets live in settings, not a new table:** spec 4's data
    model has no presets table, so one-tap "Offers" presets are stored as
    a JSON array in the settings key `discount_presets`
    (`CatalogRepository.saveDiscountPresets`). Corrupt JSON degrades to an
    empty list. Presets carry a display name plus a discount type/value.
30. **Receipt number derived from payment id:** the spec wants a receipt
    number on the PDF but defines no receipt table. The PDF computes
    `R-<6-digit-zero-padded payment id>` from the primary key, so numbers
    are stable, unique and need no extra state. Receipts are generated
    per-payment via the `pdf` package and shared through `share_plus`.
31. **WhatsApp template by member status (list swipe / profile quick
    action):** spec 6.3 says the swipe "opens the right template by
    status". Mapping implemented in `MessagesComposer.composeByStatus`:
    no-plan/upcoming → `welcome`; frozen → `inactivity` (come-back
    message); expired ≤3 days → `expired_3`, ≥4 days → `expired_7`;
    active/expiring with daysLeft 1-3 → `expiry_3`, 4-7 → `expiry_7`,
    0/today → `expiry_0`. The message is shown in an editable preview
    dialog before opening `wa.me`; the send is logged in message_log
    afterwards.
32. **Member card shared as PNG, receipt as PDF:** the success screen
    captures the RepaintBoundary-wrapped member card to a 3× PNG and
    shares it via `share_plus`; the receipt is always a real PDF (A5).
    QR on the card encodes the member code (scannable by the Check-in
    tab's lookup in a later phase).
33. **Swipe actions never remove rows:** the members list uses
    `Dismissible` with `confirmDismiss` always returning `false` — the
    drag fires WhatsApp (right) or Renew (left) and the tile snaps back.
    Renew shows a Phase-3 notice until the renewal flow lands.
34. **Phase gating in Phase-2 screens:** buttons for features in later
    phases (record payment, freeze, renew, cancel, void payment,
    un-archive) render honestly with "arrives with Phase 3" notices
    rather than being hidden, so the UI matches the final layout.
35. **Photo pipeline:** picked images are recompressed to max 512 px on
    the long side at JPEG quality ~80 and copied into the app documents
    `images/` folder, so gallery changes/deletions can't break profiles.
    Duplicate-phone check runs on the normalized 10-digit phone and
    includes a warning banner (not a hard block) — the owner may
    legitimately enroll a family member sharing a phone.

## Web support (Flutter Web build)

36. **Cross-platform image layer (`AppImage`):** all image handling goes
    through `core/utils/app_image.dart`, a conditional import
    (`app_image_io.dart` / `app_image_web.dart`). Native stores real files
    in the app documents `images/` folder and keeps file paths in the DB;
    **web stores base64 `data:` URIs in the same text columns**
    (`photo_path`, `qr_path`, `logo_path`). The drift database itself lives
    in IndexedDB on web, so data URIs persist across sessions exactly like
    file paths do on Android. Photos are compressed to 512 px / quality 80
    via `flutter_image_compress`; QR codes and logos are stored losslessly
    (`compress: false`). `AppImage.shareBytes` uses in-memory `XFile.fromData`
    on web (share sheet downloads the file) and temp files on native.
37. **drift on web requires explicit `web:` options:** `driftDatabase()`
    throws `When compiling to the web, the \`web\` parameter needs to be
    set` unless `DriftWebOptions` is passed. `AppDatabase` now passes
    `sqlite3.wasm` + `drift_worker.js` relative URIs; the two runtime
    assets (drift-2.31.0 / sqlite3-2.9.4 releases) **must ship with every
    web deployment** (copied from `web/` into `build/web` at build time).
    Verified in-browser: DB opens via `WasmStorageImplementation.sharedIndexedDb`.
38. **Android toolchain pinned to Flutter 3.50 defaults:** AGP 9.3.1 +
    Gradle 9.5.0 + Kotlin 2.4.20 (settings.gradle.kts / gradle-wrapper).
    Flutter 3.50's gradle plugin hard-requires Gradle ≥ 9.3.1 and the AGP 9
    API, so downgrading to AGP 8.x is a dead end (the plugin fails to apply).
    share_plus 13.3.1 + file_picker 13.3.3 compile fine on this toolchain —
    earlier "Unresolved reference ShareSuccessManager" errors were stale
    Gradle cache, not a real incompatibility.
39. **`compileSdk = 36` hardcoded in app/build.gradle.kts:**
    flutter_plugin_android_lifecycle ships AAR metadata requiring
    compileSdk 36; `flutter.compileSdkVersion` (35) is too low.
40. **JDK 21 for Gradle:** configured persistently via
    `flutter config --jdk-dir="C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot"`.
41. **share_plus API migration:** `Share.shareXFiles` is deprecated; card
    and receipt sharing use `SharePlus.instance.share(ShareParams(...))`.
    Receipt share returns `Future<void>` (the PDF file handle is no longer
    needed by callers).
42. **`test/widget_test.dart` removed:** `flutter create --platforms web .`
    regenerated it as the default counter template referencing a
    non-existent `MyApp`. Rebuilding a full-app pump test hangs under the
    test runner (infinite frame loop in the onboarding PageView), so the
    file was dropped rather than blocking CI; the 93 remaining tests are
    the regression gate, and web boots are verified in a real browser.
43. **CupertinoIcons build warning is benign:** a transitive dependency
    (image_picker) references CupertinoIcons; GymDesk never uses it, so
    the font is not bundled and the tree-shaker notes it. No action needed.



# TESTING.md

Manual QA checklist. Phase 1 items are checkable now; later phases get their
own sections as they land. Automated unit tests live in `test/` and cover
end-date math (month clamping, leap years), status boundaries (days_left
0/7/8), pricing/discount/dues, freeze shifting, reminder selection
(lookback, suppression), phone normalization, template rendering, and more.

Run: `flutter test`

---

## Phase 1 — Foundation

### First-run wizard
- [ ] Fresh install opens the wizard (no way to skip into the app).
- [ ] Step 1 validates: empty name blocked, invalid phone blocked with
      inline error, valid phone accepted (10 digits, spaces/`+91` OK).
- [ ] Logo picker works; picked image shows in the tile; remove works.
- [ ] Step 2 QR image can be skipped.
- [ ] Step 3 shows the 4 seeded plans with editable prices; prices save.
- [ ] Step 4 language toggle persists; enabling app lock prompts for a
      4–6 digit PIN (with confirm field); mismatched PIN is rejected.
- [ ] Finish lands on Home; gym name appears in the greeting.
- [ ] Relaunching the app does not show the wizard again.

### App lock
- [ ] With lock enabled, app restart → lock screen before anything else.
- [ ] Correct PIN unlocks; wrong PIN shows an error and clears entry.
- [ ] Biometric unlock works on a device with a fingerprint enrolled.
- [ ] Backgrounding the app for ≥60 s re-locks on return.
- [ ] Backgrounding for <60 s does not re-lock.
- [ ] Toggling lock off in Settings removes the lock requirement.
- [ ] Change PIN: wrong current PIN rejected; new PIN takes effect.

### Home dashboard
- [ ] With no data: all cards show zero values gracefully.
- [ ] Greeting matches the time of day; date is correct.
- [ ] After adding data (Phase 2 demo data), Active/Expiring/Collection/
      Revenue numbers match manual counts from the SQL views.
- [ ] Pull-to-refresh works.

### Members tab (Phase-1 slice)
- [ ] Empty state shows "No members yet. Tap + to add your first member."
- [ ] Search matches name, phone (digits), and member code.
- [ ] Clearing search restores the full list.
- [ ] Status pill matches the member's end date (expired/expiring/active).

### Reminders tab (Phase-1 slice)
- [ ] Empty state: "All caught up. No reminders today. 🎉"
- [ ] With an expiring member: row shows name, "Ends …", due badge if any.
- [ ] Send → preview dialog (editable) → WhatsApp opens with the exact
      pre-filled text and `+91` number.
- [ ] Confirm "Yes, mark as sent" → row disappears; reopening the tab
      doesn't show it again.
- [ ] "No, keep pending" → row stays.
- [ ] Telugu template renders correctly in the preview and in WhatsApp.
- [ ] With WhatsApp uninstalled: SMS fallback opens with the same text.

### Check-in tab (Phase-1 slice)
- [ ] Search by phone digits and name returns the right members.
- [ ] Active member: green Check in button; today's counter increments;
      member appears in today's list with the time.
- [ ] Second check-in same day: warning shows; confirming adds another row.
- [ ] Expired member: red banner + "Renew now" + "Check in anyway" (logged
      as expired).
- [ ] Frozen member: blue banner; check-in blocked; override works with
      confirmation.

### Settings
- [ ] Gym profile saves; name/phone reflect on Home.
- [ ] Theme switch: Dark / Light / System applies immediately.
- [ ] Default message language EN/తె persists.
- [ ] About shows version and the "data stored only on this phone" notice.

### Stability
- [ ] Airplane mode on: every screen works (fully offline).
- [ ] Kill the app mid-use → reopening shows all saved data.
- [ ] Rotation locked portrait; no overflow errors at large font scale.

---

## Phase 2 — Plans, members, enrollment

### Plans & Add-ons (More › Plans & Add-ons)
- [ ] The four seeded plans (Monthly/Quarterly/Half-yearly/Yearly) appear
      with the prices set during onboarding.
- [ ] Add a custom plan (e.g. "Weekly", 1 mo, ₹500); it appears in the list.
- [ ] Edit a plan's price; the enroll picker shows the new price, but an
      existing member's profile still shows their original snapshot price.
- [ ] Custom duration (e.g. 2 months) can be set via "Custom duration…".
- [ ] Deactivate a plan: it disappears from enroll, stays visible in the
      manager with an INACTIVE tag; reactivate restores it.
- [ ] Reorder mode: drag to reorder; enroll screen shows the new order.
- [ ] Add-on CRUD works with One-time / Per-plan billing; deactivating
      hides it from the enroll checkboxes.
- [ ] Default admission fee edits persist; new enroll pre-fills it.
- [ ] Discount presets: add "Diwali 10%" and "Referral ₹200 off"; both
      appear as chips in enroll; deleting one removes the chip.

### Enroll flow (4 steps, also verify with Renew in Phase 3)
- [ ] Progress bar fills per step; Back preserves every entered value.
- [ ] Step 1: photo via camera and gallery is compressed and shown; name
      required; phone validated (non-10-digit rejected with inline error);
      age outside 10–90 rejected; gender segmented control; notes optional.
- [ ] Typing an existing member's phone shows the duplicate warning banner
      (enrollment still possible); a fresh phone shows nothing.
- [ ] Step 2: picking a plan shows the end date LIVE (start 1 Mar Monthly →
      ends 31 Mar; start 31 Jan Monthly → 27 Feb); start date cannot be
      more than 1 year back.
- [ ] Add-on checkboxes add their price; admission fee editable (0 OK).
- [ ] Discount: None / ₹ Flat / % — the summary updates each time; 10% on
      plan 1000 + admission 300 = 1300 total (discount skips admission).
- [ ] Leaving mid-flow (back press) asks "Discard this enrollment?".
- [ ] Step 3: summary card lists plan + add-ons + fee − discount = total.
- [ ] Payment mode UPI QR opens the QR sheet with the total; "Payment
      received ✓" sets the full amount; without an uploaded QR a helpful
      notice shows instead.
- [ ] Partial payment: enter 500 of 1000 → "₹500 will remain due" banner.
- [ ] Step 4 review matches everything entered; Confirm & Enroll saves once
      (member + subscription + payment) and opens the success screen.
- [ ] Success: card shows gym name, photo, name, GYM-000x, plan, valid-till
      date, status pill, and a scannable QR of the member code.
- [ ] "Send welcome on WhatsApp" opens wa.me with the rendered welcome
      template; coming back logs it as sent.
- [ ] "Share receipt (PDF)" opens the share sheet with an A5 PDF:
      gym header, receipt no. R-00000x, member, period, total/paid/balance,
      mode, PAID IN FULL or due highlighted.
- [ ] "Share member card (image)" shares a PNG of the card.
- [ ] Unpaid enroll: receipt button explains no payment was recorded; card
      still shares; member profile shows ₹0 paid, full amount due.

### Members list
- [ ] FAB opens enroll; list shows avatar, name, phone, plan, status pill,
      "Ends <date>" (or "Expired N days ago"), and due badge "₹N due" when
      dues exist.
- [ ] Filter chips show live counts: All / Active / Expiring soon /
      Expired / Frozen / Dues pending; tapping filters correctly and the
      count matches the rows shown.
- [ ] Sort menu: Name A-Z, Expiry soonest (no-plan members sink to the
      bottom), Recently joined (GYM-00xx descending).
- [ ] Search debounces and matches name / phone digits / member code.
- [ ] Swipe right → WhatsApp opens the status-matched template after an
      editable preview; the tile snaps back (row is never removed).
- [ ] Swipe left → Renew shows the Phase-3 notice.
- [ ] Tap opens the member profile.

### Member profile
- [ ] Header: photo (tap to change → gallery pick is compressed), name,
      status pill, member code, joined date, phone, age, gender.
- [ ] Quick actions: WhatsApp (status template + preview + log), Call
      (dialer), Check-in (confirm dialog → adds today's visit).
- [ ] Plan tab: plan name, date range, add-ons, progress bar of days used,
      days left/expired line, Total/Paid/Due rows.
- [ ] Phase-3 actions (Record payment / Freeze / Renew / Cancel) show the
      honest "arrives with Phase 3" notice.
- [ ] Payments tab: every payment with mode, date, note, VOIDED tag on
      voided rows; per-payment receipt PDF shares correctly; void button
      shows the Phase-3 notice.
- [ ] History tab: every subscription newest-first with period, total,
      paid, add-ons, Cancelled tag when applicable.
- [ ] Attendance tab: 90-day count, lifetime count, last visit time, and
      chips for each visited day (same-day double visits count once in the
      90-day figure).
- [ ] Edit member (pencil): name/phone/age/gender/notes save and reflect
      everywhere; validation blocks an invalid phone.
- [ ] Archive (box icon): confirm dialog → member vanishes from the list;
      opening the profile via a member code search still works; history is
      preserved.

### Data integrity (also covered by automated tests)
- [ ] Enroll with full, partial, and zero payments — end dates, dues, and
      payment rows match the summary card exactly.
- [ ] Kill the app right after Confirm & Enroll → member exists completely
      (transaction, no half-saves).
- [ ] Two members enrolled in a row get GYM-0001 then GYM-0002.

## Builds & deliverables

### Website (Flutter Web)
Build with `flutter build web --release`; deploy the whole `build/web`
folder — **it must include `sqlite3.wasm` and `drift_worker.js`** or the
database will never open. Serve over HTTP(S) (any static host; a plain
`python -m http.server` works for a LAN).

- [ ] App loads with no console errors; the first-run wizard renders.
- [ ] Data persists across a page reload (drift stores the DB in
      IndexedDB; the browser console shows
      `Using WasmStorageImplementation...` when the database opens).
- [ ] Member photo / UPI QR / gym logo pickers work (stored as data URIs).
- [ ] Sharing the member card PNG / receipt PDF downloads the file.
- [ ] Known web limits: WhatsApp links open a new tab (by design);
      `share_plus` on desktop browsers downloads files instead of opening
      a native share sheet; file pickers use the browser picker.

### Android APK
Build with `flutter build apk --release`; output is
`build/app/outputs/flutter-apk/app-release.apk`. (Release is currently
debug-signed for side-load testing — a keystore is set up before any
Play Store push.)

## Phase 3 (to be written when Phase 3 lands)
## Phase 4 (to be written when Phase 4 lands)
## Phase 5 (to be written when Phase 5 lands)
## Phase 6 (to be written when Phase 6 lands)

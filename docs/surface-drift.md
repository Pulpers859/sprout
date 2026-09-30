# Web and iOS behavior alignment

Updated 2026-09-30. iOS is the behavior reference for shared budget flows.
The web app now follows these behaviors without replacing its Firebase account
and local-cache infrastructure.

## Ported to the web

- Integer-cent arithmetic for budgets, spending, refunds, carryover, archives,
  calendar totals, and truncating daily allowance. Existing web/Firebase dollars
  stay compatible; portable backups use iOS schema 2 integer cents.
- Full-input amount validation, localized decimal/grouping input, trimmed entry
  text, visible validation feedback, and editing expenses/payments in place.
- Zero-budget spending fills the progress bar. Pace uses unclamped spending and
  the iOS asymmetric early-month tolerance. Negative net spending remains visible.
- Stored-month titles, calendar grids, day counts and pace; exact calendar cents
  and a notice when dated entries contribute to totals outside the visible month.
- Weekly, monthly and yearly recurring entries, creation and removal controls,
  short-month day anchoring, bounded catch-up and duplicate-occurrence protection.
  Processing runs on load, foreground return and entry save; no server scheduler.
- Month-by-month rollover with recurring backfill, positive carryover, merged
  same-month archives, future-entry preservation, and a 12-month archive policy
  favoring meaningful months. Repeated closes do not grant the base budget twice.
  Keep advances the ledger without clearing transactions; Cancel is a no-op.
- Backup export/import with strict validation, summary, confirmation and a durable
  device-local pre-import copy for undo. Portable date/UUID/money encoding follows
  the actual iOS Codable schema. No Xcode import execution was performed here.
- Recovery of valid rows/previous device saves, retained damaged source data,
  visible storage/sync errors, and blocked writes when saved data is unreadable.
- Recent-item quick add starts a fresh amount/note/date draft. Category edits save
  immediately instead of relying on closing Settings.

## Deliberate differences and limits

- Web retains Google sign-in, Firebase sync and per-user localStorage. iOS remains
  local-file-only; a shared Google account does not connect the two apps.
- Web cloud conflict resolution is still last-write-wins by timestamp, not a
  transaction-by-transaction merge. Concurrent devices can overwrite changes.
- Web recovery uses browser storage, not filesystem quarantine. Storage eviction,
  private browsing or quota limits can remove/prevent device copies. Exported
  backups are the portable recovery path; failed imports preserve the live ledger.
- Web strict import rejects malformed rows instead of partially replacing data;
  cache recovery can salvage rows but pauses saves until a valid import resolves it.
- Web parsing additionally checks grouping placement. Currency remains USD while
  input separators follow the browser locale; this is not multi-currency support.
- iOS timestamps are absolute. Moving a backup across time zones may change a
  transaction's calendar date, consistent with the native date model.
- Native App Intents, deep links, widgets/system integrations, haptics, Dynamic
  Type and native presentation are not browser features. This is behavior alignment,
  not a reproduction of SwiftUI styling.
- Recurring catch-up is capped at 600 occurrences per rule per pass and rollover
  at 240 months, matching native bounds. These are safety limits, not unlimited
  historical reconstruction.

## Verification

Run the Node regression command in `README.md`. It exercises the pure modules
and the actual HTML controller with fake Firebase, timers, storage and DOM.
Browser checks with synthetic data cover entry validation, recurring creation,
editing expense to payment, correct totals, and the backup confirmation/import UI.
Live Google sign-in/cloud behavior and actual iOS backup import still require
integration/device validation. The generated Swift CI profile/workflow is unchanged.

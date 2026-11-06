# Web and iOS behavior alignment

Updated 2026-11-06. iOS is the behavior reference for shared budget flows.
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

## Timestamp format (both surfaces)

Holiday rows are the first ones web authors itself, which exposed a format
mismatch that had been latent.

- **Every Sprout timestamp is ISO-8601 to whole seconds**, e.g.
  `2026-11-02T12:00:00Z`. iOS encodes with `.iso8601`, and `backup.mjs`'s
  `iso()` has always stripped milliseconds from the monthly fields on export.
  `holiday.mjs` now produces that form at the point of authoring, so the device
  cache, the Firestore document and the exported file all agree, and anything
  already stored in another shape is converted on the next load.
- **iOS decoding accepts fractional seconds as well.** `.iso8601` is
  `ISO8601DateFormatter` with `.withInternetDateTime` and *not*
  `.withFractionalSeconds`, so `…T12:00:00.000Z` failed to decode — and failed
  silently: a gift's `date` and a person's `createdAt` fell back to
  `.distantPast` (year 1 AD), a season's `startedAt` likewise, and an archived
  `closedAt` to `nil`. `SproutDate.iso8601` now tries both forms.
  `JavaScript`'s `toISOString()` always emits three decimals, so any tool other
  than Sprout itself writes that shape. Encoding is unchanged.

## Holiday spending (ported 2026-11-06)

The Holiday tab now exists on both surfaces: a third section with its own
budget, the people being bought for, gifts, returns, and seasons.

- Separation is structural on both. iOS keeps gifts in `snapshot.holidaySeason`
  and types `BudgetTab` so monthly math cannot be handed `.holiday`. Web splits
  `state.activeSection` from `budgetCat()`, which only ever answers `personal`
  or `grocery` — so `getTx`/`netSpent`/`getBudget`/`getCarryover` and the
  `['personal','grocery']` guards in `ledger.mjs` cannot be pointed at a season.
- Shared logic lives in `Sprout-html/holiday.mjs`, which mirrors
  `HolidayModels.swift` and the holiday half of `BudgetStore.swift`: net-of-returns
  totals, per-person tallies counting gifts and returns separately, `unreserved`
  (never greater than remaining, so it cannot contradict the headline),
  gifts-only counting for copy, normalization that renames rather than deletes,
  duplicate-id re-identification, orphan re-homing, the archive cap, archive-time
  label de-duplication and the backwards-clock guard on `closedAt`.
- **Holiday money is integer cents on both surfaces**, including inside web
  state, where every monthly amount beside it is dollars. That asymmetry is
  deliberate: holiday data has only ever been written by iOS at schema v2 in
  cents, and web snapshots already on disk carry it that way under
  `schemaVersion: 1` because an earlier web build passed it through
  uninterpreted. Rescaling it by version would read every stored $40 gift as
  $4,000. `holiday.mjs` names every money helper `...Cents` for that reason.
- `normalizeSeason` writes a complete, fixed key set and preserves keys it does
  not model. Both matter: Firestore writes use `{merge: true}`, which
  deep-merges nested maps, so an active season written without `closedAt` would
  inherit the closed stamp of the season it replaced; and dropping unmodelled
  keys would make an iOS -> web -> iOS round trip lossy for any field iOS adds
  later.
- A damaged holiday row costs that row on both surfaces, not the section. Web
  validates per row like its own `list()` does for transactions and archives,
  and `normalizeSeason` drops a row whose amount is unreadable rather than
  coercing it to zero — matching iOS, where `amount` is a required decode. An
  unreadable per-person target is no target rather than a target of zero, which
  is the distinction `plannedAmount` exists to carry.
- The import confirmation names holiday data on both sides on both surfaces:
  what the incoming file carries (distinguishing "no holiday data" from a season
  with zero gifts, from the raw payload) and what the import would destroy.
- Holiday keys count toward the backup signature on both surfaces, so a
  holiday-only export is not rejected by one and accepted by the other.

Holiday differences that remain:

- Web has no pushed per-person screen, because the page has no navigation stack.
  The per-person view is an in-place swap with a Back button, keyed by
  `state.holidayDetailId`.
- iOS has `sprout://quick-add?tab=holiday` and a "Log Holiday Gift" App
  Shortcut. Web has no deep links or intents, as for every other flow.
- Holiday gifts have no recurring rules on either surface. That is a
  monthly-ledger concept and a recurring gift is not a thing.
- Returns exist on both: a returned gift keeps its own row and nets off the
  season total, the way a monthly payment nets off `netSpent`.
- Web has no pace label or month-ending banner on the Holiday tab, because a
  season has no time dimension — the same reason iOS omits them there.
- Web pauses saving when any stored row had to be salvaged, holiday rows
  included. iOS reports the loss and keeps saving. That is the pre-existing
  recovery difference below, not a holiday-specific one.

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

## Known remaining drift

Found by an independent audit on 2026-11-06 and not yet closed. Listed here
rather than described as aligned.

- **Web is ahead of iOS in four places.** Web can convert an expense to a
  payment while editing (iOS forces delete-and-re-enter); web mints stable
  recurring-occurrence ids (`recurring:<ruleId>:<date>`) deduped against the
  live ledger and every archive, where iOS mints a fresh UUID per occurrence and
  relies on the rule cursor alone; web blocks writes while saved data is
  unreadable and offers to export the recovered and original copies, where iOS
  alerts and keeps writing; web validates grouping placement when parsing an
  amount, rejecting a mistyped `1,2` that iOS reads as 12. None of these is
  fixed on iOS.
- The 12-month archive cap is applied on web only when archiving, not on
  import, so importing a 20-month backup leaves 20 archived months on web and
  12 on iOS. Web deliberately keeps everything an import carries.
- iOS has a month-ending banner that closes the month out when tapped; web has
  only a passive notice and the header Reset button.
- iOS shows success toasts and haptics after a save; web just closes the form.
- iOS lets a category use any emoji from the keyboard; web offers a fixed grid.
- iOS groups the recurring list by tab and sorts by next date; web lists it in
  array order.
- iOS quarantines corrupt saves to timestamped files and prunes to three; web
  keeps one `:recovery` slot in browser storage.

## Verification

Run the Node regression command in `README.md`. It exercises the pure modules
and the actual HTML controller with fake Firebase, timers, storage and DOM.
Browser checks with synthetic data cover entry validation, recurring creation,
editing expense to payment, correct totals, and the backup confirmation/import UI.
Live Google sign-in/cloud behavior and actual iOS backup import still require
integration/device validation. The generated Swift CI profile/workflow is unchanged.

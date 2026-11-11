# Web and iOS behavior alignment

Updated 2026-11-10. iOS is the behavior reference for shared budget flows.
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
  already stored in another shape is converted on the next load. This was true
  of the holiday fields and the export from the start, and *not* of
  `monthHistory[].archivedAt` or `updatedAt`, which kept their milliseconds in
  the cache and the Firestore document until an audit on 2026-11-08 caught it.
  Both are whole seconds now, and a test asserts that none of the three sinks
  carries a fractional stamp — previously only the export was ever checked,
  which is exactly why it went unnoticed.
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
- `normalizeSeason` writes a complete key set for every key it models, and
  preserves keys it does not. Those two rules are in tension and the merge
  resolves it in favour of stale data: `startNewSeason` builds a literal with
  only the modelled keys, so an unmodelled key stored on the previous season is
  not in the write and survives under `{merge:true}` onto the new one. Latent
  today — iOS's `HolidaySeason` has exactly the modelled keys — but it fires the
  first time iOS adds a field, which is the stated reason the spread exists.
  Recorded, not fixed. The recipient/purchase case cannot occur for a reason
  the original note missed: those are arrays, which Firestore replaces whole
  rather than merging element-wise. Both matter: Firestore writes use `{merge: true}`, which
  deep-merges nested maps, so an active season written without `closedAt` would
  inherit the closed stamp of the season it replaced; and dropping unmodelled
  keys would make an iOS -> web -> iOS round trip lossy for any field iOS adds
  later.
- A damaged holiday row costs that row on both surfaces, not the section. Web
  validates per row like its own `list()` does for transactions and archives,
  and `normalizeSeason` drops a row whose amount is unreadable rather than
  coercing it to zero — matching iOS, where `amount` is a required decode. Two
  shapes escaped that until 2026-11-08 and are now aligned: a **fractional**
  amount (web truncated it, so a stored `plannedAmount: 1.5` became a real
  $0.01 target that switched on the planning line and painted the bar red,
  where iOS read no target at all), and a row with **no `name`** (web renamed
  it "Someone"/"Gift" and kept its money with no warning, where iOS drops it,
  because `name` is a required decode there for both row types). Web now drops
  both — and the importer reports the nameless one, since a row that vanishes
  with its money and says nothing is worse than one that was never dropped. An
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

## Presentation (web restyled 2026-11-10)

The web app now uses the iOS app's design rather than its own.

- Colours are the values in `Color+Sprout.swift`, light and dark, including the
  three hero gradients and the berry holiday accent. Type is the system face
  (`-apple-system`, with `ui-rounded` for titles and money), which on an iPhone
  is the same San Francisco the app renders. The three Google web fonts are gone.
- Layout follows the iOS dashboards: "Sprout" title with circular settings and
  "…" buttons, a pill section picker under it, a gradient summary card with the
  balance as its headline, two pill actions, then avatar rows with a trailing
  amount. Secondary holiday actions (rename, new season, record a return, past
  seasons) and sign-out live in the "…" menu, as they do on iOS.
- The section picker is at the top, not along the bottom edge. That matches
  iOS, and it keeps every control out of the bottom-right corner, where
  Netlify's free plan pins a hosting badge that cannot be turned off.
- Still different, on purpose: forms open in place as a card rather than as a
  slide-up sheet. A bottom sheet under the iPhone keyboard is the classic
  mobile-web failure and it cannot be tested from this repo's tooling. Row
  options are a tap on "…" rather than a long-press, and there are no haptics,
  toasts, or animated transitions between tabs — the page is rebuilt on every
  change, so entry animations would replay on every tap.
- Per-person edit and remove moved off each row and onto the person's own
  screen, where iOS has them. The row itself opens the person.

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
  Undo Import used to be a second, unintended way out: it cleared the pause
  unconditionally, so the salvaged ledger went live and saved freely, and the
  preserved original became unreachable because its download button was gated
  on the pause. The pause is now restored with the data it belongs to, and the
  download button follows the copy rather than the pause.
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

- **Web is ahead of iOS in two places.** Web can convert an expense to a
  payment while editing (iOS forces delete-and-re-enter); web mints stable
  recurring-occurrence ids (`recurring:<ruleId>:<date>`) deduped against the
  live ledger and every archive, where iOS mints a fresh UUID per occurrence and
  relies on the rule cursor alone.

  On the recurring ids: this is belt-and-braces on web rather than a live iOS
  bug, and the earlier wording here overstated it. iOS persists rules and
  transactions in one snapshot file, written atomically, so the cursor cannot
  drift behind the rows it posted. Web's stable ids guard a case iOS does not
  have. The difference still matters in one direction — a row iOS drops on a
  lossy load is never reposted, because the cursor stayed ahead of it, where
  web's dedupe would notice the gap and fill it. **That claim was wrong** and
  is withdrawn: `processRecurring` only ever iterates forward from
  `nextOccurrenceDate`, so a gap behind the cursor is never revisited on web
  either. The stable ids guard a double-post, not a missing post.

- **Resolved 2026-11-06: iOS accepting a mistyped amount.** iOS stripped the
  locale's grouping separators before parsing, so `1,2` read as `$12` — a silent
  tenfold mis-entry on the one field where the user is typing money, and the
  same permissiveness that once turned `1 2` into `12`. `SproutMoneyText` now
  validates grouping against the locale's own shape instead of stripping it,
  including the two-then-three pattern en_IN uses, and `isZeroAmount` agrees
  with it so `0,0` is no longer read as a deliberate zero budget. One
  consequence is deliberate: `"12.50"` in de_DE is now rejected rather than read
  as €1,250, which is what web already did.

  The first version of this fix did not apply in any locale whose grouping
  separator *is* a space. `stripped()` deleted U+00A0 and U+202F outright, and
  deleted plain spaces wherever the locale grouped with one, so by the time the
  placement check ran there was no separator left to look at and `"1 2"` still
  read as 12 in fr_FR, sv, fi, nb, pl, cs, ru and a dozen more — the exact
  mis-entry the check exists to catch, silently exempt in a third of the
  locale set. `stripped()` now rewrites each kind of space *to* the locale's own
  separator and lets the check judge the placement, which is what web's
  `parseAmount` does. In locales that group with punctuation a non-breaking space
  is still stray decoration and is still removed, and a plain space is still left
  in place so `"1 2"` fails the strict character scan.

  One gap remains: the non-Latin-digit path hands the whole string to
  `NumberFormatter` without a grouping check, where web transliterates the digits
  first and then checks. A related consequence, unchanged by this work, is that
  `isZeroAmount` only accepts Latin digits, so a zero budget cannot be entered as
  `"٠"`.

  A visible side effect worth stating: validation is computed from the live text
  on every keystroke, so typing `1,234` in en_US now passes through `"1,"` and
  `"1,2"`, each of which is invalid, and the error line appears and Save disables
  until the final digit lands. Previously `"1,2"` parsed as $12 so nothing
  flashed. Web behaves the same way.

- **Resolved 2026-11-06: iOS writing over a partially-recovered ledger.** iOS
  quarantined a save file it could not parse at all, but not one that parsed
  only by dropping rows — the more dangerous case, because the app carries on
  as normal and the next save destroys the evidence. The alert even said the
  loss "could not be restored", which was true only because nothing had kept a
  copy. `load()` now writes the bytes as they were read to
  `budget-data.partial-<stamp>.json` before anything can overwrite them, keeps
  one copy per distinct damaged file rather than one per launch, and prunes each
  kind of kept copy against its own limit so a run of partial saves cannot evict
  an unparseable one. `undoImport()` preserves too, because it is the one path
  that destroys its own source: it overwrites the save, pushes the imported file
  into the previous generation, and then deletes the pre-import copy. This is the
  iOS-native answer to the same risk; web's answer (block writes until an import
  resolves it) stays as it is, because blocking writes on the primary surface
  would make the app unusable.

  **The copy is not reachable by the user.** The save lives in Application
  Support and the app ships without `UIFileSharingEnabled` or
  `LSSupportsOpeningDocumentsInPlace`, so the Files app cannot see it, and the
  only import path is a document picker that cannot reach the app container. The
  copy is therefore worth exactly one thing today — it rides along in an
  encrypted device backup, and a later build could offer it — so the alert says
  only that the file was kept, and does not name it or suggest opening it. The
  alert also still tells the user to restore a backup in Settings, which is the
  one step they can actually take; an earlier draft of this change moved that
  sentence into the branch where no copy was written, i.e. showed the only
  actionable instruction on the rarer path.

  One claim made while landing this was wrong and is corrected here: a
  damaged-but-readable file *is* usually rewritten on the first load, because
  `finishLoad()` processes recurring rules and persists whenever one was due. The
  content dedupe therefore only does work for a user with no rule due that day.
  The copy is still written before any of it.

- **Resolved 2026-11-06: a save file that could not be *read* was treated as
  corrupt.** `load()` shared one `catch` between "could not open the file" and
  "could not decode the file". The save is written
  `.completeFileProtectionUnlessOpen`, so a launch while the device is locked
  fails on the read with a perfectly healthy ledger on disk — and the shared
  handler quarantined it, moving the user's real file aside and starting them
  fresh or from the previous generation. The read is now separate: the file is
  left exactly where it is, a distinct alert explains that the data is unchanged
  and to reopen unlocked, and every write is blocked while that state holds so
  the empty in-memory snapshot cannot be saved over the real one by the next
  edit. An explicit backup import lifts the block, since it is the only way out
  if the file is permanently unreadable, and deliberately leaves no undo point
  because the snapshot it would capture is the empty one.
- The 12-month archive cap is applied on web only when archiving, not on
  import, so importing a 20-month backup leaves 20 archived months on web and
  12 on iOS. Web deliberately keeps everything an import carries. Holiday
  history did **not** follow that rule until 2026-11-08 — a strict import ran
  the six-season cap and silently discarded the rest with zero warnings, and
  `holidayImportSummary` counted the already-trimmed list so the confirmation
  under-reported what the file held. `normalizeHistory` now takes
  `limit: false`, which the importer uses.
- **Resolved 2026-11-08, from an adversarial audit of the web surface.** Four
  more, all web-only: `exportBackup` ran the stable recurring-occurrence id
  `recurring:<ruleId>:<date>` through its UUID coercion, which hashes anything
  that is not already a UUID — so after one export/import round trip the
  occurrence id could no longer be derived from the rule id and the dedupe that
  prevents a double charge was silently dead; only the embedded rule id is
  rewritten now, so the two still match. Holiday ids rode out of the export
  verbatim while every monthly id was coerced, and on iOS a non-UUID
  `recipientID` decodes to nil, so **every gift would lose its person** while
  keeping its money — reachable whenever `crypto.randomUUID` is absent or the
  file was hand-edited. The gift form did no date validation, so a cleared date
  field while editing silently overwrote a gift's real date with the save time,
  where the monthly form has always refused it. And the import-confirmation
  summary was the one unescaped interpolation left; its inputs are numeric
  today, but it sits beside the one that carries the season label and was
  already a stored-XSS once.

- Known and accepted on web, from the same audit: `exportBackup` anchors dates
  at noon, which covers ±12h, so a backup moved between a +13 zone and a
  negative one can shift an entry out of its month and change that month's
  total; a pre-2000 `startedAt` on an archived season is rewritten to "now" on
  first normalize, which can sort it above genuinely recent seasons; and
  `saveLocalCache` validates the rotation target before the primary write, so a
  rotation failure loses the save rather than the backup copy.

- Resolved 2026-11-10: web's month notice is now a tappable banner that opens
  the same close-out dialog, as on iOS. "Reset" itself moved into the header's
  "…" menu as "Start a new month".
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

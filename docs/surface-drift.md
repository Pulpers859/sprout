# Web ↔ iOS surface drift

Recorded during the September 2026 audit. `Sprout-html/index.html` is the legacy
behavior reference; `Sprout-iOS` is the product. These are the places where the
two now genuinely disagree, so nobody re-derives "correct" behavior from the
wrong surface.

Each item says which surface is authoritative. Where iOS is authoritative the
web prototype is knowingly behind — it was left alone rather than rewritten,
because there is no test harness for it and it is not the shipping product.

## iOS is authoritative

| Behavior | iOS | Web | Why it matters |
| --- | --- | --- | --- |
| Money representation | Integer cents (`MoneyAmount`, schema v2) | `Number` dollars | Repeated float addition drifts; the web can accumulate sub-cent error across a long ledger. |
| Multi-month rollover | Walks month by month, giving each skipped month its own recurring backfill, archive entry, and carryover | Single collapsed reset | On the web, skipping two months loses those months from history and posts nothing for them. |
| Recurring rules | Fully processed — catch-up posting, day anchoring across short months, loop bounds | Stored in state and persisted, never processed | A rule created on iOS and synced to the web would simply never fire there. |
| Amount parsing | One parser (`SproutMoneyText`), locale separators, strict character set | `parseFloat` | `parseFloat("12abc")` is `12`; the web accepts trailing garbage. |
| Corruption recovery | Quarantine, previous-generation fallback, per-row lossy decode, user-visible alerts | No equivalent | The web silently falls back to defaults. |
| Backup import | Validated, summarized, confirmed | No import path | — |
| Stored-month display | Day count, pace, calendar grid and header all key off the stored month | Wall clock | Web shows the new month's grid over the old month's ledger when a rollover is pending. |
| Pace tolerance | Widens early in the month | Flat 2% | The web flags "too fast" for any purchase over ~5% of budget on day 1. |

## Web only

- Firebase Google auth, cloud sync, and last-write-wins merge by `updatedAt`.
  iOS is local-file only and has no account concept.
- `localStorage` cache keyed per user.

## iOS only

- Recurring transactions, archived month detail, backup export/import,
  App Intents and the `sprout://quick-add` deep link, haptics, Dynamic Type.

## Shared and intentionally identical

- Two budget scopes (personal, grocery) with independent budgets and carryover.
- `remaining = base + carryover − netSpent`, refunds subtract.
- Carryover on reset clamps negatives to zero.
- Archive cap of twelve closed months, newest first, deduplicated by month key.
- Default budgets: personal $200, grocery $400.

## If you change shared behavior

Change iOS first, add the test, then decide explicitly whether the web
prototype follows. Record the decision here. Do not let the two drift silently:
that is failure mode 5 in `AGENTS.md`.

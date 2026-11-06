import test from 'node:test';
import assert from 'node:assert/strict';
import {
  HISTORY_LIMIT, defaultSeasonLabel, emptySeason, seasonSpentCents, seasonRemainingCents,
  seasonHasBudget, giftCount, returnCount, recipientTally, hasPerPersonTargets, plannedTotalCents,
  remainingTargetsCents, unreservedCents, seasonProgress, recipientProgress, purchasesNewestFirst,
  purchasesFor, findRecipient, recipientsInDisplayOrder, unassignedRowCount, seasonIsEmpty,
  normalizeSeason, normalizeHistory, uniqueArchivedLabel, startNewSeason,
} from './holiday.mjs';

const at = iso => new Date(iso);
const person = (id, over = {}) => ({ id, name: id, emoji: '🎁', plannedAmount: null, createdAt: '2026-11-01T12:00:00.000Z', ...over });
const gift = (id, over = {}) => ({ id, recipientID: null, name: id, amount: 1000, note: '', date: '2026-11-02T12:00:00.000Z', isReturn: false, ...over });

const season = (over = {}) => normalizeSeason({
  id: 'season', label: 'Holiday 2026', budget: 0, recipients: [], purchases: [],
  startedAt: '2026-11-01T12:00:00.000Z', closedAt: null, ...over,
}, at('2026-11-06T12:00:00Z'));

test('a fresh season has no budget rather than a budget of zero', () => {
  const fresh = emptySeason(at('2026-11-06T12:00:00Z'));
  assert.equal(fresh.label, 'Holiday 2026');
  assert.equal(fresh.budget, 0);
  assert.equal(seasonHasBudget(fresh), false);
  // No budget and no spending is an untouched bar, not a full one.
  assert.equal(seasonProgress(fresh), 0);
});

test('spending with no budget reads as fully consumed', () => {
  assert.equal(seasonProgress(season({ purchases: [gift('a', { amount: 1500 })] })), 1);
});

test('amounts stay exact in cents across many gifts', () => {
  const purchases = Array.from({ length: 10 }, (_, i) => gift(`g${i}`, { amount: 7 }));
  const s = season({ budget: 10000, purchases });
  assert.equal(seasonSpentCents(s), 70);
  assert.equal(seasonRemainingCents(s), 9930);
});

test('returns net off the season total and are not counted as gifts', () => {
  const s = season({
    budget: 40000,
    recipients: [person('mom')],
    purchases: [
      gift('a', { recipientID: 'mom', amount: 9000 }),
      gift('b', { recipientID: 'mom', amount: 9000, isReturn: true }),
    ],
  });
  assert.equal(seasonSpentCents(s), 0);
  assert.equal(seasonRemainingCents(s), 40000);
  assert.equal(giftCount(s), 1);
  assert.equal(returnCount(s), 1);
  // Both rows survive: deleting the gift would lose what was bought, and
  // editing it down would lose that money moved twice.
  assert.equal(s.purchases.length, 2);
});

test('a bucket holding only a return is still visible', () => {
  const s = season({ purchases: [gift('r', { amount: 2500, isReturn: true })] });
  assert.equal(seasonSpentCents(s), -2500);
  assert.equal(unassignedRowCount(s), 1);
  assert.equal(recipientTally(s, null).rows, 1);
});

test('per-person tallies add up to the season total', () => {
  const s = season({
    recipients: [person('mom'), person('dad')],
    purchases: [
      gift('a', { recipientID: 'mom', amount: 4000 }),
      gift('b', { recipientID: 'mom', amount: 1800 }),
      gift('c', { recipientID: 'dad', amount: 1200 }),
      gift('d', { amount: 900 }),
    ],
  });
  assert.equal(recipientTally(s, 'mom').spentCents, 5800);
  assert.equal(recipientTally(s, 'dad').spentCents, 1200);
  assert.equal(recipientTally(s, null).spentCents, 900);
  const parts = s.recipients.reduce((sum, p) => sum + recipientTally(s, p.id).spentCents, 0)
    + recipientTally(s, null).spentCents;
  assert.equal(parts, seasonSpentCents(s));
});

test('a target of nothing is not the same as no target', () => {
  const none = season({ recipients: [person('mom')] });
  assert.equal(hasPerPersonTargets(none), false);
  assert.equal(recipientProgress(none, none.recipients[0]), null);

  const zero = season({ recipients: [person('neighbour', { plannedAmount: 0 })] });
  assert.equal(plannedTotalCents(zero), 0);
  // The discriminator: plannedTotal is zero for both shapes.
  assert.equal(hasPerPersonTargets(zero), true);
  assert.equal(recipientProgress(zero, zero.recipients[0]), 0);
});

test('the planning figure can never out-claim what is available', () => {
  let s = season({
    budget: 50000,
    recipients: [person('mom', { plannedAmount: 15000 }), person('dad', { plannedAmount: 10000 }), person('sam', { plannedAmount: 5000 })],
  });
  assert.equal(remainingTargetsCents(s), 30000);
  assert.equal(unreservedCents(s), 20000);

  // Spending into a target does not free money; unplanned spending does.
  s = season({ ...s, purchases: [gift('a', { recipientID: 'mom', amount: 10000 })] });
  assert.equal(unreservedCents(s), 20000);
  s = season({ ...s, purchases: [...s.purchases, gift('b', { amount: 6000 })] });
  assert.equal(unreservedCents(s), 14000);

  // Walk it well past the budget; the invariant has to hold throughout.
  for (const amount of [20000, 24000, 10000]) {
    s = season({ ...s, purchases: [...s.purchases, gift(`x${amount}`, { recipientID: 'mom', amount })] });
    assert.ok(unreservedCents(s) <= seasonRemainingCents(s));
  }
  assert.ok(seasonRemainingCents(s) < 0);
  assert.ok(unreservedCents(s) <= seasonRemainingCents(s));
});

test('returning more than was spent cannot reserve more than the target', () => {
  const s = season({
    budget: 50000,
    recipients: [person('mom', { plannedAmount: 10000 })],
    purchases: [gift('r', { recipientID: 'mom', amount: 30000, isReturn: true })],
  });
  assert.equal(recipientTally(s, 'mom').spentCents, -30000);
  assert.equal(remainingTargetsCents(s), 10000);
  assert.ok(unreservedCents(s) <= seasonRemainingCents(s));
});

test('gifts list newest first with a stable tie-break', () => {
  const s = season({ purchases: [
    gift('old', { date: '2026-11-01T12:00:00.000Z' }),
    gift('new', { date: '2026-12-05T12:00:00.000Z' }),
    gift('mid', { date: '2026-11-20T12:00:00.000Z' }),
  ] });
  assert.deepEqual(purchasesNewestFirst(s).map(r => r.id), ['new', 'mid', 'old']);
  assert.deepEqual(purchasesFor(s, null).map(r => r.id), ['new', 'mid', 'old']);
});

test('normalization renames rather than deletes, and re-homes orphans', () => {
  const s = normalizeSeason({
    id: 'x', label: '   ', budget: -500, startedAt: '2026-11-01T12:00:00.000Z',
    recipients: [{ id: 'p1', name: '  ', emoji: '' }],
    purchases: [
      { id: 'g1', recipientID: 'ghost', name: '  ', amount: 1000, date: '2026-11-02T12:00:00.000Z' },
    ],
  }, at('2026-11-06T12:00:00Z'));

  assert.equal(s.label, 'Holiday 2026');
  assert.equal(s.budget, 0);
  assert.equal(s.recipients[0].name, 'Someone');
  assert.equal(s.recipients[0].emoji, '🎁');
  assert.equal(s.purchases[0].name, 'Gift');
  // Still counted, and reachable from the unassigned bucket.
  assert.equal(s.purchases[0].recipientID, null);
  assert.equal(seasonSpentCents(s), 1000);
});

test('a row sharing an id is re-identified when it differs and dropped when identical', () => {
  const differing = normalizeSeason({
    startedAt: '2026-11-01T12:00:00.000Z',
    recipients: [person('same', { name: 'Mom' }), person('same', { name: 'Dad', emoji: '🎄' })],
  }, at('2026-11-06T12:00:00Z'));
  // Dropping the second would delete a real person.
  assert.equal(differing.recipients.length, 2);
  assert.deepEqual(differing.recipients.map(p => p.name).sort(), ['Dad', 'Mom']);
  assert.equal(new Set(differing.recipients.map(p => p.id)).size, 2);

  const identical = normalizeSeason({
    startedAt: '2026-11-01T12:00:00.000Z',
    purchases: [gift('dupe', { amount: 4000 }), gift('dupe', { amount: 4000 })],
  }, at('2026-11-06T12:00:00Z'));
  // An identical repeat is a merge artifact; collapsing it loses nothing.
  assert.equal(identical.purchases.length, 1);
  assert.equal(seasonSpentCents(identical), 4000);
});

test('a season with no usable start date is not named "Holiday 1"', () => {
  const s = normalizeSeason({ label: '', startedAt: 'nonsense' }, at('2026-11-06T12:00:00Z'));
  assert.equal(s.label, 'Holiday 2026');
});

test('starting a new season archives the old one and keeps the name asked for', () => {
  const current = season({
    budget: 60000,
    recipients: [person('mom', { plannedAmount: 20000 })],
    purchases: [gift('a', { recipientID: 'mom', amount: 4000 })],
  });
  const next = startNewSeason({ season: current, history: [], carryRecipients: true, now: at('2027-11-02T12:00:00Z') });

  assert.equal(next.history.length, 1);
  assert.equal(next.history[0].label, 'Holiday 2026');
  assert.equal(seasonSpentCents(next.history[0]), 4000);
  assert.ok(next.history[0].closedAt);

  assert.equal(next.season.label, 'Holiday 2027');
  assert.equal(next.season.budget, 60000);
  assert.equal(seasonSpentCents(next.season), 0);
  assert.deepEqual(next.season.recipients.map(p => p.name), ['mom']);
  assert.equal(next.season.recipients[0].plannedAmount, 20000);
});

test('a new season can start without carrying the people', () => {
  const current = season({ recipients: [person('mom')], purchases: [gift('a')] });
  const next = startNewSeason({ season: current, history: [], carryRecipients: false, now: at('2027-11-02T12:00:00Z') });
  assert.equal(next.season.recipients.length, 0);
  assert.equal(next.history[0].recipients.length, 1);
});

test('an untouched season is not archived', () => {
  const next = startNewSeason({ season: emptySeason(at('2026-11-06T12:00:00Z')), history: [], carryRecipients: false, now: at('2026-11-06T12:00:00Z') });
  assert.equal(next.history.length, 0);
});

test('seasons closed in the same year stay distinguishable in history', () => {
  const now = at('2026-12-01T12:00:00Z');
  let s = season({ purchases: [gift('a')] });
  let first = startNewSeason({ season: s, history: [], carryRecipients: false, now });
  assert.deepEqual(first.history.map(h => h.label), ['Holiday 2026']);
  // The live season keeps the plain default the sheet promises.
  assert.equal(first.season.label, 'Holiday 2026');

  const second = startNewSeason({
    season: { ...first.season, purchases: [gift('b')] },
    history: first.history, carryRecipients: false, now,
  });
  assert.equal(second.season.label, 'Holiday 2026');
  assert.deepEqual(second.history.map(h => h.label), ['Holiday 2026 (2)', 'Holiday 2026']);
  assert.equal(new Set(second.history.map(h => h.label)).size, second.history.length);
});

test('a custom season name is kept verbatim', () => {
  const next = startNewSeason({
    season: season({ purchases: [gift('a')] }), history: [],
    label: '  Christmas with the Kanes  ', carryRecipients: false, now: at('2026-12-01T12:00:00Z'),
  });
  assert.equal(next.season.label, 'Christmas with the Kanes');
});

test('history is capped and keeps the most recent', () => {
  let current = season({ purchases: [gift('seed')] });
  let history = [];
  for (let year = 2020; year <= 2020 + HISTORY_LIMIT + 1; year++) {
    const out = startNewSeason({
      season: { ...current, purchases: [gift(`g${year}`)] },
      history, label: `Season ${year}`, carryRecipients: false, now: at(`${year}-12-01T12:00:00Z`),
    });
    current = out.season;
    history = out.history;
  }
  assert.equal(history.length, HISTORY_LIMIT);
  assert.equal(history[0].label, `Season ${2020 + HISTORY_LIMIT}`);
  assert.ok(!history.some(h => h.label === 'Holiday 2026'));
});

test('a season closed under a backwards clock is not evicted on the spot', () => {
  let history = [];
  let current = season({ purchases: [gift('seed')] });
  // Fill history to the cap with seasons closed in the future.
  for (let i = 0; i < HISTORY_LIMIT; i++) {
    const out = startNewSeason({
      season: { ...current, purchases: [gift(`f${i}`)] },
      history, label: `Future ${i}`, carryRecipients: false, now: at(`${2030 + i}-12-01T12:00:00Z`),
    });
    current = out.season;
    history = out.history;
  }
  assert.equal(history.length, HISTORY_LIMIT);

  // Clock goes back, as on a restored device before it syncs.
  const out = startNewSeason({
    season: { ...current, label: 'The one that matters', purchases: [gift('big', { amount: 80000 })] },
    history, carryRecipients: false, now: at('2026-12-20T12:00:00Z'),
  });
  assert.equal(out.history[0].label, 'The one that matters');
  assert.equal(seasonSpentCents(out.history[0]), 80000);
  assert.equal(out.history.length, HISTORY_LIMIT);
});

test('display order and lookups are deterministic', () => {
  const s = season({ recipients: [
    person('b', { name: 'Bea', createdAt: '2026-11-03T12:00:00.000Z' }),
    person('a', { name: 'Al', createdAt: '2026-11-01T12:00:00.000Z' }),
  ] });
  assert.deepEqual(recipientsInDisplayOrder(s).map(p => p.name), ['Al', 'Bea']);
  assert.equal(findRecipient(s, 'a').name, 'Al');
  assert.equal(findRecipient(s, null), null);
  assert.equal(findRecipient(s, 'missing'), null);
});

test('uniqueArchivedLabel only disambiguates on a real collision', () => {
  assert.equal(uniqueArchivedLabel([{ label: 'A' }], 'B'), 'B');
  assert.equal(uniqueArchivedLabel([{ label: 'A' }], 'A'), 'A (2)');
  assert.equal(uniqueArchivedLabel([{ label: 'A' }, { label: 'A (2)' }], 'A'), 'A (3)');
});

test('normalizeHistory drops duplicates and sorts by close time', () => {
  const history = normalizeHistory([
    { id: 's1', label: 'Older', startedAt: '2025-01-01T00:00:00.000Z', closedAt: '2025-12-01T00:00:00.000Z' },
    { id: 's2', label: 'Newer', startedAt: '2026-01-01T00:00:00.000Z', closedAt: '2026-12-01T00:00:00.000Z' },
    { id: 's1', label: 'Older again', startedAt: '2025-01-01T00:00:00.000Z', closedAt: '2025-12-01T00:00:00.000Z' },
  ], at('2026-11-06T12:00:00Z'));
  assert.deepEqual(history.map(h => h.label), ['Newer', 'Older']);
});

test('seasonIsEmpty only ignores a season with nothing in it', () => {
  assert.equal(seasonIsEmpty(season()), true);
  assert.equal(seasonIsEmpty(season({ budget: 100 })), false);
  assert.equal(seasonIsEmpty(season({ recipients: [person('a')] })), false);
  assert.equal(seasonIsEmpty(season({ purchases: [gift('a')] })), false);
});

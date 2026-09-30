import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeSnapshot, exportBackup } from './backup.mjs';

const tx = (overrides = {}) => ({ id: 'legacy-entry', name: 'Milk', amount: 4.29, emoji: '🛒', date: '2026-09-21', type: 'grocery', ...overrides });
const fixture = () => ({
  personalBudget: 200, groceryBudget: 400, personalCarryover: -12.23, groceryCarryover: 31.42,
  transactions: [tx(), tx({ id: 'refund', amount: 2.11, isRefund: true, note: 'Returned' })],
  recurringRules: [{ ...tx({ id: 'rule', amount: 19.99 }), frequency: 'monthly', nextOccurrenceDate: '2026-10-31', anchorDay: 31 }],
  currentMonth: '2026-09', updatedAt: '2026-09-29T17:00:00.123Z',
  personalCategories: [{ emoji: '🍕', label: 'Dining' }],
  monthHistory: [{ monthKey: '2026-08', personalBudget: 175, groceryBudget: 350, personalCarryover: 0, groceryCarryover: -3.45,
    transactions: [tx({ date: '2026-08-20' })], archivedAt: '2026-09-01T04:00:00Z' }],
});

test('legacy dollars migrate to iOS cents across transactions, recurring rules, and history', () => {
  const original = fixture();
  const portable = exportBackup(original);
  assert.equal(portable.schemaVersion, 2);
  assert.equal(portable.groceryBudget, 40000);
  assert.equal(portable.personalCarryover, -1223);
  assert.equal(portable.transactions[0].amount, 429);
  assert.equal(portable.recurringRules[0].amount, 1999);
  assert.equal(portable.monthHistory[0].groceryCarryover, -345);
  assert.equal(portable.transactions[0].tab, 'grocery');
  assert.equal(portable.transactions[0].type, undefined);
  for (const row of [...portable.transactions, ...portable.recurringRules, ...portable.personalCategories]) {
    assert.match(row.id, /^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i);
  }
  assert.match(portable.transactions[0].date, /T\d{2}:00:00Z$/);
  assert.deepEqual(exportBackup(original), portable, 'stable identities on repeat export');
  const restored = normalizeSnapshot(JSON.parse(JSON.stringify(portable)), { strict: true });
  assert.deepEqual(restored.warnings, []);
  assert.equal(restored.snapshot.transactions[0].date, original.transactions[0].date);
  assert.equal(restored.snapshot.transactions[0].amount, 4.29);
  assert.equal(restored.snapshot.transactions[1].isRefund, true);
  assert.equal(restored.snapshot.recurringRules[0].nextOccurrenceDate, '2026-10-31');
  assert.equal(restored.snapshot.recurringRules[0].anchorDay, 31);
  assert.equal(restored.snapshot.monthHistory[0].transactions[0].date, '2026-08-20');
  assert.deepEqual(exportBackup(restored.snapshot), portable);
});

test('schema version determines whether integers mean cents or dollars', () => {
  assert.equal(normalizeSnapshot({ groceryBudget: 400 }).snapshot.groceryBudget, 400);
  assert.equal(normalizeSnapshot({ schemaVersion: 2, groceryBudget: 400 }).snapshot.groceryBudget, 4);
  assert.throws(() => normalizeSnapshot({ schemaVersion: 3 }), /version/);
  assert.throws(() => normalizeSnapshot({ schemaVersion: '2' }), /version/);
});

test('missing legacy fields get defaults without inventing freshness', () => {
  const { snapshot, warnings } = normalizeSnapshot({ transactions: [tx({ id: undefined })] }, { strict: true });
  assert.equal(snapshot.personalBudget, 200);
  assert.equal(snapshot.groceryBudget, 400);
  assert.equal(snapshot.updatedAt, '1970-01-01T00:00:00Z');
  assert.equal(snapshot.transactions[0].note, '');
  assert.equal(snapshot.transactions[0].isRefund, false);
  assert.equal(snapshot.personalCategories.length, 5);
  assert.deepEqual(warnings, []);
});

test('damaged rows are salvaged independently; strict import rejects any loss', () => {
  const input = fixture();
  input.transactions.push(tx({ id: 'invalid', date: '2026-02-30' }));
  input.monthHistory[0].transactions.push(tx({ id: 'bad-money', amount: '20' }));
  input.recurringRules.push({ frequency: 'sometimes' });
  input.monthHistory.push({ monthKey: '2026-13' });
  const result = normalizeSnapshot(input);
  assert.equal(result.snapshot.transactions.length, 2);
  assert.equal(result.snapshot.monthHistory.length, 1);
  assert.equal(result.snapshot.monthHistory[0].transactions.length, 1);
  assert.equal(result.snapshot.recurringRules.length, 1);
  assert.equal(result.warnings.length, 4);
  assert.throws(() => normalizeSnapshot(input, { strict: true }));
});

test('strict validation rejects corrupt amounts, flags, dates, lists, categories, and duplicate identities', () => {
  for (const amount of [NaN, Infinity, -1, 1e13, '2', 2.005]) {
    assert.throws(() => normalizeSnapshot({ transactions: [tx({ amount })] }, { strict: true }), /amount/);
  }
  assert.throws(() => normalizeSnapshot({ schemaVersion: 2, transactions: [tx({ amount: 1.1 })] }, { strict: true }), /fractional/);
  for (const date of ['2025-02-29', '2026-04-31', '2026-01-01T24:00:00Z', 'yesterday']) {
    assert.throws(() => normalizeSnapshot({ transactions: [tx({ date })] }, { strict: true }));
  }
  for (const input of [
    { transactions: {} }, { transactions: [tx({ isRefund: 'false' })] },
    { transactions: [tx({ type: 'unknown' })] }, { transactions: [tx(), tx()] },
    { currentMonth: '2026-13' }, { personalCategories: [{ emoji: '', label: 'Food' }] },
    { monthHistory: [{ monthKey: '2026-08' }, { monthKey: '2026-08' }] },
  ]) assert.throws(() => normalizeSnapshot(input, { strict: true }));
});

test('strict imports reject unrelated and empty objects; a legitimate empty ledger is supported', () => {
  for (const input of [{}, [], null, { hello: 'world' }, { schemaVersion: 2 }, { updatedAt: '2026-01-01T00:00:00Z' }]) {
    assert.throws(() => normalizeSnapshot(input, { strict: true }));
  }
  assert.equal(normalizeSnapshot({ transactions: [] }, { strict: true }).snapshot.transactions.length, 0);
});

test('valid leap days and exact boundary amounts survive without clamping', () => {
  const result = normalizeSnapshot({ transactions: [tx({ date: '2024-02-29', amount: 1e12 })] }, { strict: true });
  assert.equal(result.snapshot.transactions[0].amount, 1e12);
  assert.equal(result.snapshot.transactions[0].date, '2024-02-29');
});

test('zero recurring rules are reported and cannot be imported silently', () => {
  const input = fixture();
  input.recurringRules[0].amount = 0;
  assert.throws(() => normalizeSnapshot(input, { strict: true }), /recurring amount must be positive/);
  const { snapshot, warnings } = normalizeSnapshot(input);
  assert.equal(snapshot.recurringRules.length, 0);
  assert.equal(warnings.length, 1);
});

test('normalization leaves the original object intact and retains every archived month', () => {
  const input = fixture();
  input.monthHistory = Array.from({ length: 24 }, (_, i) => ({ ...input.monthHistory[0], monthKey: `${2024 + Math.floor(i / 12)}-${String(i % 12 + 1).padStart(2, '0')}` }));
  const before = JSON.stringify(input);
  const { snapshot } = normalizeSnapshot(input, { strict: true });
  assert.equal(snapshot.monthHistory.length, 24);
  assert.equal(JSON.stringify(input), before);
  assert.equal(snapshot.updatedAt, '2026-09-29T17:00:00.123Z', 'cache freshness retains millisecond precision');
});

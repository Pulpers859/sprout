import test from 'node:test';
import assert from 'node:assert/strict';
import { validDate, monthInfo, nextOccurrence, processRecurring, resetLedger, keepLedger } from './ledger.mjs';

const tx = (id, date, amount = 10, type = 'personal') => ({ id, date, amount, type, name: id, isRefund: false });
const state = (extra = {}) => ({ currentMonth: '2026-09', personalBudget: 200, groceryBudget: 400,
  personalCarryover: 0, groceryCarryover: 0, transactions: [], monthHistory: [], recurringRules: [], ...extra });
const rule = (extra = {}) => ({ id: 'rent', name: 'Rent', type: 'personal', amount: 25,
  frequency: 'monthly', nextOccurrenceDate: '2026-09-15', anchorDay: 15, ...extra });

test('strict dates reject overflow while accepting leap days', () => {
  assert.equal(validDate('2024-02-29'), true);
  for (const d of ['2026-02-29', '2026-04-31', '2026-9-01', '0000-01-01', '2026-13-01', '']) assert.equal(validDate(d), false, d);
});
test('stored month controls days left and pace across boundary and clock rollback', () => {
  assert.deepEqual(monthInfo('2026-09', '2026-10-01'), { days: 30, day: 30, daysLeft: 1, pace: 1 });
  assert.deepEqual(monthInfo('2026-10', '2026-09-30'), { days: 31, day: 1, daysLeft: 31, pace: 1 / 31 });
  assert.equal(monthInfo('2024-02', '2024-02-28').daysLeft, 2);
});
test('monthly and yearly schedules retain original day through short months', () => {
  const feb = nextOccurrence('2026-01-31', 'monthly', 31);
  assert.equal(feb, '2026-02-28');
  assert.equal(nextOccurrence(feb, 'monthly', 31), '2026-03-31');
  assert.equal(nextOccurrence('2024-02-29', 'yearly', 29), '2025-02-28');
  assert.equal(nextOccurrence('2027-02-28', 'yearly', 29), '2028-02-29');
  assert.equal(nextOccurrence('2026-03-07', 'weekly'), '2026-03-14');
  assert.equal(nextOccurrence('2026-01-01', 'unknown'), null);
});
test('recurring processing is idempotent, including a restored stale cursor', () => {
  const s = state({ recurringRules: [rule()] });
  assert.equal(processRecurring(s, '2026-10-16'), true);
  assert.deepEqual(s.transactions.map(t => t.date), ['2026-09-15', '2026-10-15']);
  assert.equal(processRecurring(s, '2026-10-16'), false);
  s.recurringRules[0].nextOccurrenceDate = '2026-09-15';
  processRecurring(s, '2026-10-16');
  assert.equal(s.transactions.length, 2);
});
test('bounded catch-up converges instead of posting another batch each activation', () => {
  const s = state({ recurringRules: [rule({ frequency: 'weekly', nextOccurrenceDate: '1900-01-01', anchorDay: 1 })] });
  processRecurring(s, '2026-09-30');
  assert.equal(s.transactions.length, 600);
  assert.ok(s.recurringRules[0].nextOccurrenceDate > '2026-09-30');
  assert.equal(processRecurring(s, '2026-09-30'), false);
  assert.equal(s.transactions.length, 600);
});
test('reset archives closing entries and preserves future entries without reducing carry', () => {
  const s = state({ transactions: [tx('old', '2026-09-20', 50), tx('new', '2026-10-01', 30)] });
  resetLedger(s, '2026-10-02', true);
  assert.equal(s.personalCarryover, 150);
  assert.deepEqual(s.transactions.map(t => t.id), ['new']);
  assert.deepEqual(s.monthHistory[0].transactions.map(t => t.id), ['old']);
});
test('repeated same-month carry closes merge history and never grant the base twice', () => {
  const s = state({ transactions: [tx('first', '2026-09-01', 50)] });
  resetLedger(s, '2026-09-10', true);
  assert.equal(s.personalCarryover, 150);
  s.transactions.push(tx('second', '2026-09-15', 20));
  resetLedger(s, '2026-09-20', true);
  assert.equal(s.personalCarryover, 130);
  assert.deepEqual(s.monthHistory[0].transactions.map(t => t.id).sort(), ['first', 'second']);
  resetLedger(s, '2026-09-21', true);
  assert.equal(s.personalCarryover, 130);
  assert.equal(s.monthHistory[0].transactions.length, 2);
});
test('month walk allocates recurring charges to their periods', () => {
  const s = state({ currentMonth: '2026-07', recurringRules: [rule({ nextOccurrenceDate: '2026-07-15' })] });
  resetLedger(s, '2026-10-16', false);
  assert.deepEqual(s.monthHistory.map(m => m.monthKey), ['2026-09', '2026-08', '2026-07']);
  for (const m of s.monthHistory) assert.equal(m.transactions[0].date.slice(0, 7), m.monthKey);
  assert.deepEqual(s.transactions.map(t => t.date), ['2026-10-15']);
  assert.equal(s.personalCarryover, 0);
});
test('keep advances month without losing live entries and catches up recurring', () => {
  const s = state({ transactions: [tx('old', '2026-09-01')], recurringRules: [rule()] });
  keepLedger(s, '2026-10-01');
  assert.equal(s.currentMonth, '2026-10');
  assert.equal(s.transactions.length, 2);
  assert.equal(s.monthHistory.length, 0);
});
test('backward clock or invalid stored month preserves ledger and carryover', () => {
  for (const currentMonth of ['2026-11', 'invalid']) {
    const s = state({ currentMonth, personalCarryover: 50, transactions: [tx('keep', '2026-11-01')] });
    resetLedger(s, '2026-10-01', false);
    assert.equal(s.transactions.length, 1);
    assert.equal(s.personalCarryover, 50);
    assert.equal(s.monthHistory.length, 0);
  }
});
test('placeholder history does not evict older months containing transactions', () => {
  const s = state({ currentMonth: '2025-01', transactions: [tx('saved', '2025-01-10')] });
  resetLedger(s, '2026-09-01', false);
  assert.equal(s.monthHistory.length, 12);
  assert.ok(s.monthHistory.some(m => m.monthKey === '2025-01' && m.transactions[0].id === 'saved'));
});
test('carryover uses exact cents and refunds, and clips negative remaining', () => {
  const s = state({ personalBudget: 0.3, transactions: [tx('a', '2026-09-01', 0.1), tx('b', '2026-09-01', 0.2),
    { ...tx('refund', '2026-09-01', 0.01), isRefund: true }, tx('g', '2026-09-01', 500, 'grocery')] });
  resetLedger(s, '2026-10-01', true);
  assert.equal(s.personalCarryover, 0.01);
  assert.equal(s.groceryCarryover, 0);
});

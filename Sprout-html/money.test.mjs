import test from 'node:test';
import assert from 'node:assert/strict';
import { toCents, fromCents, parseAmount, netSpent, sumMoney, paceStatus, progress } from './money.mjs';

test('cent arithmetic cancels repeated decimal expenses and refunds exactly', () => {
  assert.equal(sumMoney(0.1, 0.2, -0.3), 0);
  const rows = Array.from({ length: 1000 }, () => ({ amount: 0.01 }));
  rows.push({ amount: 10, isRefund: true });
  assert.equal(netSpent(rows), 0);
  assert.equal(sumMoney(200, 25.1, -netSpent([{ amount: 30.2 }])), 194.9);
});

test('cent boundaries round half away from zero and contain nonfinite values', () => {
  assert.equal(toCents(1.005), 101);
  assert.equal(toCents(-1.005), -101);
  assert.equal(toCents(1e-7), 0);
  assert.equal(toCents(Infinity), 0);
  assert.equal(toCents(NaN), 0);
  assert.equal(toCents(1e20), 100_000_000_000_000);
  assert.equal(fromCents(-123), -1.23);
});

test('strict parsing rejects partial numbers, exponent notation, signs and malformed grouping', () => {
  for (const value of ['', ' ', '1e3', '12oops', 'Infinity', 'NaN', '-1', '+1', '1 2', '1,2', '1.2.3', '.', '1,234.5,6']) {
    assert.equal(parseAmount(value), null, value);
  }
  assert.equal(parseAmount('0'), 0);
  assert.equal(parseAmount('0.001'), 0); // caller rejects zero for transactions
  assert.equal(parseAmount('1.005'), 1.01);
  assert.equal(parseAmount('$1,234.50'), 1234.5);
  assert.equal(parseAmount('999999.99'), 999999.99);
  assert.equal(parseAmount('1000000'), null);
  assert.equal(parseAmount('999999.991'), null);
});

test('localized input retains cents including non-Latin digits and Indian grouping', () => {
  assert.equal(parseAmount('1.234,50', 'de-DE'), 1234.5);
  assert.equal(parseAmount('1\u202f234,50', 'fr-FR'), 1234.5);
  assert.equal(parseAmount('١٬٢٣٤٫٥٠', 'ar-EG'), 1234.5);
  assert.equal(parseAmount('1,23,456.78', 'en-IN'), 123456.78);
  assert.equal(parseAmount('12,34.50', 'en-US'), null);
});

test('progress treats zero-budget spending as consumed and clamps refunds/overspend', () => {
  assert.equal(progress(1, 0), 1);
  assert.equal(progress(0, 0), 0);
  assert.equal(progress(-10, 100), 0);
  assert.equal(progress(120, 100), 1);
});

test('pace allows early spending and still detects overspend on final day', () => {
  assert.equal(paceStatus(20, 200, 1, 30), 'on');
  assert.equal(paceStatus(0, 200, 1, 30), 'behind');
  assert.equal(paceStatus(200, 200, 30, 30), 'on');
  assert.equal(paceStatus(210, 200, 30, 30), 'ahead');
  assert.equal(paceStatus(1, 0, 30, 30), 'ahead');
});

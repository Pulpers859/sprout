import { netSpent, sumMoney } from './money.mjs';

const frequencies = new Set(['weekly', 'monthly', 'yearly']);
const pad = n => String(n).padStart(2, '0');
const leap = y => y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
const monthDays = (y, m) => [31, leap(y) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];
const validMonth = key => typeof key === 'string' && /^\d{4}-(0[1-9]|1[0-2])$/.test(key) && Number(key.slice(0, 4)) >= 1;

export function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) || !validMonth(value.slice(0, 7))) return false;
  const [y, m, d] = value.split('-').map(Number);
  return d >= 1 && d <= monthDays(y, m);
}

export function monthInfo(monthKey, today) {
  if (!validDate(today)) throw new RangeError('Invalid reference date');
  const key = validMonth(monthKey) ? monthKey : today.slice(0, 7);
  const [y, m] = key.split('-').map(Number);
  const days = monthDays(y, m);
  const day = key < today.slice(0, 7) ? days : key > today.slice(0, 7) ? 1 : Number(today.slice(8));
  return { days, day, daysLeft: days - day + 1, pace: day / days };
}

function addMonths(date, months, anchorDay) {
  const [y, m, d] = date.split('-').map(Number);
  const total = y * 12 + m - 1 + months;
  const year = Math.floor(total / 12), month = total % 12 + 1;
  if (year > 9999) return null;
  return `${String(year).padStart(4, '0')}-${pad(month)}-${pad(Math.min(anchorDay ?? d, monthDays(year, month)))}`;
}

export function nextOccurrence(date, frequency, anchorDay) {
  if (!validDate(date) || !frequencies.has(frequency)) return null;
  if (anchorDay != null && (!Number.isInteger(anchorDay) || anchorDay < 1 || anchorDay > 31)) return null;
  if (frequency !== 'weekly') return addMonths(date, frequency === 'monthly' ? 1 : 12, anchorDay);
  const value = new Date(`${date}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() + 7);
  const result = value.toISOString().slice(0, 10);
  return validDate(result) ? result : null;
}

/** Posts each due occurrence once. Stable IDs also protect a restored/stale rule cursor. */
export function processRecurring(snapshot, throughDate) {
  if (!validDate(throughDate)) throw new RangeError('Invalid recurring cutoff');
  snapshot.transactions ??= [];
  const ids = new Set(snapshot.transactions.map(t => t.id));
  for (const month of snapshot.monthHistory ?? []) for (const t of month.transactions ?? []) ids.add(t.id);
  let changed = false;
  for (const rule of snapshot.recurringRules ?? []) {
    if (!rule.id || !validDate(rule.nextOccurrenceDate) || !frequencies.has(rule.frequency)
      || !Number.isFinite(rule.amount) || rule.amount <= 0
      || !['personal', 'grocery'].includes(rule.type)) continue;
    const anchor = Number.isInteger(rule.anchorDay) && rule.anchorDay >= 1 && rule.anchorDay <= 31
      ? rule.anchorDay : Number(rule.nextOccurrenceDate.slice(8));
    let remaining = 600;
    while (rule.nextOccurrenceDate <= throughDate && remaining-- > 0) {
      const date = rule.nextOccurrenceDate;
      const next = nextOccurrence(date, rule.frequency, anchor);
      if (!next || next <= date) break;
      const id = `recurring:${rule.id}:${date}`;
      if (!ids.has(id)) {
        snapshot.transactions.push({ id, name: rule.name, amount: rule.amount, note: rule.note || '',
          emoji: rule.emoji || (rule.type === 'grocery' ? '🛒' : '🛍️'), date, type: rule.type,
          isRefund: Boolean(rule.isRefund) });
        ids.add(id);
      }
      rule.anchorDay = anchor;
      rule.nextOccurrenceDate = next;
      changed = true;
    }
    // Converge after the cap; reopening cannot repeatedly post another 600 rows.
    if (rule.nextOccurrenceDate <= throughDate) {
      const next = nextOccurrence(throughDate, rule.frequency, anchor);
      if (next && next > throughDate) { rule.nextOccurrenceDate = next; changed = true; }
    }
  }
  return changed;
}

function trimHistory(history) {
  const ordered = [...history].sort((a, b) => b.monthKey.localeCompare(a.monthKey));
  const nonempty = m => m.transactions.length > 0 || m.personalCarryover > 0 || m.groceryCarryover > 0;
  const kept = ordered.filter(nonempty).slice(0, 12);
  kept.push(...ordered.filter(m => !nonempty(m)).slice(0, 12 - kept.length));
  return kept.sort((a, b) => b.monthKey.localeCompare(a.monthKey));
}

function closeMonth(snapshot, carry, force, today) {
  const closing = [], future = [];
  for (const t of snapshot.transactions ?? []) {
    // Invalid legacy dates are retained in the archive rather than discarded.
    (validDate(t.date) && t.date.slice(0, 7) > snapshot.currentMonth ? future : closing).push(t);
  }
  const history = snapshot.monthHistory ?? [];
  const existing = history.find(m => m.monthKey === snapshot.currentMonth);
  const merged = new Map(closing.map(t => [t.id, { ...t }]));
  for (const t of existing?.transactions ?? []) if (!merged.has(t.id)) merged.set(t.id, { ...t });
  const archived = { monthKey: snapshot.currentMonth, personalBudget: snapshot.personalBudget,
    groceryBudget: snapshot.groceryBudget, personalCarryover: existing?.personalCarryover ?? snapshot.personalCarryover ?? 0,
    groceryCarryover: existing?.groceryCarryover ?? snapshot.groceryCarryover ?? 0,
    transactions: [...merged.values()], archivedAt: `${today}T12:00:00.000Z` };
  if (force || existing || closing.length || archived.personalCarryover > 0 || archived.groceryCarryover > 0) {
    snapshot.monthHistory = trimHistory([...history.filter(m => m.monthKey !== snapshot.currentMonth), archived]);
  }
  for (const type of ['personal', 'grocery']) {
    snapshot[`${type}Carryover`] = carry ? Math.max(0, sumMoney(
      archived[`${type}Budget`], archived[`${type}Carryover`], -netSpent(archived.transactions.filter(t => t.type === type)))) : 0;
  }
  snapshot.transactions = future;
}

export function resetLedger(snapshot, today, carry = false) {
  if (!validDate(today)) throw new RangeError('Invalid reset date');
  const target = today.slice(0, 7);
  // A malformed or future ledger key cannot safely be destructively archived.
  if (!validMonth(snapshot.currentMonth) || snapshot.currentMonth > target) {
    snapshot.currentMonth = target;
    return;
  }
  let closed = false, steps = 240;
  while (snapshot.currentMonth < target && steps-- > 0) {
    const { days } = monthInfo(snapshot.currentMonth, today);
    processRecurring(snapshot, `${snapshot.currentMonth}-${pad(days)}`);
    closeMonth(snapshot, carry, true, today);
    snapshot.currentMonth = addMonths(`${snapshot.currentMonth}-01`, 1, 1).slice(0, 7);
    closed = true;
  }
  if (!closed) closeMonth(snapshot, carry, false, today);
  snapshot.currentMonth = target;
  processRecurring(snapshot, today);
}

export function keepLedger(snapshot, today) {
  if (!validDate(today)) throw new RangeError('Invalid keep date');
  snapshot.currentMonth = today.slice(0, 7);
  processRecurring(snapshot, today);
}

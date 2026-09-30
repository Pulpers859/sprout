// Public values remain dollars for compatibility with existing Firebase/cache data.
// Arithmetic crosses into integer cents and back only at these boundaries.
const MAX_CENTS = 100_000_000_000_000;
const INPUT_MAX = 999999.99;

export function toCents(dollars) {
  if (typeof dollars !== 'number' || !Number.isFinite(dollars)) return 0;
  const magnitude = Math.abs(dollars);
  if (magnitude >= MAX_CENTS / 100) return Math.sign(dollars) * MAX_CENTS;
  // Move the decimal using its shortest decimal representation. This avoids
  // binary multiplication turning 1.005 into 100.49999999999999.
  const [coefficient, exponent = '0'] = magnitude.toString().split('e');
  const cents = Math.round(Number(`${coefficient}e${Number(exponent) + 2}`));
  return Math.sign(dollars) * cents;
}

export function fromCents(cents) {
  if (!Number.isFinite(cents)) return 0;
  return Math.min(MAX_CENTS, Math.max(-MAX_CENTS, Math.trunc(cents))) / 100;
}

export function sumMoney(...dollars) {
  return fromCents(dollars.reduce((total, value) =>
    Math.min(MAX_CENTS, Math.max(-MAX_CENTS, total + toCents(value))), 0));
}

export function netSpent(transactions) {
  return fromCents(transactions.reduce((total, entry) => {
    const cents = toCents(entry.amount) * (entry.isRefund ? -1 : 1);
    return Math.min(MAX_CENTS, Math.max(-MAX_CENTS, total + cents));
  }, 0));
}

/** Fully consumes localized decimal input; returns null for malformed amounts.
 * Zero is valid for budgets. Transaction callers must additionally require > 0.
 * Currency remains USD, matching the web app's persisted dollar amounts.
 */
export function parseAmount(text, locale = 'en-US') {
  if (typeof text !== 'string') return null;
  let formatter;
  try { formatter = new Intl.NumberFormat(locale); } catch { return null; }
  const parts = formatter.formatToParts(123456789.5);
  const decimal = parts.find(part => part.type === 'decimal')?.value || '.';
  const group = parts.find(part => part.type === 'group')?.value || ',';
  let candidate = text.trim().replace(/USD|\$/g, '').trim();
  const digitFormatter = new Intl.NumberFormat(locale, { useGrouping: false });
  for (let digit = 0; digit <= 9; digit++) {
    candidate = candidate.split(digitFormatter.format(digit)).join(String(digit));
  }
  if (/\s/u.test(group)) candidate = candidate.replace(/[ \u00a0\u202f]/g, group);
  const sections = candidate.split(decimal);
  if (sections.length > 2) return null;
  let whole = sections[0];
  const fraction = sections[1];
  if (fraction !== undefined && !/^\d*$/.test(fraction)) return null;
  if (whole.includes(group)) {
    // Validate grouping rather than silently accepting a mistyped "1,2" as 12.
    const groups = whole.split(group);
    const integerGroups = parts.filter(part => part.type === 'integer').map(part => part.value.length);
    const lastSize = integerGroups.at(-1);
    const interiorSize = integerGroups.length > 2 ? integerGroups.at(-2) : lastSize;
    if (!groups.every(part => /^\d+$/.test(part)) ||
        groups.at(-1).length !== lastSize ||
        groups[0].length < 1 || groups[0].length > interiorSize ||
        groups.slice(1, -1).some(part => part.length !== interiorSize)) return null;
    whole = groups.join('');
  }
  if (!/^\d*$/.test(whole) || !(whole + (fraction || '')).length) return null;
  const value = Number(`${whole || '0'}.${fraction || '0'}`);
  if (!Number.isFinite(value) || value > INPUT_MAX) return null;
  return fromCents(toCents(value));
}

export function progress(spent, budget) {
  const spentCents = Math.max(0, toCents(spent));
  const budgetCents = toCents(budget);
  return budgetCents > 0 ? Math.min(spentCents / budgetCents, 1) : spentCents > 0 ? 1 : 0;
}

export function paceStatus(spent, budget, day, days) {
  const pace = days > 0 ? Math.min(Math.max(day / days, 0), 1) : 0;
  const spentCents = Math.max(0, toCents(spent));
  const budgetCents = toCents(budget);
  const actual = budgetCents > 0 ? spentCents / budgetCents : spentCents > 0 ? Infinity : 0;
  if (actual > pace + 0.02 + (1 - pace) * 0.1) return 'ahead';
  if (actual < pace - 0.02) return 'behind';
  return 'on';
}

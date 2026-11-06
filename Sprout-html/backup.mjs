// The web cache uses dollars (v1); portable backups use iOS integer cents (v2).
import { normalizeSeason, normalizeHistory } from './holiday.mjs';

const MAX_CENTS = 100_000_000_000_000;
const DEFAULT_CATEGORIES = [
  ['🛍️', 'Shopping'], ['🎁', 'Gifts'], ['💄', 'Beauty'], ['🍕', 'Dining'], ['🚗', 'Gas'],
];
const MONEY_KEYS = ['groceryBudget', 'personalBudget', 'groceryCarryover', 'personalCarryover'];
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const localDay = date => `${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
const iso = date => date.toISOString().replace(/\.\d{3}Z$/, 'Z');
function validDay(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T12:00:00Z`);
  return Number(value.slice(0, 4)) > 0 && Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}
function month(value) {
  if (typeof value !== 'string' || !validDay(`${value}-01`)) throw new Error('invalid month');
  return value;
}
function timestamp(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)
      || !validDay(value.slice(0, 10)) || Number(value.slice(11, 13)) > 23 || Number(value.slice(14, 16)) > 59
      || Number(value.slice(17, 19)) > 59 || !Number.isFinite(Date.parse(value))) throw new Error('invalid timestamp');
  return new Date(value).toISOString();
}
function day(value) {
  if (validDay(value)) return value;
  return localDay(new Date(timestamp(value)));
}
function string(value, fallback) {
  if (value === undefined && fallback !== undefined) return fallback;
  if (typeof value !== 'string') throw new Error('expected text');
  return value;
}
// Stable UUIDs make repeat exports retain legacy identities. Existing UUIDs pass through.
function uuid(value) {
  const text = String(value);
  if (/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(text)) return text;
  let hex = '';
  for (let lane = 0; lane < 4; lane++) {
    let hash = (2166136261 ^ Math.imul(lane + 1, 0x9e3779b9)) >>> 0;
    for (let i = 0; i < text.length; i++) hash = Math.imul(hash ^ text.charCodeAt(i), 16777619) >>> 0;
    hex += hash.toString(16).padStart(8, '0');
  }
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20)}`;
}

// Holiday amounts are integer CENTS, at every version, and are never rescaled
// by `money()` the way monthly amounts are. See the header of holiday.mjs: the
// data has only ever been written by iOS in cents, and web snapshots already on
// disk carry it that way under `schemaVersion: 1` because the previous build
// passed it through uninterpreted. Scaling it by version would read every
// stored $40 gift as $4,000 and write it back that way.
function holidayCents(value, path) {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`${path}: invalid amount`);
  if (!Number.isInteger(value)) throw new Error(`${path}: amount has fractional cents`);
  if (Math.abs(value) > MAX_CENTS) throw new Error(`${path}: amount outside supported range`);
  return value;
}

/** Shape check only; `normalizeSeason` does the renaming, re-homing and
 * de-duplication, exactly as it does for the live ledger. Throwing here lets a
 * strict import reject a damaged holiday section rather than partially replace
 * the user's data, which is how this importer already treats every other row. */
function checkSeasonShape(value, path) {
  if (!object(value)) throw new Error(`${path}: expected an object`);
  holidayCents(value.budget ?? 0, `${path}.budget`);
  for (const key of ['recipients', 'purchases']) {
    const rows = value[key];
    if (rows === undefined || rows === null) continue;
    if (!Array.isArray(rows)) throw new Error(`${path}.${key}: expected a list`);
    rows.forEach((row, index) => {
      if (!object(row)) throw new Error(`${path}.${key}[${index}]: expected an object`);
      if (key === 'purchases') holidayCents(row.amount, `${path}.${key}[${index}].amount`);
      if (key === 'recipients' && row.plannedAmount != null) {
        holidayCents(row.plannedAmount, `${path}.${key}[${index}].plannedAmount`);
      }
    });
  }
  return value;
}

/**
 * The payload's schema version, matching `BudgetStore.schemaVersion(in:)`.
 *
 * A quoted `"2"` from a hand-edited or third-party file used to read as "no
 * version, so v1", which multiplied every monthly amount by 100 and wrote the
 * inflated figures back.
 *
 * iOS additionally infers v2 from the presence of holiday data, and that rule
 * deliberately is NOT ported. It is safe there because iOS has never written
 * anything but v2, so "no version" can only mean a foreign file. Here v1 is the
 * native format: the web cache and every legacy Firebase document are
 * version-less dollars, so inferring v2 from holiday data would read a $200
 * monthly budget as $2.00. Holiday amounts are cents at every version anyway
 * (see holiday.mjs), so they are not at risk either way.
 */
export function schemaVersionOf(input) {
  const raw = input?.schemaVersion;
  if (Number.isInteger(raw)) return raw;
  if (typeof raw === 'string' && /^\d+$/.test(raw.trim())) return Number(raw.trim());
  if (raw != null) return NaN;
  return 1;
}

/** Whether the payload carries a holiday section at all. The normalized
 * snapshot cannot answer this: an absent section becomes an empty season,
 * which looks identical to a real season nobody has shopped for yet. */
export function containsHolidayData(input) {
  return input?.holidaySeason != null || input?.holidaySeasonHistory != null;
}

export function normalizeSnapshot(input, { strict = false } = {}) {
  if (!object(input)) throw new Error('This file is not a Sprout backup.');
  const version = schemaVersionOf(input);
  if (!Number.isInteger(version) || version < 0 || version > 2) throw new Error('Unsupported Sprout backup version.');
  // Holiday keys count as a signature, as they do on iOS: a file carrying only
  // holiday data is still a Sprout export, and rejecting it here while iOS
  // accepts it is the kind of asymmetry that costs someone their gifts.
  if (strict && !['groceryBudget', 'personalBudget', 'transactions', 'recurringRules', 'monthHistory', 'currentMonth', 'personalCategories',
    'holidaySeason', 'holidaySeasonHistory']
    .some(key => Object.hasOwn(input, key) && input[key] != null)) throw new Error('This file is not a Sprout backup.');
  const warnings = [];
  const recover = (path, fn, fallback) => {
    try { return fn(); } catch (error) {
      const message = `${path}: ${error.message}`;
      if (strict) throw new Error(message);
      warnings.push(message);
      return fallback;
    }
  };
  function money(value, fallback, nonnegative = false) {
    if (value === undefined || value === null) {
      if (fallback !== undefined) return fallback;
      throw new Error('missing amount');
    }
    if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('invalid amount');
    if (version === 2 && !Number.isInteger(value)) throw new Error('amount has fractional cents');
    const scaled = version === 2 ? value : value * 100;
    const cents = Math.round(scaled);
    if (Math.abs(scaled - cents) > Math.max(1e-7, Math.abs(scaled) * Number.EPSILON * 2)) throw new Error('amount has fractional cents');
    if (Math.abs(cents) > MAX_CENTS || (nonnegative && cents < 0)) throw new Error('amount outside supported range');
    return cents / 100;
  }
  function list(value, path, parse) {
    if (value === undefined || value === null) return [];
    return recover(path, () => {
      if (!Array.isArray(value)) throw new Error('expected a list');
      const ids = new Set();
      return value.flatMap((row, index) => {
        const parsed = recover(`${path}[${index}]`, () => {
          if (!object(row)) throw new Error('expected an object');
          const result = parse(row, `${path}[${index}]`);
          const id = result.id ?? result.monthKey;
          if (ids.has(id)) throw new Error('duplicate identity');
          ids.add(id);
          return result;
        }, null);
        return parsed ? [parsed] : [];
      });
    }, []);
  }
  function identity(row, path) {
    if (row.id === undefined) return uuid(path);
    if (!['string', 'number'].includes(typeof row.id) || String(row.id).trim() === '' || (typeof row.id === 'number' && !Number.isSafeInteger(row.id))) throw new Error('invalid identity');
    const value = String(row.id);
    return /^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(value) ? value.toLowerCase() : value;
  }
  function entry(row, path, recurring = false) {
    const type = row.tab ?? row.type ?? 'personal';
    if (!['personal', 'grocery'].includes(type)) throw new Error('invalid budget type');
    if (row.tab !== undefined && row.type !== undefined && row.tab !== row.type) throw new Error('conflicting budget types');
    if (row.isRefund !== undefined && typeof row.isRefund !== 'boolean') throw new Error('invalid refund flag');
    const result = {
      id: identity(row, path), name: string(row.name), amount: money(row.amount, undefined, true),
      note: string(row.note, ''), emoji: string(row.emoji, type === 'grocery' ? '🛒' : '🛍️'), type, isRefund: row.isRefund ?? false,
    };
    if (!recurring) return { ...result, date: day(row.date) };
    if (result.amount <= 0) throw new Error('recurring amount must be positive');
    if (!['weekly', 'monthly', 'yearly'].includes(row.frequency)) throw new Error('invalid recurrence frequency');
    const nextOccurrenceDate = day(row.nextOccurrenceDate);
    const anchorDay = row.anchorDay ?? Number(nextOccurrenceDate.slice(-2));
    if (!Number.isInteger(anchorDay) || anchorDay < 1 || anchorDay > 31) throw new Error('invalid recurrence anchor');
    return { ...result, frequency: row.frequency, nextOccurrenceDate, anchorDay };
  }
  function budgets(row, path, archived = false) {
    return Object.fromEntries(MONEY_KEYS.map(key => [key, recover(`${path}.${key}`, () => money(row[key], key === 'groceryBudget' ? (archived ? 0 : 400) : key === 'personalBudget' ? (archived ? 0 : 200) : 0, key.endsWith('Budget')), 0)]));
  }
  const defaultCategories = DEFAULT_CATEGORIES.map(([emoji, label], index) => ({ id: uuid(`default-category-${index}`), emoji, label }));
  const categories = input.personalCategories == null ? defaultCategories : list(input.personalCategories, 'personalCategories', (row, path) => {
    const emoji = string(row.emoji).trim();
    const label = string(row.label).trim();
    if (!emoji || !label) throw new Error('empty category label or emoji');
    return { id: identity(row, path), emoji, label };
  });
  if (input.personalCategories != null && categories.length === 0) recover('personalCategories', () => { throw new Error('no usable categories'); }, null);
  const snapshot = {
    schemaVersion: 1,
    ...budgets(input, 'snapshot'),
    transactions: list(input.transactions, 'transactions', entry),
    recurringRules: list(input.recurringRules, 'recurringRules', (row, path) => entry(row, path, true)),
    // Preserve all imported archives. The active ledger applies its history cap
    // when archiving; decoding must never silently discard backup contents.
    monthHistory: list(input.monthHistory, 'monthHistory', (row, path) => ({
      monthKey: month(row.monthKey), ...budgets(row, path, true),
      transactions: list(row.transactions, `${path}.transactions`, entry),
      archivedAt: row.archivedAt == null ? '1970-01-01T00:00:00Z' : timestamp(row.archivedAt),
    })).sort((a, b) => b.monthKey.localeCompare(a.monthKey)),
    currentMonth: recover('currentMonth', () => input.currentMonth == null ? localDay(new Date()).slice(0, 7) : month(input.currentMonth), localDay(new Date()).slice(0, 7)),
    personalCategories: categories.length ? categories : defaultCategories,
    // `null` rather than omitted when absent, so `Object.assign(state, snapshot)`
    // on sign-out clears it like every other field. An omitted key would leave
    // the previous account's holiday data in place.
    holidaySeason: input.holidaySeason == null ? null : recover('holidaySeason', () =>
      normalizeSeason(checkSeasonShape(input.holidaySeason, 'holidaySeason')), null),
    holidaySeasonHistory: input.holidaySeasonHistory == null ? null : recover('holidaySeasonHistory', () => {
      if (!Array.isArray(input.holidaySeasonHistory)) throw new Error('expected a list');
      input.holidaySeasonHistory.forEach((row, index) => checkSeasonShape(row, `holidaySeasonHistory[${index}]`));
      return normalizeHistory(input.holidaySeasonHistory);
    }, null),
    updatedAt: recover('updatedAt', () => input.updatedAt == null ? '1970-01-01T00:00:00Z' : timestamp(input.updatedAt), '1970-01-01T00:00:00Z'),
  };
  return { snapshot, warnings };
}

export function exportBackup(input) {
  const { snapshot } = normalizeSnapshot(input, { strict: true });
  const budgets = row => Object.fromEntries(MONEY_KEYS.map(key => [key, Math.round(row[key] * 100)]));
  const date = value => iso(new Date(`${value}T12:00:00`));
  const entry = (row, recurring = false) => {
    const { type, date: entryDate, nextOccurrenceDate, ...rest } = row;
    return { ...rest, id: uuid(row.id), amount: Math.round(row.amount * 100), tab: type,
      ...(recurring ? { nextOccurrenceDate: date(nextOccurrenceDate) } : { date: date(entryDate) }) };
  };
  return {
    ...snapshot, schemaVersion: 2, ...budgets(snapshot), updatedAt: iso(new Date(snapshot.updatedAt)),
    transactions: snapshot.transactions.map(row => entry(row)),
    recurringRules: snapshot.recurringRules.map(row => entry(row, true)),
    monthHistory: snapshot.monthHistory.map(row => ({ ...row, ...budgets(row), archivedAt: iso(new Date(row.archivedAt)), transactions: row.transactions.map(item => entry(item)) })),
    personalCategories: snapshot.personalCategories.map(row => ({ ...row, id: uuid(row.id) })),
  };
}

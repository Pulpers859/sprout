// Holiday spending: the web half of the iOS Holiday tab.
//
// MONEY UNITS: every amount in this module and in the holiday slice of web
// state is **integer cents**, unlike the rest of the web app, which keeps
// dollars (see money.mjs). That is deliberate and it is not cosmetic.
//
// Holiday data has only ever been written by iOS, at schema v2, in cents. Web
// snapshots already on disk carry it verbatim under `schemaVersion: 1`, because
// the previous web build passed it through without interpreting it. If the
// importer rescaled holiday amounts by the snapshot's version the way it does
// monthly amounts, every one of those stored $40 gifts would be read as
// $4,000 and written back that way — the exact 100x bug the iOS decoder had to
// be fixed for. Treating holiday money as cents at every boundary makes that
// unrepresentable: iOS writes cents, web reads cents, web writes cents.
//
// Helpers that return money are named `...Cents` so a caller cannot mistake
// one for a dollar figure.

export const HISTORY_LIMIT = 6;
export const RECIPIENT_LIMIT = 100;
export const DEFAULT_RECIPIENT_EMOJI = '🎁';
export const UNASSIGNED_LABEL = 'Not for one person';

export const RECIPIENT_EMOJI_OPTIONS = [
  '🎁', '🎄', '❤️', '⭐️', '🧸', '🍪',
  '👩', '👨', '👧', '👦', '🧑', '👵',
  '👴', '🐶', '🐱', '☕️', '📚', '🎮',
];

const MAX_CENTS = 100_000_000_000_000;
const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);

function newId() {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  // Only reached in environments without WebCrypto; uniqueness is all that is
  // needed here, not unpredictability.
  return `h-${Date.now().toString(16)}-${Math.random().toString(16).slice(2, 10)}`;
}

function clampCents(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
  return Math.min(MAX_CENTS, Math.max(-MAX_CENTS, Math.trunc(value)));
}

export function defaultSeasonLabel(now = new Date()) {
  const date = now instanceof Date ? now : new Date(now);
  const year = Number.isFinite(date.getTime()) ? date.getFullYear() : new Date().getFullYear();
  return `Holiday ${year}`;
}

export function emptySeason(now = new Date()) {
  const date = now instanceof Date ? now : new Date(now);
  const startedAt = Number.isFinite(date.getTime()) ? date : new Date();
  return {
    id: newId(),
    label: defaultSeasonLabel(startedAt),
    budget: 0,
    recipients: [],
    purchases: [],
    startedAt: startedAt.toISOString(),
    closedAt: null,
  };
}

// ── Reading a season ────────────────────────────────────────────────────────

/** Net of returns, as `netSpent` nets refunds on the monthly ledger. */
export function seasonSpentCents(season) {
  return (season?.purchases || []).reduce(
    (total, row) => clampCents(total + (row.isReturn ? -clampCents(row.amount) : clampCents(row.amount))),
    0,
  );
}

export function seasonRemainingCents(season) {
  return clampCents(clampCents(season?.budget) - seasonSpentCents(season));
}

export function seasonHasBudget(season) {
  return clampCents(season?.budget) > 0;
}

/** Gifts only. A return is money coming back, not something bought. */
export function giftCount(season) {
  return (season?.purchases || []).reduce((n, row) => n + (row.isReturn ? 0 : 1), 0);
}

export function returnCount(season) {
  return (season?.purchases || []).reduce((n, row) => n + (row.isReturn ? 1 : 0), 0);
}

/**
 * One person's share. Gifts and returns are counted separately: "3 gifts" must
 * not include money that came back, while deciding whether a bucket has
 * anything at all must — a bucket holding only a return would otherwise vanish
 * from the dashboard with its money still in the season total.
 */
export function recipientTally(season, recipientId) {
  const target = recipientId ?? null;
  let spentCents = 0;
  let gifts = 0;
  let returns = 0;
  for (const row of season?.purchases || []) {
    if ((row.recipientID ?? null) !== target) continue;
    const amount = clampCents(row.amount);
    spentCents = clampCents(spentCents + (row.isReturn ? -amount : amount));
    if (row.isReturn) returns += 1; else gifts += 1;
  }
  return { spentCents, gifts, returns, rows: gifts + returns };
}

export function hasPerPersonTargets(season) {
  return (season?.recipients || []).some(person => person.plannedAmount != null);
}

export function plannedTotalCents(season) {
  return (season?.recipients || []).reduce(
    (total, person) => clampCents(total + (person.plannedAmount == null ? 0 : clampCents(person.plannedAmount))),
    0,
  );
}

/**
 * The part of each target that has not been spent yet. Clamped at the target so
 * a refund larger than someone's spend cannot reserve more than they were ever
 * allotted, and floored at zero so overshooting reserves nothing further.
 */
export function remainingTargetsCents(season) {
  return (season?.recipients || []).reduce((total, person) => {
    if (person.plannedAmount == null) return total;
    const planned = clampCents(person.plannedAmount);
    const spent = recipientTally(season, person.id).spentCents;
    return clampCents(total + Math.min(Math.max(planned - spent, 0), planned));
  }, 0);
}

/**
 * Budget that is neither spent nor still reserved by a target. Always
 * `<= seasonRemainingCents`, so the dashboard can describe a slice of the
 * available balance without ever contradicting the headline figure.
 */
export function unreservedCents(season) {
  return clampCents(seasonRemainingCents(season) - remainingTargetsCents(season));
}

/** Share of the budget spent, clamped. Spending against no budget reads as
 * fully consumed rather than untouched, matching `progress` in money.mjs. */
export function seasonProgress(season) {
  const budget = clampCents(season?.budget);
  const spent = Math.max(seasonSpentCents(season), 0);
  if (budget <= 0) return spent > 0 ? 1 : 0;
  return Math.min(spent / budget, 1);
}

/** `null` when the person has no target, which is not a target of zero. */
export function recipientProgress(season, person) {
  if (!person || person.plannedAmount == null) return null;
  const planned = clampCents(person.plannedAmount);
  const spent = Math.max(recipientTally(season, person.id).spentCents, 0);
  if (planned <= 0) return spent > 0 ? 1 : 0;
  return Math.min(spent / planned, 1);
}

function byDateDesc(a, b) {
  const left = Date.parse(a.row.date);
  const right = Date.parse(b.row.date);
  const lhs = Number.isFinite(left) ? left : 0;
  const rhs = Number.isFinite(right) ? right : 0;
  // Insertion order breaks ties, so two gifts logged the same day keep a
  // stable order instead of shuffling on every render.
  return rhs === lhs ? b.index - a.index : rhs - lhs;
}

export function purchasesNewestFirst(season) {
  return (season?.purchases || [])
    .map((row, index) => ({ row, index }))
    .sort(byDateDesc)
    .map(item => item.row);
}

export function purchasesFor(season, recipientId) {
  const target = recipientId ?? null;
  return (season?.purchases || [])
    .map((row, index) => ({ row, index }))
    .filter(item => (item.row.recipientID ?? null) === target)
    .sort(byDateDesc)
    .map(item => item.row);
}

export function findRecipient(season, recipientId) {
  if (recipientId == null) return null;
  return (season?.recipients || []).find(person => person.id === recipientId) || null;
}

/** Added order, with the name breaking ties so a file whose timestamps were
 * lost still renders deterministically. */
export function recipientsInDisplayOrder(season) {
  return [...(season?.recipients || [])].sort((a, b) => {
    const left = Date.parse(a.createdAt);
    const right = Date.parse(b.createdAt);
    const lhs = Number.isFinite(left) ? left : 0;
    const rhs = Number.isFinite(right) ? right : 0;
    if (lhs === rhs) return String(a.name).localeCompare(String(b.name), undefined, { sensitivity: 'base' });
    return lhs - rhs;
  });
}

export function unassignedRowCount(season) {
  return (season?.purchases || []).reduce((n, row) => n + ((row.recipientID ?? null) === null ? 1 : 0), 0);
}

export function seasonIsEmpty(season) {
  return !(season?.purchases || []).length
    && !(season?.recipients || []).length
    && !seasonHasBudget(season);
}

// ── Normalizing a season ────────────────────────────────────────────────────

const sameRecipient = (a, b) =>
  a.name === b.name && a.emoji === b.emoji && (a.plannedAmount ?? null) === (b.plannedAmount ?? null);

const samePurchase = (a, b) =>
  (a.recipientID ?? null) === (b.recipientID ?? null)
  && a.name === b.name && a.amount === b.amount && a.note === b.note
  && a.date === b.date && a.isReturn === b.isReturn;

/**
 * Keeps a season internally consistent. Renames rather than deletes, because
 * this runs on every save and deleting a row with a blank field would remove
 * it out from under someone mid-edit.
 *
 * A row sharing an id is not automatically a row to discard: an identical one
 * is a merge artifact and costs nothing, but a *different* one is a real person
 * or a real gift, and dropping it silently loses them. Identical rows are
 * collapsed; differing ones are re-identified.
 */
export function normalizeSeason(season, now = new Date()) {
  // Every field this module knows is written explicitly below, `closedAt`
  // included, and never conditionally omitted. Firestore writes use
  // `{merge: true}`, which deep-merges nested maps: a key left out of a write
  // keeps whatever the stored document had, so an active season written
  // without `closedAt` would silently inherit the closed stamp of the season
  // it replaced and come back looking closed.
  const source = isObject(season) ? season : {};
  const startedAt = typeof source.startedAt === 'string' && Number.isFinite(Date.parse(source.startedAt))
    ? source.startedAt
    : (now instanceof Date ? now : new Date()).toISOString();

  const label = String(source.label ?? '').trim();
  const budget = Math.max(clampCents(source.budget), 0);

  const byRecipientId = new Map();
  const recipients = [];
  for (const raw of Array.isArray(source.recipients) ? source.recipients : []) {
    if (!isObject(raw)) continue;
    const name = String(raw.name ?? '').trim();
    const emoji = String(raw.emoji ?? '').trim();
    const planned = raw.plannedAmount == null ? null : Math.max(clampCents(raw.plannedAmount), 0);
    const person = {
      ...raw,
      id: typeof raw.id === 'string' && raw.id ? raw.id : newId(),
      name: name || 'Someone',
      emoji: emoji || DEFAULT_RECIPIENT_EMOJI,
      plannedAmount: planned,
      createdAt: typeof raw.createdAt === 'string' && Number.isFinite(Date.parse(raw.createdAt))
        ? raw.createdAt
        : startedAt,
    };
    const existing = byRecipientId.get(person.id);
    if (existing) {
      if (sameRecipient(existing, person)) continue;
      person.id = newId();
    }
    byRecipientId.set(person.id, person);
    recipients.push(person);
  }

  const byPurchaseId = new Map();
  const purchases = [];
  for (const raw of Array.isArray(source.purchases) ? source.purchases : []) {
    if (!isObject(raw)) continue;
    const name = String(raw.name ?? '').trim();
    const referenced = raw.recipientID == null ? null : String(raw.recipientID);
    const gift = {
      ...raw,
      id: typeof raw.id === 'string' && raw.id ? raw.id : newId(),
      // A gift pointing at someone who is no longer here is re-homed as
      // unassigned rather than left dangling: it still counts toward the
      // season total, so it has to appear in a list somewhere.
      recipientID: referenced != null && byRecipientId.has(referenced) ? referenced : null,
      name: name || 'Gift',
      amount: clampCents(raw.amount),
      note: String(raw.note ?? '').trim(),
      date: typeof raw.date === 'string' && Number.isFinite(Date.parse(raw.date)) ? raw.date : startedAt,
      isReturn: raw.isReturn === true,
    };
    const existing = byPurchaseId.get(gift.id);
    if (existing) {
      if (samePurchase(existing, gift)) continue;
      gift.id = newId();
    }
    byPurchaseId.set(gift.id, gift);
    purchases.push(gift);
  }

  return {
    // Spread first so every key this module models overrides the stored value,
    // while anything it does not model survives the round trip.
    ...source,
    id: typeof source.id === 'string' && source.id ? source.id : newId(),
    label: label || defaultSeasonLabel(startedAt),
    budget,
    recipients,
    purchases,
    startedAt,
    closedAt: typeof source.closedAt === 'string' && Number.isFinite(Date.parse(source.closedAt))
      ? source.closedAt
      : null,
  };
}

function closeStamp(season) {
  const closed = Date.parse(season?.closedAt);
  if (Number.isFinite(closed)) return closed;
  const started = Date.parse(season?.startedAt);
  return Number.isFinite(started) ? started : 0;
}

export function normalizeHistory(history, now = new Date()) {
  const seen = new Set();
  const ordered = (Array.isArray(history) ? history : [])
    .filter(isObject)
    .map(season => normalizeSeason(season, now))
    .filter(season => {
      if (seen.has(season.id)) return false;
      seen.add(season.id);
      return true;
    })
    .sort((a, b) => {
      const delta = closeStamp(b) - closeStamp(a);
      return delta !== 0 ? delta : String(b.label).localeCompare(String(a.label));
    });
  // Only seasons that held something are ever archived, so trimming by recency
  // cannot evict a meaningful season in favour of a placeholder.
  return ordered.slice(0, HISTORY_LIMIT);
}

/** Two archived seasons both called "Holiday 2026" make the history list
 * unreadable, so the one being filed is disambiguated on the way in. The
 * season the user is about to work in keeps the name they asked for. */
export function uniqueArchivedLabel(history, base) {
  const taken = new Set((history || []).map(season => season.label));
  if (!taken.has(base)) return base;
  for (let suffix = 2; suffix <= 99; suffix++) {
    const candidate = `${base} (${suffix})`;
    if (!taken.has(candidate)) return candidate;
  }
  return base;
}

/**
 * Closes the active season and opens a fresh one.
 *
 * The close stamp is forced strictly later than anything already in history.
 * History is sorted by close time and then trimmed, so a stored season closed
 * under a clock that ran ahead — or a clock the user has since set back —
 * sorted the season being filed right now to the bottom, where the cap dropped
 * it immediately. `resetLedger` has a backwards-clock guard; this is its
 * holiday equivalent.
 */
export function startNewSeason({ season, history, label, carryRecipients, now = new Date() }) {
  const at = now instanceof Date ? now : new Date();
  const stamp = Number.isFinite(at.getTime()) ? at : new Date();
  const closing = normalizeSeason(season, stamp);
  const existingHistory = (Array.isArray(history) ? history : []).filter(isObject);

  let nextHistory = existingHistory;
  if (!seasonIsEmpty(closing)) {
    const newestStored = existingHistory.reduce((newest, row) => Math.max(newest, closeStamp(row)), -Infinity);
    const closedMs = Number.isFinite(newestStored) && newestStored >= stamp.getTime()
      ? newestStored + 1000
      : stamp.getTime();
    closing.closedAt = new Date(closedMs).toISOString();
    closing.label = uniqueArchivedLabel(existingHistory, closing.label);
    nextHistory = [closing, ...existingHistory];
  }

  const requested = String(label ?? '').trim();
  const nextSeason = {
    id: newId(),
    label: requested || defaultSeasonLabel(stamp),
    // The budget is a standing choice, so it carries like the monthly base
    // budget does across a rollover.
    budget: closing.budget,
    recipients: carryRecipients ? closing.recipients.map(person => ({ ...person })) : [],
    purchases: [],
    startedAt: stamp.toISOString(),
    closedAt: null,
  };

  return { season: normalizeSeason(nextSeason, stamp), history: normalizeHistory(nextHistory, stamp) };
}

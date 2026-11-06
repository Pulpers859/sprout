import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { randomUUID } from 'node:crypto';
import * as money from './money.mjs';
import * as ledger from './ledger.mjs';
import * as backup from './backup.mjs';
import * as holiday from './holiday.mjs';

const html = readFileSync(new URL('./index.html', import.meta.url), 'utf8');
const script = html.match(/<script type="module">([\s\S]*?)<\/script>/)[1]
  .replace(/^\s*import .*?;\s*$/gm, '');

function harness(storage = new Map()) {
  const timers = new Map(), writes = [], nodes = new Map(), writeHolds = [];
  let authCallback, cloud = null, cloudError = null, timerID = 0, failWriteKey = null;
  const app = { innerHTML: '' };
  const document = {
    hidden: false, addEventListener() {}, querySelectorAll() { return []; }, querySelector() { return null; },
    getElementById(id) {
      if (id === 'app') return app;
      // Most elements are absent. Materialize only controls explicitly needed by
      // a test, plus the sign-in control that render assigns directly.
      if (id === 'signInBtn') return nodes.get(id) || nodes.set(id, {}).get(id);
      return nodes.get(id) || null;
    },
  };
  const context = vm.createContext({
    ...money, ...ledger, ...backup, sumTransactions: money.netSpent, Holiday: holiday,
    console, Intl, Date, structuredClone, crypto: { randomUUID },
    navigator: { language: 'en-US' }, document,
    window: { SPROUT_FIREBASE: { apiKey: 'test-placeholder' }, addEventListener() {} },
    localStorage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => {
      if (key === failWriteKey) throw new Error('Quota exceeded');
      storage.set(key, String(value));
    }, removeItem: key => storage.delete(key) },
    setTimeout: fn => { const id = ++timerID; timers.set(id, fn); return id; },
    clearTimeout: id => timers.delete(id),
    initializeApp: () => ({}), getAuth: () => ({}), getFirestore: () => ({}),
    GoogleAuthProvider: class {}, onAuthStateChanged: (_auth, fn) => { authCallback = fn; },
    signOut: async () => {}, signInWithPopup: async () => {}, signInWithRedirect: async () => {},
    doc: (_db, collection, uid) => ({ collection, uid }),
    getDoc: async () => {
      if (cloudError) throw cloudError;
      const snapshot = structuredClone(cloud);
      return { exists: () => snapshot !== null, data: () => structuredClone(snapshot) };
    },
    setDoc: async (ref, data) => {
      writes.push({ ref, data: structuredClone(data) });
      const hold = writeHolds.shift();
      if (hold) await hold;
      cloud = structuredClone(data);
    },
  });
  vm.runInContext(script, context, { filename: 'index.html' });
  const run = source => vm.runInContext(source, context);
  const value = source => structuredClone(run(source));
  const node = id => {
    const handlers = {};
    const item = { value: '', addEventListener: (name, fn) => { handlers[name] = fn; }, click: () => handlers.click?.(), handlers };
    nodes.set(id, item); return item;
  };
  return { run, value, storage, timers, writes, app, node,
    failWrite: key => { failWriteKey = key; },
    fireTimers: () => { const pending = [...timers.values()]; timers.clear(); pending.forEach(fn => fn()); },
    holdNextWrite: () => {
      let release; writeHolds.push(new Promise(resolve => { release = resolve; }));
      return () => release();
    },
    cloudSnapshot: () => structuredClone(cloud),
    login: async (uid = 'alice') => { await authCallback({ uid }); },
    cloud: data => { cloud = data; }, cloudError: error => { cloudError = error; },
  };
}

test('actual add/edit paths trim names, preserve identity and update refund math', async () => {
  const h = harness(); await h.login();
  h.run(`startForm('expense'); state.formName=' Coffee '; state.formNote=' note '; state.formAmount='1.005'; addTransaction(false)`);
  assert.equal(h.value('state.transactions.length'), 1);
  const original = h.value('state.transactions[0]');
  assert.equal(original.amount, 1.01); assert.equal(original.name, 'Coffee'); assert.equal(original.note, 'note');
  h.run(`startForm('payment', state.transactions[0], true); state.formAmount='2.10'; addTransaction(true)`);
  assert.equal(h.value('state.transactions.length'), 1);
  assert.equal(h.value('state.transactions[0].id'), original.id);
  assert.equal(h.value(`netSpent('personal')`), -2.1);
  assert.equal(h.value(`getRemaining('personal')`), 202.1);
});

test('actual transaction validation refuses malformed, rounded-zero and invalid-date entries', async () => {
  const h = harness(); await h.login();
  for (const amount of ['1e2', '12oops', '0.001', '1000000', '-2']) {
    h.run(`startForm('expense'); state.formName='Food'; state.formAmount=${JSON.stringify(amount)}; addTransaction(false)`);
    assert.equal(h.value('state.transactions.length'), 0, amount);
    assert.ok(h.value('state.formError'));
  }
  h.run(`state.formAmount='10'; state.formName='   '; addTransaction(false)`);
  assert.equal(h.value('state.transactions.length'), 0);
  h.run(`state.formName='Food'; state.formDate='2026-02-30'; addTransaction(false)`);
  assert.equal(h.value('state.transactions.length'), 0);
});

test('quick-add starts fresh after a stale edit draft while keeping merchant/category', async () => {
  const h = harness(); await h.login();
  h.run(`state.formAmount='99'; state.formNote='old'; state.formDate='2020-01-01'; state.formRecurring=true; state.editingTransactionId='old'; startForm('expense', {name:'Cafe',emoji:'☕'})`);
  assert.equal(h.value('state.formName'), 'Cafe'); assert.equal(h.value('state.formEmoji'), '☕');
  assert.equal(h.value('state.formAmount'), ''); assert.equal(h.value('state.formNote'), '');
  assert.equal(h.value('state.formDate'), h.value('getToday()'));
  assert.equal(h.value('state.editingTransactionId'), null); assert.equal(h.value('state.formRecurring'), false);
});

test('budget save event changes base only, accepts zero and rejects invalid text', async () => {
  const h = harness(); await h.login();
  const input = h.node('budgetInput'), save = h.node('budgetSave');
  h.run('state.personalCarryover=25.1; bindEvents()');
  input.value = '100.20'; save.click();
  assert.equal(h.value(`getBudget('personal')`), 125.3);
  input.value = '1e3'; save.click();
  assert.equal(h.value('state.personalBudget'), 100.2);
  assert.ok(h.value('state.budgetError'));
  input.value = '0'; save.click();
  assert.equal(h.value('state.personalBudget'), 0); assert.equal(h.value('state.personalCarryover'), 25.1);
});

test('reset archives current transactions, preserves future ones and carries cents accurately', async () => {
  const h = harness(); await h.login();
  h.run(`state.transactions=[{id:'old',name:'Lunch',amount:10.1,date:getToday(),type:'personal',isRefund:false,emoji:'🍕',note:''},{id:'future',name:'Future',amount:5,date:'9999-01-01',type:'personal',isRefund:false,emoji:'🍕',note:''}]; resetMonth(true)`);
  assert.equal(h.value('state.monthHistory.length'), 1);
  assert.equal(h.value('state.monthHistory[0].transactions[0].id'), 'old');
  assert.equal(h.value('state.transactions.length'), 1);
  assert.equal(h.value('state.transactions[0].id'), 'future');
  assert.equal(h.value('state.personalCarryover'), 189.9);
});

test('loadData picks newer local data and signout cancels stale writes without erasing its cache', async () => {
  const h = harness();
  const key = h.value(`cacheKeyForUser('alice')`);
  const local = { ...h.value('stateSnapshot()'), personalBudget: 321, updatedAt: '2090-01-02T00:00:00Z' };
  h.storage.set(key, JSON.stringify(local));
  h.cloud({ ...local, personalBudget: 123, updatedAt: '2090-01-01T00:00:00Z' });
  await h.login();
  assert.equal(h.value('state.personalBudget'), 321);
  assert.equal(h.writes[0].data.personalBudget, 321);
  h.run('scheduleSave()'); assert.equal(h.timers.size, 1);
  const saved = h.storage.get(key), writes = h.writes.length;
  h.run('handleSignOut()'); await Promise.resolve(); await Promise.resolve();
  assert.equal(h.timers.size, 0); assert.equal(h.value('state.user'), null);
  assert.equal(h.storage.get(key), saved); assert.equal(h.writes.length, writes);
});

test('loadData cloud failure without cache blocks mutations', async () => {
  const h = harness(); h.cloudError(new Error('offline')); await h.login();
  assert.equal(h.value('state.writeBlocked'), true);
  h.run(`startForm('expense'); state.formName='Food'; state.formAmount='10'; addTransaction(false); resetMonth()`);
  assert.equal(h.value('state.transactions.length'), 0); assert.equal(h.timers.size, 0); assert.equal(h.writes.length, 0);
});

test('backup preview is nonmutating; confirmed import can restore its safety copy', async () => {
  const h = harness(); await h.login();
  const before = h.value('state.personalBudget');
  const data = backup.exportBackup({ ...h.value('stateSnapshot()'), personalBudget: 87.65 });
  h.run('state.showSettings=true');
  const promise = h.run('previewImport');
  await promise({ size: 500, text: async () => JSON.stringify(data) });
  assert.equal(h.value('state.personalBudget'), before);
  assert.ok(h.value('state.pendingImport'));
  h.run('confirmImport()');
  assert.equal(h.value('state.personalBudget'), 87.65); assert.equal(h.value('state.canUndoImport'), true);
  h.run('undoImport()');
  assert.equal(h.value('state.personalBudget'), before); assert.equal(h.value('state.canUndoImport'), false);
});

test('backup preview cannot cross account identity during asynchronous file reading', async () => {
  const h = harness(); await h.login();
  const data = backup.exportBackup(h.value('stateSnapshot()'));
  let finish;
  const pending = h.run('previewImport')({ size: 500, text: () => new Promise(resolve => { finish = resolve; }) });
  await h.login('bob'); finish(JSON.stringify(data)); await pending;
  assert.equal(h.value('state.pendingImport'), null);
});

test('import quota failure after the safety copy preserves live data and blocked state', async () => {
  const h = harness(); await h.login();
  const key = h.value(`cacheKeyForUser('alice')`);
  h.run('state.personalBudget=345.67; state.writeBlocked=true');
  const before = h.value('stateSnapshot()');
  h.storage.set(key, JSON.stringify(before));
  const replacement = backup.exportBackup({ ...before, personalBudget: 12.34 });
  await h.run('previewImport')({ size: 500, text: async () => JSON.stringify(replacement) });
  h.failWrite(key); h.run('confirmImport()');
  assert.equal(h.value('state.personalBudget'), 345.67);
  assert.equal(h.value('state.writeBlocked'), true);
  assert.equal(h.value('state.canUndoImport'), false);
  assert.ok(h.value('state.pendingImport'));
  assert.equal(h.storage.get(key), JSON.stringify(before));
  assert.equal(JSON.parse(h.storage.get(`${key}:before-import`)).personalBudget, 345.67);
  assert.equal(h.timers.size, 0); assert.equal(h.writes.length, 0);
});

test('unsupported newer cloud schema blocks writes and preserves both original sources', async () => {
  const h = harness(), key = h.value(`cacheKeyForUser('alice')`);
  const local = { ...h.value('stateSnapshot()'), personalBudget: 321, updatedAt: '2020-01-01T00:00:00Z' };
  const cloud = { ...local, schemaVersion: 999, personalBudget: 54321, updatedAt: '2090-01-01T00:00:00Z' };
  h.storage.set(key, JSON.stringify(local)); h.cloud(cloud); await h.login();
  assert.equal(h.value('state.personalBudget'), 321); assert.equal(h.value('state.writeBlocked'), true);
  assert.equal(h.storage.get(key), JSON.stringify(local));
  assert.equal(h.storage.get(`${key}:recovery`), JSON.stringify(cloud));
  h.run('scheduleSave()'); assert.equal(h.writes.length, 0); assert.equal(h.timers.size, 0);
});

test('damaged primary cache retains its original bytes while recovering the previous generation', async () => {
  const h = harness(), key = h.value(`cacheKeyForUser('alice')`);
  const previous = { ...h.value('stateSnapshot()'), personalBudget: 456.78 };
  h.storage.set(key, '{ damaged save'); h.storage.set(`${key}:previous`, JSON.stringify(previous));
  await h.login();
  assert.equal(h.value('state.personalBudget'), 456.78); assert.equal(h.value('state.writeBlocked'), true);
  assert.equal(h.storage.get(key), '{ damaged save'); assert.equal(h.storage.get(`${key}:recovery`), '{ damaged save');
  assert.equal(h.writes.length, 0); assert.equal(h.timers.size, 0);
});

test('empty cache and empty existing cloud documents are protected, not treated as new accounts', async () => {
  for (const source of ['cache', 'cloud']) {
    const h = harness(), key = h.value(`cacheKeyForUser('alice')`);
    if (source === 'cache') h.storage.set(key, '{}'); else h.cloud({});
    await h.login();
    assert.equal(h.value('state.writeBlocked'), true, source);
    assert.equal(h.writes.length, 0, source); assert.equal(h.timers.size, 0, source);
    assert.equal(h.storage.get(`${key}:recovery`), '{}', source);
  }
});

test('import undo survives reload, then clears its availability after durable restoration', async () => {
  const h = harness(); await h.login();
  h.run('state.personalBudget=111.22');
  const replacement = backup.exportBackup({ ...h.value('stateSnapshot()'), personalBudget: 87.65 });
  await h.run('previewImport')({ size: 500, text: async () => JSON.stringify(replacement) });
  h.run('confirmImport()');
  const reload = harness(h.storage); await reload.login();
  assert.equal(reload.value('state.personalBudget'), 87.65); assert.equal(reload.value('state.canUndoImport'), true);
  reload.run('undoImport()');
  assert.equal(reload.value('state.personalBudget'), 111.22); assert.equal(reload.value('state.canUndoImport'), false);
  const key = reload.value(`cacheKeyForUser('alice')`);
  assert.equal(reload.storage.has(`${key}:before-import`), false);
  const secondReload = harness(reload.storage); await secondReload.login();
  assert.equal(secondReload.value('state.personalBudget'), 111.22); assert.equal(secondReload.value('state.canUndoImport'), false);
});

test('recurring refresh stops at the displayed month boundary until rollover is resolved', async () => {
  const h = harness(); await h.login();
  h.run(`state.currentMonth='2000-01'; state.recurringRules=[{id:'rent',name:'Rent',amount:10,type:'personal',isRefund:false,frequency:'monthly',nextOccurrenceDate:'2000-01-15',anchorDay:15}]; refreshDate()`);
  assert.equal(h.value('state.transactions.length'), 1);
  assert.equal(h.value('state.transactions[0].date'), '2000-01-15');
  assert.equal(h.value('state.recurringRules[0].nextOccurrenceDate'), '2000-02-15');
  assert.equal(h.value('state.showReset'), true);
  h.run('refreshDate()'); assert.equal(h.value('state.transactions.length'), 1);
});

test('same-account relogin cannot let an old queued write replace the latest device edit', async () => {
  const h = harness(); await h.login();
  const releaseA1 = h.holdNextWrite();
  h.run('state.personalBudget=101; scheduleSave()'); h.fireTimers();
  await Promise.resolve();
  assert.equal(h.writes.length, 1); assert.equal(h.writes[0].data.personalBudget, 101);
  h.run('state.personalBudget=202; scheduleSave()'); h.fireTimers();
  await Promise.resolve();
  assert.equal(h.writes.length, 1); // A2 waits behind A1.
  h.run('state.personalBudget=303; scheduleSave()');
  assert.equal(h.timers.size, 1); // A3 exists only in the durable device copy.
  h.run('handleSignOut()');
  const relogin = h.login();
  await Promise.resolve();
  releaseA1(); await relogin;
  await h.run('cloudWriteQueue');
  assert.deepEqual(h.writes.map(write => write.data.personalBudget), [101, 303]);
  assert.equal(h.cloudSnapshot().personalBudget, 303);
  assert.equal(h.value('state.personalBudget'), 303);
  assert.equal(h.timers.size, 0);
});

test('same-user relogin invalidates an import file read from the old auth session', async () => {
  const h = harness(); await h.login();
  const data = backup.exportBackup(h.value('stateSnapshot()'));
  let finish;
  const pending = h.run('previewImport')({ size: 500, text: () => new Promise(resolve => { finish = resolve; }) });
  h.run('handleSignOut()'); await h.login();
  finish(JSON.stringify(data)); await pending;
  assert.equal(h.value('state.pendingImport'), null);
});

test('import and destructive-action confirmations replace the settings overlay', async () => {
  const h = harness(); await h.login();
  h.run('state.showSettings=true; render()');
  assert.match(h.app.innerHTML, /id="settingsOverlay"/);
  const data = backup.exportBackup(h.value('stateSnapshot()'));
  await h.run('previewImport')({ size: 500, text: async () => JSON.stringify(data) });
  assert.match(h.app.innerHTML, /aria-label="Confirm backup import"/);
  assert.doesNotMatch(h.app.innerHTML, /id="settingsOverlay"/);
  for (const kind of ['undo', 'stop']) {
    h.run(`state.pendingImport=null; state.pendingAction={kind:'${kind}'}; render()`);
    assert.match(h.app.innerHTML, /aria-label="Confirm action"/);
    assert.doesNotMatch(h.app.innerHTML, /id="settingsOverlay"/);
    assert.equal((h.app.innerHTML.match(/class="modal-overlay"/g) || []).length, 1);
  }
});

// Back-to-back edits must not tie the timestamp used for cloud reconciliation.
test('save timestamps advance even when the clock has not caught up with the previous save', async () => {
  const h = harness(); await h.login();
  h.run("state.updatedAt = '2090-01-01T00:00:00.000Z'; scheduleSave()");
  assert.equal(h.value('state.updatedAt'), '2090-01-01T00:00:00.001Z');
  h.run('scheduleSave()');
  assert.equal(h.value('state.updatedAt'), '2090-01-01T00:00:00.002Z');
});

// ── Holiday ──

const addGift = (h, { name = 'Scarf', amount = '40', person = null, isReturn = false, note = '', date = null } = {}) =>
  h.run(`startHolidayGiftForm({ recipientID: ${person === null ? 'null' : JSON.stringify(person)}, isReturn: ${isReturn} });
    state.holidayForm.name = ${JSON.stringify(name)};
    state.holidayForm.amount = ${JSON.stringify(amount)};
    state.holidayForm.note = ${JSON.stringify(note)};
    ${date ? `state.holidayForm.date = ${JSON.stringify(date)};` : ''}
    state.holidayForm.recipientChosen = true;
    saveHolidayGift()`);

const addPerson = (h, name, planned = '') =>
  h.run(`startHolidayPersonForm();
    state.holidayForm.name = ${JSON.stringify(name)};
    state.holidayForm.planned = ${JSON.stringify(planned)};
    saveHolidayPerson();
    state.holidaySeason.recipients.at(-1).id`);

test('holiday gifts never touch either monthly budget', async () => {
  const h = harness(); await h.login();
  const before = { personal: h.value(`getRemaining('personal')`), grocery: h.value(`getRemaining('grocery')`) };
  h.run(`commitSeason({ ...season(), budget: 60000 })`);
  const mom = h.run(addPerson(h, 'Mom', '150') && `state.holidaySeason.recipients[0].id`);
  addGift(h, { name: 'Sweater', amount: '80', person: mom });
  addGift(h, { name: 'Wrapping paper', amount: '12' });

  assert.equal(h.value(`Holiday.seasonSpentCents(season())`), 9200);
  assert.equal(h.value(`getRemaining('personal')`), before.personal);
  assert.equal(h.value(`getRemaining('grocery')`), before.grocery);
  // Not in the monthly ledger at all, which is what makes the exclusion
  // structural rather than a filter every caller has to remember.
  assert.equal(h.value('state.transactions.length'), 0);
});

test('monthly spending never touches the holiday budget, and a reset leaves the season alone', async () => {
  const h = harness(); await h.login();
  h.run(`commitSeason({ ...season(), budget: 50000 })`);
  const mom = addPerson(h, 'Mom');
  addGift(h, { name: 'Headphones', amount: '120', person: mom });
  h.run(`startForm('expense'); state.formName='Coffee'; state.formAmount='4.75'; addTransaction(false)`);

  assert.equal(h.value(`Holiday.seasonSpentCents(season())`), 12000);
  h.run(`resetMonth(true)`);
  assert.equal(h.value('state.holidaySeason.budget'), 50000);
  assert.equal(h.value(`Holiday.seasonSpentCents(season())`), 12000);
  assert.equal(h.value('state.holidaySeason.recipients.length'), 1);
  // And no archived month absorbed the gift.
  assert.ok(h.value('state.monthHistory').every(m => m.transactions.every(t => t.name !== 'Headphones')));
});

test('holiday amounts persist as cents to the device cache and the cloud', async () => {
  const h = harness(); await h.login();
  addGift(h, { name: 'Scarf', amount: '40.25' });
  h.fireTimers();
  await h.run('cloudWriteQueue');
  const cloud = h.cloudSnapshot();
  assert.equal(cloud.holidaySeason.purchases[0].amount, 4025);
  // Dollars beside it, cents inside it — the one representation that cannot
  // read a stored $40 gift as $4,000. See the header of holiday.mjs.
  assert.equal(cloud.personalBudget, 200);
  assert.equal(cloud.schemaVersion, 1);
  const cached = JSON.parse(h.storage.get(h.value(`cacheKeyForUser('alice')`)));
  assert.equal(cached.holidaySeason.purchases[0].amount, 4025);
});

test('a reloaded cache brings holiday data back unchanged', async () => {
  const storage = new Map();
  const first = harness(storage); await first.login();
  first.run(`commitSeason({ ...season(), budget: 75000 })`);
  const mom = addPerson(first, 'Mom', '300');
  addGift(first, { name: 'Scarf', amount: '40.25', person: mom });
  addGift(first, { name: 'Scarf returned', amount: '10', person: mom, isReturn: true });
  first.fireTimers();

  const second = harness(storage); await second.login();
  assert.equal(second.value('state.holidaySeason.budget'), 75000);
  assert.equal(second.value(`Holiday.seasonSpentCents(season())`), 3025);
  assert.equal(second.value('state.holidaySeason.recipients[0].name'), 'Mom');
  assert.equal(second.value('state.holidaySeason.recipients[0].plannedAmount'), 30000);
  assert.equal(second.value(`Holiday.returnCount(season())`), 1);
  assert.equal(second.value('state.statusMessage'), '');
});

test('signing out clears holiday data instead of leaving it for the next account', async () => {
  const h = harness(); await h.login('alice');
  addGift(h, { name: 'Scarf', amount: '40' });
  assert.equal(h.value(`Holiday.seasonSpentCents(season())`), 4000);
  h.run('applyPersistedData({})');
  // A fresh empty season, not Alice's.
  assert.equal(h.value(`Holiday.seasonSpentCents(season())`), 0);
  assert.equal(h.value('state.holidaySeason.purchases.length'), 0);
  assert.equal(h.value('state.holidaySeasonHistory.length'), 0);
});

test('a gift is refused without a description, a positive amount, or a chosen person', async () => {
  const h = harness(); await h.login();
  addPerson(h, 'Mom');

  h.run(`startHolidayGiftForm(); state.holidayForm.amount='20'; saveHolidayGift()`);
  assert.equal(h.value('state.holidaySeason.purchases.length'), 0);
  assert.ok(h.value('state.holidayFormError'));

  for (const amount of ['', '0', '-5', '1e3', '1000000', 'oops']) {
    h.run(`startHolidayGiftForm(); state.holidayForm.name='Gift'; state.holidayForm.recipientChosen=true;
      state.holidayForm.amount=${JSON.stringify(amount)}; saveHolidayGift()`);
    assert.equal(h.value('state.holidaySeason.purchases.length'), 0, amount);
  }

  // With people on the list, filing against nobody has to be a decision.
  h.run(`startHolidayGiftForm(); state.holidayForm.name='Gift'; state.holidayForm.amount='20'; saveHolidayGift()`);
  assert.equal(h.value('state.holidaySeason.purchases.length'), 0);
  assert.match(h.value('state.holidayFormError'), /Choose who/);
});

test('a gift can be filed against nobody when nobody is on the list', async () => {
  const h = harness(); await h.login();
  h.run(`startHolidayGiftForm(); state.holidayForm.name='Wrapping paper'; state.holidayForm.amount='12'; saveHolidayGift()`);
  assert.equal(h.value('state.holidaySeason.purchases.length'), 1);
  assert.equal(h.value('state.holidaySeason.purchases[0].recipientID'), null);
});

test('removing a person removes exactly the money the confirmation named', async () => {
  const h = harness(); await h.login();
  const mom = addPerson(h, 'Mom');
  addPerson(h, 'Dad');
  const dad = h.value('state.holidaySeason.recipients[1].id');
  addGift(h, { name: 'Sweater', amount: '90', person: mom });
  addGift(h, { name: 'Sweater returned', amount: '40', person: mom, isReturn: true });
  addGift(h, { name: 'Socks', amount: '12', person: dad });

  const quoted = h.value(`Holiday.recipientTally(season(), ${JSON.stringify(mom)}).spentCents`);
  assert.equal(quoted, 5000);
  const total = h.value(`Holiday.seasonSpentCents(season())`);
  h.run(`state.pendingHolidayDelete={kind:'person',id:${JSON.stringify(mom)}}; confirmHolidayDelete()`);
  assert.equal(h.value(`Holiday.seasonSpentCents(season())`), total - quoted);
  assert.equal(h.value('state.holidaySeason.recipients.length'), 1);
  // Nothing was left behind as an orphan.
  assert.equal(h.value(`Holiday.unassignedRowCount(season())`), 0);
});

test('a holiday backup round trip keeps the season, its people and its history', async () => {
  const h = harness(); await h.login();
  h.run(`commitSeason({ ...season(), budget: 40000 })`);
  const mom = addPerson(h, 'Mom', '150');
  addGift(h, { name: 'Scarf', amount: '40', person: mom });
  h.run(`state.holidayForm={kind:'season',label:'',carry:true}; saveHolidayNewSeason()`);
  addGift(h, { name: "Next year's first", amount: '20' });

  const portable = h.value('exportBackup(stateSnapshot())');
  assert.equal(portable.schemaVersion, 2);
  assert.equal(portable.holidaySeason.budget, 40000);
  assert.equal(portable.holidaySeason.purchases[0].amount, 2000);
  assert.equal(portable.holidaySeasonHistory.length, 1);
  assert.equal(portable.holidaySeasonHistory[0].purchases[0].amount, 4000);

  const fresh = harness(); await fresh.login();
  fresh.run(`applyPersistedData(${JSON.stringify(portable)})`);
  assert.equal(fresh.value('state.holidaySeason.budget'), 40000);
  assert.equal(fresh.value(`Holiday.seasonSpentCents(season())`), 2000);
  assert.equal(fresh.value('state.holidaySeasonHistory.length'), 1);
  assert.deepEqual(fresh.value('state.holidaySeason.recipients.map(p => p.name)'), ['Mom']);
});

test('the holiday tab keeps the monthly figures reachable and unchanged', async () => {
  const h = harness(); await h.login();
  h.run(`startForm('expense'); state.formName='Coffee'; state.formAmount='4.75'; addTransaction(false)`);
  h.run(`state.activeSection='holiday'`);
  // The bridge never answers "holiday" for a budget question.
  assert.equal(h.value('budgetCat()'), 'personal');
  assert.equal(h.value(`netSpent(budgetCat())`), 4.75);
  h.run(`state.activeSection='grocery'`);
  assert.equal(h.value('budgetCat()'), 'grocery');
});

test('a damaged holiday section in the cache does not cost the monthly ledger', async () => {
  const storage = new Map();
  const seed = harness(storage); await seed.login();
  seed.run(`startForm('expense'); state.formName='Coffee'; state.formAmount='4.75'; addTransaction(false)`);
  seed.fireTimers();
  const key = seed.value(`cacheKeyForUser('alice')`);
  const cached = JSON.parse(storage.get(key));
  cached.holidaySeason = 'wiped';
  storage.set(key, JSON.stringify(cached));

  const h = harness(storage); await h.login();
  assert.equal(h.value('state.transactions.length'), 1);
  assert.equal(h.value(`netSpent('personal')`), 4.75);
  // Reported, not silently swapped for an empty season.
  assert.ok(h.value('state.statusMessage'));
  assert.equal(h.value('state.holidaySeason.purchases.length'), 0);
});

test('transaction search filters by name and note, and goes inert when hidden', async () => {
  const h = harness(); await h.login();
  for (const [name, note] of [['Coffee','morning'],['Lunch',''],['Bus',''],['Books','gift'],['Gas','']]) {
    h.run(`startForm('expense'); state.formName=${JSON.stringify(name)}; state.formNote=${JSON.stringify(note)}; state.formAmount='5'; addTransaction(false)`);
  }
  h.run(`state.txSearch='coff'; render()`);
  assert.match(h.app.innerHTML, /Coffee/);
  assert.ok(!h.app.innerHTML.includes('>Lunch<'));
  // Matches the note too.
  h.run(`state.txSearch='gift'; render()`);
  assert.match(h.app.innerHTML, /Books/);
  assert.ok(!h.app.innerHTML.includes('>Coffee<'));
  // Below five rows the field is gone, so the filter must stop applying or the
  // list reads "no match" with no box to clear.
  h.run(`state.txSearch='coff'; state.transactions = state.transactions.slice(0,3); render()`);
  assert.ok(!h.app.innerHTML.includes('id="txSearch"'));
  assert.match(h.app.innerHTML, /Lunch/);
  // And a query does not survive a tab change.
  h.run(`state.txSearch='coff'; bindEvents()`);
  h.run(`state.activeSection='grocery'; state.txSearch=''; render()`);
  assert.equal(h.value('state.txSearch'), '');
});

test('a closed month shows its leftover, not the whole balance as a daily figure', async () => {
  const h = harness(); await h.login();
  h.run(`state.currentMonth='2020-01'; state.personalBudget=200; render()`);
  const html = h.app.innerHTML;
  // The pre-fix bug: daysLeft is 1 for a past month, so the figure meant to say
  // what you may spend today said "spend all of it".
  assert.ok(!html.includes('$200.00/day'), 'must not offer the whole balance per day');
  assert.match(html, /unspent in/);
});

test('the progress bar is coloured by spend, and pace is its own labelled signal', async () => {
  const h = harness(); await h.login();
  h.run(`state.personalBudget=100; startForm('expense'); state.formName='Big'; state.formAmount='101'; addTransaction(false)`);
  // Over budget is red even when the month's pace calls it "on plan".
  assert.equal(h.value(`getProgressColor(netSpent('personal'), getBudget('personal'))`), 'var(--red)');
  assert.match(h.app.innerHTML, /Spending (too fast|on plan|under plan)/);
  h.run(`state.transactions=[]; state.personalBudget=100; render()`);
  assert.equal(h.value(`getProgressColor(0, 100)`), 'var(--sage)');
});

test('the import prompt names the holiday data on both sides', async () => {
  const h = harness(); await h.login();
  const mom = addPerson(h, 'Mom');
  addGift(h, { name: 'Scarf', amount: '40', person: mom });

  // A backup with no holiday section still replaces the holiday data you have.
  h.run(`state.pendingImport = { snapshot: normalizeSnapshot({ personalBudget: 1, currentMonth: getCurrentMonth() }).snapshot, uid: 'alice', generation: 0, hasHoliday: false }; render()`);
  let html = h.app.innerHTML;
  assert.match(html, /no holiday data/);
  assert.match(html, /You will lose/);
  assert.match(html, /1 gift/);
  assert.match(html, /1 person/);
  assert.match(html, /holiday seasons on this device/);

  // And an incoming season is described rather than summarised as a count of zero.
  const incoming = h.value('exportBackup(stateSnapshot())');
  h.run(`state.pendingImport = { snapshot: normalizeSnapshot(${JSON.stringify(incoming)}).snapshot, uid: 'alice', generation: 0, hasHoliday: true }; render()`);
  html = h.app.innerHTML;
  assert.match(html, /Holiday: 1 holiday gift, 1 person/);
});

test('an active season written to the cloud always carries closedAt', async () => {
  const h = harness(); await h.login();
  addGift(h, { name: 'Scarf', amount: '40' });
  h.run(`state.holidayForm={kind:'season',label:'',carry:false}; saveHolidayNewSeason()`);
  h.fireTimers();
  await h.run('cloudWriteQueue');
  const written = h.cloudSnapshot().holidaySeason;
  // Firestore merges nested maps, so a write that omitted closedAt would let
  // the closed season's stamp survive onto the active one and come back
  // looking closed.
  assert.ok('closedAt' in written);
  assert.equal(written.closedAt, null);
  assert.deepEqual(Object.keys(written).sort(),
    ['budget','closedAt','id','label','purchases','recipients','startedAt']);
});

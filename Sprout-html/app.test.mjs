import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { randomUUID } from 'node:crypto';
import * as money from './money.mjs';
import * as ledger from './ledger.mjs';
import * as backup from './backup.mjs';

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
    ...money, ...ledger, ...backup, sumTransactions: money.netSpent,
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

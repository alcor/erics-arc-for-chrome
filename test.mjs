// Loads the extension into a throwaway Chromium and checks pinned-tab reset.
// Run: npm install && npx playwright-core install chromium && npm test
import { chromium } from 'playwright-core';
import http from 'node:http';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ext = import.meta.dirname;
const server = http.createServer((req, res) => res.end(`<title>${req.url}</title>${req.url}`)).listen(0);
const base = `http://127.0.0.1:${server.address().port}`;

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'arc-for-chrome-test-'));
const ctx = await chromium.launchPersistentContext(profile, {
  channel: 'chromium',
  args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
});
const sw = ctx.serviceWorkers()[0] || await ctx.waitForEvent('serviceworker');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const settle = () => sw.evaluate(() => queue).then(() => sleep(300)).then(() => sw.evaluate(() => queue));
const pinnedUrls = () => sw.evaluate(async () => (await chrome.tabs.query({ pinned: true })).map(t => t.pendingUrl || t.url));
const open = (p, pinned = false) => sw.evaluate(async ([url, pinned]) => {
  const t = await chrome.tabs.create({ url });
  await new Promise(r => setTimeout(r, 300));
  if (pinned) await chrome.tabs.update(t.id, { pinned: true });
  return t.id;
}, [base + p, pinned]);
const go = (id, p) => sw.evaluate(([id, url]) => chrome.tabs.update(id, { url }), [id, base + p]).then(() => sleep(300));
const urlOf = id => sw.evaluate(async id => { const t = await chrome.tabs.get(id); return t.pendingUrl || t.url; }, id);
const call = (fn, id) => sw.evaluate(async ([fn, id]) => { await self[fn](await chrome.tabs.get(id)); }, [fn, id]);
const close = id => sw.evaluate(id => chrome.tabs.remove(id), id).then(settle);

const a = await open('/a', true);
const b = await open('/b', true);
await settle();

await go(a, '/a2');
await call('reset', a);
await sleep(300);
assert.equal(await urlOf(a), `${base}/a`);
console.log('reset after navigation: ok');

// Closing a pinned tab puts it back at its pinned URL in the same spot.
await go(a, '/a3');
await close(a);
assert.deepEqual(await pinnedUrls(), [`${base}/a`, `${base}/b`]);
console.log('close brings pinned tab back: ok');

// Simulated restart: session map forgotten, tabs have drifted, URLs come back from saved order.
const [a2, b2] = await sw.evaluate(async () => (await chrome.tabs.query({ pinned: true })).map(t => t.id));
await go(a2, '/x');
await go(b2, '/y');
await sw.evaluate(async () => { await queue; await chrome.storage.session.clear(); });
await call('reset', b2);
await sleep(300);
assert.equal(await urlOf(b2), `${base}/b`);
console.log('reset after simulated restart: ok');

// Replace pinned URL with current.
await call('repin', a2);
await go(a2, '/z');
await call('reset', a2);
await sleep(300);
assert.equal(await urlOf(a2), `${base}/x`);
console.log('repin: ok');

// Pinning a new tab records its own URL, not a neighbour's.
const c = await open('/c', true);
await settle();
await go(c, '/c2');
await call('reset', c);
await sleep(300);
assert.equal(await urlOf(c), `${base}/c`);
console.log('newly pinned tab keeps its own URL: ok');

// Unpinned tabs: reset does nothing, close really closes.
await sw.evaluate(id => chrome.tabs.update(id, { pinned: false }), c);
await settle();
await go(c, '/c3');
await call('reset', c);
await sleep(300);
assert.equal(await urlOf(c), `${base}/c3`);
await close(c);
assert.deepEqual(await pinnedUrls(), [`${base}/x`, `${base}/b`]);
console.log('unpinned tab ignored: ok');

// Locked tab group: tabs in "CoreCore" behave like pinned tabs.
const g1 = await open('/g1');
const g2 = await open('/g2');
await sw.evaluate(async ids => {
  const groupId = await chrome.tabs.group({ tabIds: ids });
  await chrome.tabGroups.update(groupId, { title: 'CoreCore', color: 'blue' });
}, [g1, g2]);
await settle();
const groupUrls = () => sw.evaluate(async () => {
  const [g] = await chrome.tabGroups.query({ title: 'CoreCore' });
  if (!g) return [];
  return (await chrome.tabs.query({ groupId: g.id })).map(t => t.pendingUrl || t.url);
});
await go(g1, '/g1-drift');
await close(g1);
assert.deepEqual(await groupUrls(), [`${base}/g1`, `${base}/g2`]);
console.log('closed group tab comes back in group: ok');

// ⌘W command closes the active tab through the extension; a locked one comes back.
await sw.evaluate(id => chrome.tabs.update(id, { active: true }), g2);
await go(g2, '/g2-drift');
await sw.evaluate(() => closeTabs());
await settle();
assert.deepEqual(await groupUrls(), [`${base}/g1`, `${base}/g2`]);
console.log('close command on group tab: ok');

// Closing every tab in the group brings the whole group back.
const groupIds = await sw.evaluate(async () => {
  const [g] = await chrome.tabGroups.query({ title: 'CoreCore' });
  return (await chrome.tabs.query({ groupId: g.id })).map(t => t.id);
});
await sw.evaluate(ids => chrome.tabs.remove(ids), groupIds);
await settle();
assert.deepEqual(await groupUrls(), [`${base}/g1`, `${base}/g2`]);
console.log('whole group comes back: ok');

// A tab dragged out of the group is a normal tab again.
const [out] = await sw.evaluate(async () => {
  const [g] = await chrome.tabGroups.query({ title: 'CoreCore' });
  return (await chrome.tabs.query({ groupId: g.id })).map(t => t.id);
});
await sw.evaluate(id => chrome.tabs.ungroup(id), out);
await settle();
await close(out);
assert.deepEqual(await groupUrls(), [`${base}/g2`]);
console.log('ungrouped tab really closes: ok');

// Order saved for the next launch, per slot.
assert.deepEqual((await sw.evaluate(() => chrome.storage.local.get('order'))).order,
  { pinned: [`${base}/x`, `${base}/b`], CoreCore: [`${base}/g2`] });
console.log('saved order: ok');

await ctx.close();
server.close();
fs.rmSync(profile, { recursive: true, force: true });

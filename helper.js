// The helper app (helper/): one native messaging port, opened here and kept open. The helper pings it
// every 20 seconds so this service worker isn't stopped for being idle. Over it go, out: the recently
// used tab list with favicons for the ⌃Tab switcher, a thumbnail of a tab whenever it's been in front,
// and the mini player's state; in: the tab the switcher picked, a link from another app to open as a
// Little Arc, and mini player button presses. Without the helper (not installed, or not running yet)
// nothing here matters: ⌃Tab still arrives as the recent-* commands and links still arrive as tabs.
const HELPER = 'erics_arc_helper';
const MRU_SENT = 12;
const THUMB_WIDTH = 480, THUMB_MIN_MS = 1000, THUMB_SETTLE_MS = 400;

let helper = null, helperRetryMs = 1000;
const helperSend = msg => helper?.postMessage(msg);

function helperConnect() {
  if (helper) return;
  const port = chrome.runtime.connectNative(HELPER);
  port.onMessage.addListener(helperMessage);
  port.onDisconnect.addListener(() => {
    helper = null;
    setTimeout(helperConnect, helperRetryMs);
    helperRetryMs = Math.min(helperRetryMs * 2, 60_000);
  });
  helper = port;
  helperRetryMs = 1000;
  helperHello();
}
helperConnect();
// A timer dies with the worker; the alarm doesn't.
chrome.alarms.create('helper-connect', { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(a => { if (a.name === 'helper-connect') helperConnect(); });

// Tab ids start over when Chrome restarts, so the helper drops its thumbnails when the session changes.
async function helperHello() {
  let { session } = await chrome.storage.session.get('session');
  if (!session) {
    session = crypto.randomUUID();
    await chrome.storage.session.set({ session });
  }
  helperSend({ hello: { session } });
  playerResend();
  helperMruSoon();
}

function helperMessage(msg) {
  if (msg.activate) helperActivate(msg.activate);
  else if (msg.open) openLittle({ url: msg.open });
  else if (msg.player) playerAction(msg.player);
}

function helperActivate(tabId) {
  return run(async () => {
    await endWalk();
    const tab = await chrome.tabs.update(tabId, { active: true }).catch(() => null);
    if (tab) await chrome.windows.update(tab.windowId, { focused: true });
  });
}

// The list: most recently used first, as mruList() orders it, with favicons as data: URLs.
let mruTimer = null;
function helperMruSoon() {
  if (!helper || mruTimer) return;
  mruTimer = setTimeout(() => { mruTimer = null; helperMru().catch(console.error); }, 100);
}

async function helperMru() {
  const ids = (await mruList()).slice(0, MRU_SENT);
  const tabs = (await Promise.all(ids.map(id => chrome.tabs.get(id).catch(() => null)))).filter(Boolean);
  const mru = await Promise.all(tabs.map(async t => ({ id: t.id, windowId: t.windowId, title: t.title || t.url, favicon: await favicon(t.url) })));
  helperSend({ mru });
}

const favicons = new Map();
async function favicon(pageUrl) {
  if (!pageUrl) return null;
  if (favicons.has(pageUrl)) return favicons.get(pageUrl);
  const url = chrome.runtime.getURL(`/_favicon/?pageUrl=${encodeURIComponent(pageUrl)}&size=32`);
  const data = await fetch(url).then(r => r.blob()).then(dataUrl).catch(() => null);
  if (favicons.size > 500) favicons.clear();
  favicons.set(pageUrl, data);
  return data;
}

function dataUrl(blob) {
  return new Promise(resolve => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => resolve(null);
    reader.readAsDataURL(blob);
  });
}

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if ('title' in change || 'favIconUrl' in change) helperMruSoon();
  if (change.status === 'complete') helperThumbSoon(tabId);
});
chrome.tabs.onRemoved.addListener(tabId => {
  helperSend({ closed: tabId });
  helperMruSoon();
});
chrome.tabs.onActivated.addListener(({ tabId }) => helperThumbSoon(tabId, THUMB_SETTLE_MS));
chrome.windows.onFocusChanged.addListener(async windowId => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  const [tab] = await chrome.tabs.query({ active: true, windowId });
  if (tab) helperThumbSoon(tab.id);
});
chrome.runtime.onMessage.addListener((msg, sender) => {
  if (msg.scrolled && sender.tab) helperThumbSoon(sender.tab.id);
});

// Thumbnails. Chrome can only capture the tab that's in front, so each tab's picture is from the last
// time it was: taken shortly after it's activated, when a page finishes loading, and after a scroll,
// at most once a second per tab, scaled down here before it leaves the worker.
const thumbAt = new Map(), thumbTimers = new Map();
function helperThumbSoon(tabId, after = 0) {
  if (!helper) return;
  const wait = Math.max(after, THUMB_MIN_MS - (Date.now() - (thumbAt.get(tabId) || 0)));
  if (thumbTimers.has(tabId)) return;
  thumbTimers.set(tabId, setTimeout(() => {
    thumbTimers.delete(tabId);
    helperThumb(tabId).catch(() => {});
  }, wait));
}

async function helperThumb(tabId) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab?.active || !/^https?:/.test(tab.url)) return;
  thumbAt.set(tabId, Date.now());
  const shot = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'jpeg', quality: 70 }).catch(() => null);
  if (!shot) return;
  const bitmap = await createImageBitmap(await (await fetch(shot)).blob());
  const height = Math.round(bitmap.height * THUMB_WIDTH / bitmap.width);
  const canvas = new OffscreenCanvas(THUMB_WIDTH, height);
  canvas.getContext('2d').drawImage(bitmap, 0, 0, THUMB_WIDTH, height);
  bitmap.close();
  const data = await dataUrl(await canvas.convertToBlob({ type: 'image/jpeg', quality: 0.6 }));
  if (data) helperSend({ thumb: { id: tabId, data } });
}

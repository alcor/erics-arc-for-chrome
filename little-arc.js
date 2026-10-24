// Little Arc: small throwaway windows for quick lookups, like Arc's.
// - ⌥⌘N (set it as a Global shortcut) opens one with a search box (little.html), from any app
// - links opened from other apps open in one
// - ⌥⌘-click a link opens it in one (little-click.js)
// - ⌘O moves the page into the main window as a normal tab; ⌥⌘O or the ▾ picks a window or tab group
// - an "Open in Chrome" bar sits top-right of the page (little-bar.js)
// - left unfocused for 12 hours, a Little Arc closes
// Little Arcs are Chrome popup windows: no tab strip, no sidebar, back with ⌘[.
//
// ponytail: links from other apps first land as a tab in the main window and get moved out, so the main
// window flashes; avoiding that needs a native default-browser shim.

const LITTLE_SIZE = { width: 900, height: 700 };
const LITTLE_ARCHIVE_MS = 12 * 60 * 60 * 1000;

// Session-state writes go through run() (background.js) so focus events can't clobber a new window.
async function littleState() {
  const { little = {}, lastNormal, focused } = await chrome.storage.session.get(['little', 'lastNormal', 'focused']);
  return { little, lastNormal, focused };
}

async function littleBounds() {
  const { littleBounds } = await chrome.storage.local.get('littleBounds');
  if (littleBounds) return littleBounds;
  const w = await chrome.windows.getLastFocused({ windowTypes: ['normal'] }).catch(() => null);
  if (!w) return LITTLE_SIZE;
  return {
    ...LITTLE_SIZE,
    left: Math.round(w.left + (w.width - LITTLE_SIZE.width) / 2),
    top: Math.round(w.top + (w.height - LITTLE_SIZE.height) / 3),
  };
}

async function openLittle({ url, tabId } = {}) {
  const source = tabId ? { tabId } : { url: url || chrome.runtime.getURL('little.html') };
  const w = await chrome.windows.create({ ...source, ...(await littleBounds()), type: 'popup', focused: true });
  await run(async () => {
    const { little } = await littleState();
    little[w.id] = Date.now();
    await chrome.storage.session.set({ little });
  });
  // The page may have finished loading before this window counted as a Little Arc.
  if (!source.url?.startsWith(chrome.runtime.getURL(''))) await showLittleBar(w.tabs[0].id);
  return w;
}

async function isLittleWindow(windowId) {
  return windowId in (await littleState()).little;
}

// Normal windows and their tab groups, most recently focused window first: where a Little Arc can go.
async function littleTargets() {
  const { lastNormal } = await littleState();
  const wins = (await chrome.windows.getAll({ windowTypes: ['normal'] }))
    .sort((a, b) => (b.id === lastNormal) - (a.id === lastNormal));
  const groups = await chrome.tabGroups.query({});
  return wins.map((w, i) => ({
    windowId: w.id,
    title: wins.length > 1 ? `Window ${i + 1}` : 'Chrome',
    groups: groups.filter(g => g.windowId === w.id).map(g => ({ id: g.id, title: g.title || 'Unnamed group', color: g.color })),
  }));
}

async function moveToMain(tabId, { windowId, groupId } = {}) {
  if (!windowId) windowId = (await littleTargets())[0]?.windowId;
  if (!windowId) {
    const w = await chrome.windows.create({ tabId, type: 'normal', focused: true });
    return w;
  }
  await chrome.tabs.move(tabId, { windowId, index: groupId ? -1 : await topIndex(windowId) });
  if (groupId) await chrome.tabs.group({ groupId, tabIds: tabId });
  await chrome.tabs.update(tabId, { active: true });
  await chrome.windows.update(windowId, { focused: true });
}

async function activeLittleTab() {
  const w = await chrome.windows.getLastFocused({ populate: true }).catch(() => null);
  if (!w || !(await isLittleWindow(w.id))) return null;
  return w.tabs.find(t => t.active);
}

async function showLittleBar(tabId) {
  await chrome.scripting.executeScript({ target: { tabId }, files: ['little-bar.js'] }).catch(() => {});
}

async function archiveLittle(now = Date.now()) {
  const { little, focused } = await littleState();
  for (const [id, last] of Object.entries(little)) {
    if (+id !== focused && now - last > LITTLE_ARCHIVE_MS) await chrome.windows.remove(+id).catch(() => {});
  }
}

// Links from other apps. Startup pages also arrive as 'start_page'; starting() leaves those alone.
chrome.webNavigation.onCommitted.addListener(async d => {
  if (d.frameId !== 0 || d.transitionType !== 'start_page' || starting()) return;
  const tab = await chrome.tabs.get(d.tabId).catch(() => null);
  if (!tab || tab.pinned || (await isLittleWindow(tab.windowId))) return;
  const win = await chrome.windows.get(tab.windowId);
  if (win.type !== 'normal') return;
  await openLittle({ tabId: d.tabId });
});

// The "Open in Chrome" bar, on every page load inside a Little Arc.
chrome.webNavigation.onCompleted.addListener(async d => {
  if (d.frameId !== 0 || d.url.startsWith(chrome.runtime.getURL(''))) return;
  const tab = await chrome.tabs.get(d.tabId).catch(() => null);
  if (tab && (await isLittleWindow(tab.windowId))) await showLittleBar(d.tabId);
});

chrome.windows.onFocusChanged.addListener(windowId => run(async () => {
  const { little, focused } = await littleState();
  const now = Date.now();
  if (focused in little) little[focused] = now;
  if (windowId in little) little[windowId] = now;
  const set = { little, focused: windowId };
  if (windowId !== chrome.windows.WINDOW_ID_NONE && !(windowId in little)) {
    const w = await chrome.windows.get(windowId).catch(() => null);
    if (w?.type === 'normal') set.lastNormal = windowId;
  }
  await chrome.storage.session.set(set);
}));

chrome.windows.onRemoved.addListener(windowId => run(async () => {
  const { little } = await littleState();
  if (!(windowId in little)) return;
  delete little[windowId];
  await chrome.storage.session.set({ little });
}));

chrome.windows.onBoundsChanged.addListener(async w => {
  if (!(await isLittleWindow(w.id))) return;
  const { left, top, width, height } = w;
  await chrome.storage.local.set({ littleBounds: { left, top, width, height } });
});

chrome.alarms.create('little-archive', { periodInMinutes: 30 });
chrome.alarms.onAlarm.addListener(a => { if (a.name === 'little-archive') archiveLittle(); });

chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  if (msg.little === 'open') openLittle({ url: msg.url }).then(() => reply(true));
  else if (msg.little === 'targets') littleTargets().then(reply);
  else if (msg.little === 'move') moveToMain(sender.tab.id, msg.to).then(() => reply(true));
  else return;
  return true; // reply comes later
});

async function littleCommand(command) {
  if (command === 'little-new') return openLittle();
  const tab = await activeLittleTab();
  if (!tab) return;
  if (command === 'little-open') return moveToMain(tab.id);
  if (command === 'little-open-in') return chrome.tabs.sendMessage(tab.id, { little: 'menu' }).catch(() => {});
}

// Arc-style locked tabs. A tab is locked when it's pinned or sits in one of LOCKED_GROUPS; it
// remembers the URL it had when it got locked. Closing it (⌘W, middle-click) puts it back at that
// URL in the same spot; ⌃R or the toolbar button resets it in place. Unpin it or drag it out of the
// group first to really close it.
//
// ⌘W is taken over by this extension so it closes tabs itself: Chrome's own ⌘W on a pinned tab
// shows a "press ⌘W again" toast first, and there's no setting to turn that off.
//
// Tab and group ids don't survive a browser restart, so locked URLs are also saved per slot
// ('pinned', or the group title) in tab order. During the first minute of a browser session
// (or after the extension reloads) a locked tab we haven't seen takes the URL saved at its position
// in its slot; after that, a newly locked tab takes its own current URL.
// ponytail: position matching assumes Chrome restores tabs in the same order across all windows;
// closing a window that has locked tabs and then quitting can shift URLs by one.
// "Replace pinned URL with current" or re-locking fixes a wrong one.

// ponytail: hardcoded; add an options page when there's a second group to lock.
const LOCKED_GROUPS = ['CoreCore'];

// Every read-modify-write goes through this queue so overlapping tab events can't clobber each other.
let queue = Promise.resolve();
const run = fn => (queue = queue.then(fn).catch(console.error));

async function lockedTabs() {
  const groups = await chrome.tabGroups.query({});
  const locked = new Map(groups.filter(g => LOCKED_GROUPS.includes(g.title)).map(g => [g.id, g]));
  const tabs = await chrome.tabs.query({});
  return {
    ids: new Set(tabs.map(t => t.id)),
    locked: tabs.filter(t => t.pinned || locked.has(t.groupId))
      .map(t => ({ t, group: t.pinned ? null : locked.get(t.groupId) })),
  };
}

// Entries for closed tabs are kept (onRemoved still needs them if it runs after this) and dropped
// by onRemoved itself; session storage is wiped on restart anyway.
async function sync(change) {
  let { pins = {}, where = {}, restoreUntil } = await chrome.storage.session.get(['pins', 'where', 'restoreUntil']);
  restoreUntil ??= Date.now() + 60_000; // session storage is empty: browser just started or extension reloaded
  const restoring = Date.now() < restoreUntil;
  let { order = {} } = await chrome.storage.local.get('order');
  if (Array.isArray(order)) order = { pinned: order }; // saved before groups were supported
  change?.(pins);
  const { ids, locked } = await lockedTabs();
  const next = {};
  for (const { t, group } of locked) {
    const slot = group ? group.title : 'pinned';
    next[slot] ??= [];
    pins[t.id] ??= (restoring && order[slot]?.[next[slot].length]) || t.url;
    next[slot].push(pins[t.id]);
    where[t.id] = { windowId: t.windowId, index: t.index, group: group?.title, color: group?.color };
  }
  const lockedIds = new Set(locked.map(({ t }) => t.id));
  for (const id in pins) if (ids.has(+id) && !lockedIds.has(+id)) delete pins[id];
  await chrome.storage.session.set({ pins, where, restoreUntil });
  await chrome.storage.local.set({ order: next });
  return pins;
}

const resync = () => run(() => sync());
chrome.runtime.onStartup.addListener(resync);
chrome.runtime.onInstalled.addListener(resync);
chrome.tabs.onMoved.addListener(resync);
chrome.tabs.onAttached.addListener(resync);
chrome.tabGroups.onUpdated.addListener(resync);

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (!('pinned' in change) && !('groupId' in change)) return;
  run(async () => {
    // Chrome also reports pinned:false / ungrouped just before closing a tab; that's not a real unlock.
    const tab = await chrome.tabs.get(tabId).catch(() => null);
    if (!tab) return;
    const group = tab.groupId === -1 ? null : await chrome.tabGroups.get(tab.groupId);
    const isLocked = tab.pinned || LOCKED_GROUPS.includes(group?.title);
    await sync(p => { if (isLocked) p[tabId] ??= tab.url || tab.pendingUrl; else delete p[tabId]; });
  });
});

chrome.tabs.onRemoved.addListener((tabId, { isWindowClosing }) => {
  if (isWindowClosing) return; // window closed or Chrome quitting: keep the saved order for next launch
  run(async () => {
    const { pins = {}, where = {} } = await chrome.storage.session.get(['pins', 'where']);
    const url = pins[tabId], at = where[tabId];
    delete where[tabId];
    await chrome.storage.session.set({ where });
    if (!url || !at) return sync(p => { delete p[tabId]; });
    const tab = await chrome.tabs.create({ url, pinned: !at.group, active: false, windowId: at.windowId, index: at.index });
    if (at.group) {
      const [g] = await chrome.tabGroups.query({ windowId: at.windowId, title: at.group });
      const groupId = await chrome.tabs.group(g ? { groupId: g.id, tabIds: tab.id } : { tabIds: tab.id, createProperties: { windowId: at.windowId } });
      if (!g) await chrome.tabGroups.update(groupId, { title: at.group, color: at.color });
    }
    await sync(p => { delete p[tabId]; p[tab.id] = url; });
  });
});

function reset(tab) {
  return run(async () => {
    const url = (await sync())[tab.id];
    if (url && tab.url !== url) await chrome.tabs.update(tab.id, { url });
  });
}

function repin(tab) {
  return run(() => sync(p => { if (p[tab.id]) p[tab.id] = tab.url; }));
}

async function closeTabs() {
  const tabs = await chrome.tabs.query({ highlighted: true, currentWindow: true });
  await chrome.tabs.remove(tabs.map(t => t.id));
}

chrome.action.onClicked.addListener(reset);

chrome.commands.onCommand.addListener((command, tab) => {
  if (command === 'close-tab') return closeTabs();
  if (command === 'reset-tab') return reset(tab);
  if (command === 'repin-current') return repin(tab);
});

// ⌥⌘-click a link to open it in a Little Arc.
addEventListener('click', e => {
  if (!e.altKey || !e.metaKey) return;
  const a = e.target.closest?.('a[href]');
  if (!a || !/^https?:/.test(a.href)) return;
  e.preventDefault();
  e.stopImmediatePropagation();
  chrome.runtime.sendMessage({ little: 'open', url: a.href });
}, true);

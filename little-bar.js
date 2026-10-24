// The bar in the top-right of a Little Arc page: "Open in Chrome" and ▾ to pick a window or tab
// group, labelled with whatever shortcuts are set for them. Injected by little-arc.js on each page
// load inside a Little Arc.
(() => {
  if (document.getElementById('erics-little-arc-bar')) return;
  const host = document.createElement('div');
  host.id = 'erics-little-arc-bar';
  host.style.cssText = 'all: initial; position: fixed; top: 10px; right: 10px; z-index: 2147483647;';
  const root = host.attachShadow({ mode: 'closed' });
  root.innerHTML = `
    <style>
      .bar, .menu { font: 13px/1 -apple-system, BlinkMacSystemFont, sans-serif; }
      .bar { display: flex; border-radius: 9px; overflow: hidden; background: rgba(32,32,36,.82);
             color: #fff; backdrop-filter: blur(12px); box-shadow: 0 2px 12px rgba(0,0,0,.25); opacity: .9; }
      .bar:hover { opacity: 1; }
      button { all: unset; cursor: default; padding: 7px 10px; }
      button:hover { background: rgba(255,255,255,.12); }
      .caret { border-left: 1px solid rgba(255,255,255,.15); padding: 7px 8px; }
      kbd { font: inherit; opacity: .55; margin-left: 6px; }
      .menu { position: absolute; right: 0; top: 34px; min-width: 200px; padding: 4px; border-radius: 9px;
              background: rgba(32,32,36,.95); color: #fff; box-shadow: 0 6px 24px rgba(0,0,0,.35); }
      .menu[hidden] { display: none; }
      .menu button { display: flex; align-items: center; gap: 8px; width: calc(100% - 20px); border-radius: 6px; }
      .menu .head { padding: 6px 10px 2px; font-size: 11px; opacity: .5; }
      .dot { width: 8px; height: 8px; border-radius: 50%; }
    </style>
    <div class="bar">
      <button class="open">Open in Chrome<kbd></kbd></button>
      <button class="caret" title="Open in…">▾</button>
    </div>
    <div class="menu" hidden></div>`;
  const menu = root.querySelector('.menu');
  const colors = { grey: '#9aa0a6', blue: '#8ab4f8', red: '#f28b82', yellow: '#fdd663', green: '#81c995',
                   pink: '#ff8bcb', purple: '#c58af9', cyan: '#78d9ec', orange: '#fcad70' };
  const move = to => chrome.runtime.sendMessage({ little: 'move', to });

  async function toggleMenu() {
    if (!menu.hidden) return void (menu.hidden = true);
    const targets = await chrome.runtime.sendMessage({ little: 'targets' });
    menu.replaceChildren();
    for (const w of targets) {
      const head = document.createElement('div');
      head.className = 'head';
      head.textContent = w.title;
      const today = document.createElement('button');
      today.textContent = 'New tab';
      today.onclick = () => move({ windowId: w.windowId });
      menu.append(head, today);
      for (const g of w.groups) {
        const b = document.createElement('button');
        const dot = document.createElement('span');
        dot.className = 'dot';
        dot.style.background = colors[g.color] || colors.grey;
        b.append(dot, g.title);
        b.onclick = () => move({ windowId: w.windowId, groupId: g.id });
        menu.append(b);
      }
    }
    menu.hidden = false;
  }

  chrome.runtime.sendMessage({ little: 'shortcuts' }).then(keys => {
    const kbd = root.querySelector('kbd');
    if (keys['little-open']) kbd.textContent = keys['little-open'];
    else kbd.remove();
    if (keys['little-open-in']) root.querySelector('.caret').title = `Open in… (${keys['little-open-in']})`;
  });

  root.querySelector('.open').onclick = () => move();
  root.querySelector('.caret').onclick = toggleMenu;
  chrome.runtime.onMessage.addListener(msg => { if (msg.little === 'menu') toggleMenu(); });
  document.documentElement.append(host);
})();

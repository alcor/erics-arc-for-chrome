// Search box for a blank Little Arc: a URL goes straight there, anything else goes to the default
// search engine (decided in little-arc.js, shared with the bar's address field).
const form = document.querySelector('form');

form.onsubmit = e => {
  e.preventDefault();
  const text = form.q.value.trim();
  if (text) chrome.runtime.sendMessage({ little: 'go', text });
};

addEventListener('keydown', e => { if (e.key === 'Escape') window.close(); });

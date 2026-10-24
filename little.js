// Search box for a blank Little Arc: a URL goes straight there, anything else goes to the default
// search engine.
const form = document.querySelector('form');
const input = form.q;

function asUrl(text) {
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) return text;
  if (/\s/.test(text)) return null;
  if (/^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?(\/|$)/.test(text) || /^[^/]+\.[a-z]{2,}(:\d+)?(\/|$)/i.test(text)) {
    return (text.startsWith('localhost') ? 'http://' : 'https://') + text;
  }
  return null;
}

form.onsubmit = e => {
  e.preventDefault();
  const text = input.value.trim();
  if (!text) return;
  const url = asUrl(text);
  if (url) location.href = url;
  else chrome.search.query({ text, disposition: 'CURRENT_TAB' });
};

addEventListener('keydown', e => { if (e.key === 'Escape') window.close(); });

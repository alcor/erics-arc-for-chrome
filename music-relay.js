// Passes messages between music.js (the page's world) and the extension (player.js).
addEventListener('message', e => {
  if (e.source === window && e.data?.arcMusic !== undefined) chrome.runtime.sendMessage({ music: e.data.arcMusic }).catch(() => {});
});
chrome.runtime.onMessage.addListener(msg => {
  if (msg.musicAction) postMessage({ arcMusicAction: msg.musicAction }, location.origin);
});

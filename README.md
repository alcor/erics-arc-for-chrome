# Eric's Arc for Chrome

Arc features for Chrome, working on Chrome's built-in (vertical) tab bar. No sidebar, no extra window.

## Install

1. `chrome://extensions` → turn on **Developer mode**
2. **Load unpacked** → pick this folder
3. After pulling changes, hit the reload icon on the extension card

## Features

### Locked tabs: pinned tabs and the CoreCore group

Pinned tabs, and tabs in the `CoreCore` tab group, remember the URL they had when they got locked, like Arc's Favorites and pinned tabs. Locked groups are listed in `LOCKED_GROUPS` in `background.js`.

- **Close it** (⌘W, middle-click): it comes back in the same spot at its locked URL. Unpin it, or drag it out of the group, to really close it.
- **⌘W** is handled by the extension, which skips Chrome's "press ⌘W again to close the pinned tab" toast. Chrome has no setting for that toast.
- **⌃R** or the toolbar button: reset current locked tab in place
- **Replace pinned URL with current**: no default key, set one in `chrome://extensions/shortcuts`

Locked URLs survive restarts by matching tabs in order, per pinned area and per group. If Chrome restores them in a different order, use "Replace pinned URL with current" or re-lock. Closing a whole window that has locked tabs, then quitting, can shift them by one.

## Test

```bash
npm install && npx playwright-core install chromium && npm test
```

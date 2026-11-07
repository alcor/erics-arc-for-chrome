# Monochrome

Locked tabs, new tabs at the top, ⌃Tab by recent use with a thumbnail switcher, throwaway mini browsers, peek browsers for links from locked tabs, profile hotkeys and a mini player over the tab sidebar, for Google Chrome on macOS. These are the Arc features it ports. Chrome's own vertical tab bar is the sidebar; nothing is added to the window.

## Summary

Two parts. A Chrome extension, loaded unpacked from this folder, does what an extension can: locked tabs, tab order, the recent-tab list, mini and peek browser windows, the music hooks. A Mac app, Monochrome, built from `helper/`, reads ⌃Tab and the other hotkeys through an event tap, draws the switcher, the mini browser bar, the peek shade, the profile HUD and the mini player as panels over Chrome, starts Chrome with its launch flags from the Dock and at login, and is the default browser so links from other apps reach the extension without passing through the main window. Every extension feature except ⌥⌘-click has a fallback for when the app is not running.

Setup is `setup.sh`, one Accessibility grant, three Chrome settings and one unpacked load per profile. Uninstall is `uninstall.sh`.

## What this is not

It does not touch Chrome's data folder, sync, or passwords. It does not replace the tab bar, the address bar or the New Tab page. The helper opens no pages itself. The migration script is the one exception, described under Setup, and it runs once.

## Shortcuts

| Keys | Effect | Handled by |
|---|---|---|
| ⌃Tab, ⌃⇧Tab | Last used tab in this window. Hold ⌃ for the switcher; release to pick; Esc cancels | Monochrome; extension commands as fallback |
| ⌃R | Reset the current locked tab to its locked URL | extension command |
| ⌘W, middle-click | Close. A locked tab comes back at its locked URL | Chrome; ⌘W optionally the extension |
| ⌥⇧N, from any app | New mini browser | Monochrome; extension command as fallback |
| ⌥⌘-click | Open the link in a mini browser | Monochrome only |
| ⌘L, in a mini browser | Address field, URL selected. Enter goes; Esc closes the field | Monochrome; in-page bar as fallback |
| ⌘O, ⇧⌘O, in a mini browser | Move it into Chrome as a tab; pick the window or tab group | Monochrome; extension commands as fallback |
| Esc, in a mini browser | Close it | extension |
| ⌃⌥→, ⌃⌥← | Next, previous Chrome profile | Monochrome |
| ⌃⌥1 to ⌃⌥9 | Profile by its place in Chrome's Profiles menu | Monochrome |
| ⌘S | Collapse or show the vertical tab bar | `setup.sh`, as a macOS App Shortcut |
| ⇧⌘S | Save Page As, moved off ⌘S | `setup.sh` |
| ⌥⌘↓, ⌥⌘↑ | Next, previous tab in the list | `setup.sh` |

Hotkeys are resolved through the active keyboard layout: ⌥⇧N is the key that types N, on Dvorak as on QWERTY (`helper/Keyboard.swift`).

## Setup

Requires Google Chrome, git and the Xcode command line tools (`xcode-select --install`).

1. Clone to a permanent folder. Chrome loads the extension from it, so not Downloads.

   ```bash
   git clone https://github.com/alcor/monochrome.git ~/Code/monochrome
   ```

2. Run the setup. It writes the Chrome App Shortcuts, builds and installs `~/Applications/Monochrome.app` as a login item with a Dock tile in Chrome's place, registers it as the extension's native messaging host and asks macOS to make it the default browser. Re-running is safe.

   ```bash
   ~/Code/monochrome/setup.sh
   ```

3. Allow Accessibility when Monochrome asks: System Settings → Privacy & Security (Device Control and Data Access on newer macOS) → Accessibility → Monochrome. The app is signed with a certificate from the keychain, a Developer ID or Apple Development one, so the grant survives rebuilds; `MONOCHROME_SIGN_IDENTITY` picks one by name, and the choice is remembered. With no certificate the build is ad-hoc signed, macOS treats each rebuild as a new app, and the setup resets the stale grant so the app can ask again.

4. Quit Chrome and open it from the Monochrome tile in the Dock. That start carries the launch flags. Chrome started any other way runs without them and Monochrome posts a notification saying so.

5. In Chrome: right-click the tab bar → Show Tabs Vertically. Settings → On startup → Continue where you left off. `chrome://flags/#browser-initiated-automatic-picture-in-picture` → Enabled, for video that pops out when its tab is left.

6. Load the extension in each profile: `chrome://extensions` → Developer mode → Load unpacked → this folder. Loading from the same folder in every profile keeps one extension ID, which is what the helper's registration names. After pulling changes, click reload on the extension's card; Chrome does not re-read an unpacked extension on relaunch.

7. Pin the tabs that should be locked, and put everyday tabs in a tab group named `CoreCore`. The group name is `LOCKED_GROUPS` in `background.js`.

8. Optional, once: `migrate/arc-to-chrome.sh` merges Arc's last 90 days of history and its form autofill into Chrome, backing up both databases first. It quits and reopens Chrome.

The extension's fallback commands are in `chrome://extensions/shortcuts`. Chrome pre-fills ⌃R, ⌃., ⌃⇧. and ⌃, on a fresh load. ⌥⇧N (scope Global), ⌘O and ⇧⌘O have no defaults and matter only when Monochrome is not running.

## Locked tabs come back when closed

A pinned tab, or a tab in a `CoreCore` group, remembers the URL it had when it was locked. Closing it reopens it in place at that URL; unpinning it or dragging it out of the group closes it for good. ⌃R resets it in place. The command "Replace pinned URL with current" makes the current page the locked URL.

Locked URLs survive a restart by position: tabs are matched in order within the pinned area and within each group. When Chrome restores them in another order, the URLs land on the wrong tabs, and the fix is to re-lock or replace. Closing a window with locked tabs and then quitting is the known way to shift them by one.

## New tabs open at the top

A new tab lands directly under the locked tabs, including ⌘T and a mini browser moved into Chrome. A link opened in a new tab from an ordinary tab lands after that tab. From a locked tab, a background link (⌘-click) goes to the top without joining the group, and a foreground link becomes a peek browser. Other groups and session restore are not reordered.

## ⌃Tab walks tabs by recent use, per window

The first ⌃Tab goes to the tab last used in the front window. Holding ⌃ shows the switcher: the five most recent tabs of that window, most recent first, each as a thumbnail with favicon and title, ⌘Tab's selection style on a glass surface. ⌃Tab moves the selection on, ⌃⇧Tab back, both wrapping; Esc cancels; releasing ⌃ goes to the selection. A tap-and-release never shows the switcher. Only the tab landed on counts as used, so ⌃Tab twice returns to the starting tab. A link opened in a background tab is next in line.

Chrome gives extensions no Tab key, no ⌃-release event and no way to draw over the window, so the event tap in `helper/Tap.swift` takes ⌃Tab while Chrome is in front and `helper/Switcher.swift` draws the panel. The extension supplies the recent-tab list and thumbnails (`helper.js`): a thumbnail is captured when a tab comes to the front, when it finishes loading and after a scroll the tap reports, and lives only in the app's memory. Restored tabs have none until visited; `chrome://` pages never do.

Without the app connected, the tap rewrites the keys to the extension's commands (first ⌃Tab to ⌃., further ones to ⌃⇧., ⌃⇧Tab to ⌃,) and the extension switches live with no switcher. Without the app at all, Chrome's own ⌃Tab applies.

## Mini browsers are Chrome popup windows

A mini browser is a popup window: no tab strip, no sidebar, ⌘[ for back. Size and position are remembered. One left unfocused for 12 hours closes itself.

- ⌥⇧N from any app opens one with a search box; a URL or a search in Chrome's default engine, then Enter.
- A link from another app opens one. Monochrome is the default browser, so the link reaches the app and the app asks the extension to open the window directly. Monochrome is the default browser and opens nothing itself. When the extension is not connected, the app hands the link to Chrome, where it shows in the main window briefly before becoming a mini browser.
- ⌥⌘-click on any page opens the link in one. The tap sees the click; there is no fallback.
- The bar, top right over the title bar, is a glass panel of the app: a link button or ⌘L for the address field, Open in Chrome or ⌘O to move the page into the main window, a caret or ⇧⌘O for the list of windows and groups, each window named by its active tab. The bar hides while the window is dragged and while the mini browser is not the key window. Without the app, the same bar is drawn inside the page.

## Peek browsers catch links from locked tabs

A link from a locked tab that would open a new tab opens as a mini browser over the window, with the window behind it shaded. A click on the shade or on another window closes it; ⌘O keeps the page as a tab. The shade is a panel the size of the parent window, ordered directly below the peek browser, and fades in.

The catch is two scripts the extension injects into locked tabs only (`peek-click.js`, `peek-open.js`): links with `target="_blank"` and calls to the page's `window.open` are taken before Chrome makes a tab, so the main window never shows the page. Anything else that opens a tab from a locked tab, a form post for one, passes through the main window first and is visible for a moment. No other page gets a content script, apart from the music sites below.

## Profiles switch through Chrome's own menu

⌃⌥→ and ⌃⌥← go to the next and previous profile, ⌃⌥1 to 9 to one by position. The app reads Chrome's Profiles menu over Accessibility and presses the item (`helper/Profiles.swift`), so this works in a profile without the extension; every other feature needs the extension loaded there. A HUD shows the profiles as initials on a color derived from the name, the chosen one marked, for 1.2 seconds. The menu carries no avatar images, which is why initials.

## The mini player sits on the tab sidebar

When a music tab has a track loaded and another tab is in front, a panel at the bottom of the sidebar shows artwork, title, artist and transport controls; clicking the track goes to its tab, and the close button hides it until the music tab has been visited and left again. It hides when the music tab is in front, when the sidebar is collapsed and when Chrome is not frontmost. On these sites the extension also stops Chrome's own pop-out player when the tab is left. Sites: Spotify, YouTube Music, SoundCloud, Apple Music, Tidal, Bandcamp, Pandora, Amazon Music, Deezer. Adding one is two entries in `manifest.json`, `music.js` and `music-relay.js`.

The panel is the app's (`helper/Player.swift`), because an extension cannot draw in the tab strip. It covers the last tabs of a long list and trails the window during a drag.

## The address bar opens the matching page from history

Typing words and pressing Enter opens the history entry that matches them rather than a search. Chrome allows this only with `--enable-features=OmniboxForceAllowedToBeDefault`, which is not on `chrome://flags`, so the app passes it when it starts Chrome. A search made before for the same words can still outrank the page. The flag list is `features` in `helper/Chrome.swift`; a change takes effect after `helper/install.sh` and a restart from the Dock.

## The helper is one binary in two roles

`helper/install.sh` compiles the Swift in `helper/` into `~/Applications/Monochrome.app`. Run as the app, it registers itself as a login item, owns the event tap and every panel, the Dock tile and the default-browser role. Run as `--host`, which is what Chrome spawns for the extension's native messaging host, it relays between the extension's port and the app over a Unix socket in `~/Library/Application Support/Monochrome` and pings the extension every 20 seconds so Chrome does not stop the service worker for idleness. Each Chrome profile gets its own host process and connection; the app routes tab actions to the connection that owns the tab and front-window actions to the connection whose reported front window matches Chrome's.

`Monochrome --status` prints the layout's keycodes, whether the app is running and whether the socket exists. Logs go to the unified log under subsystem `local.monochrome`:

```bash
/usr/bin/log stream --info --predicate 'subsystem == "local.monochrome"'
```

## Uninstall

```bash
~/Code/monochrome/uninstall.sh
```

It removes the app, its login item, Dock tile, support folder and host registration, this project's App Shortcuts, and what earlier versions installed: Chrome Launcher and a Karabiner rule. Karabiner itself and other App Shortcuts stay. Then remove the extension in `chrome://extensions`, restart Chrome, and choose Chrome as the default browser in System Settings → Desktop & Dock.

## Tests

```bash
npm install && npx playwright-core install chromium && npm test
```

The suite drives headless Chromium with the extension loaded and spawns the built helper in host mode against a private socket. `HEADFUL=1 npm test` adds the link hand-off from another app, which headless Chromium cannot receive.

## Not verified

I am an automated contributor and this is what I did not exercise by hand: two profiles connected to the app at once; dragging a peek browser with its shade; a profile switch by hotkey beyond reading the menu; whether Chrome matches the ⌃. and ⌃, fallback commands by typed character or by key position on Dvorak; and whether reading Chrome's menu bar over Accessibility changes Chrome's own accessibility mode.

## What would change this design

A Chrome API for the Tab key, for drawing over the window, or for native panels in the tab strip would remove the app's reason to exist for the switcher and player. Native messaging that Chrome could initiate would remove the 20-second ping. Avatar images in the Profiles menu, or a sanctioned way to read the profile list, would replace the initials.

Until then, the extension does the bookkeeping and the app does the drawing, and either runs without the other.

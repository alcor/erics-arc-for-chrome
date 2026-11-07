# Chrome Web Store listing

Everything the developer dashboard asks for, in the order its pages ask. The extension package is `store/pack.sh`'s zip in `dist/`; the app's zip on the release is `ditto -c -k --keepParent helper/build/Monochrome.app dist/Monochrome-app-<version>.zip` after `helper/install.sh` has built and signed it.

## Store listing

**Name:** Monochrome

**Summary** (from the manifest, 119 of 132 characters): Locked tabs, new tabs at the top, a ⌃Tab switcher with thumbnails, mini and peek browsers, and link routing for Chrome.

**Category:** Productivity › Workflow & Planning

**Language:** English

**Description:**

Tabs that come back. Pin a tab, or put it in your locked group, and closing it brings it back where it was, on the page you chose.

⌃Tab the way you remember it. Hold Control and step through the tabs you used last, newest first. With the free Monochrome app for Mac (github.com/alcor/monochrome/releases), you see them as thumbnails.

Windows for a quick look. ⌥⇧N opens a small browser from any app. Links from Slack and Mail open in one too, and one click moves the page into Chrome when it's worth keeping.

Links that know where to go. With the app, rules send each link to the right profile, tab group, or app.

Works with Chrome's vertical tabs. Nothing is added to the window, and nothing leaves your Mac.

**Icon:** `icons/128.png`

**Screenshots** (1280×800 JPEG), in order: `store/screenshots/1-switcher.jpg`, `2-profiles.jpg`, `3-router.jpg`, made with `Monochrome --demo --backdrop`, `--demo-profiles --backdrop` and `--demo-settings --backdrop`

**Small promo tile** (440×280): `store/screenshots/small-tile.jpg`; **marquee** (1400×560): `store/screenshots/marquee-tile.jpg`, both from `swift store/tiles.swift`

**Homepage URL:** https://github.com/alcor/monochrome

**Support URL:** https://github.com/alcor/monochrome/issues

## Privacy practices

**Single purpose:** Monochrome changes how Chrome's tabs behave: which tabs come back when closed, where new tabs go, how ⌃Tab orders them, and how links from other apps and from locked tabs open. Every feature is a tab behavior; none reads or changes page content.

**Permission justifications:**

- `tabs`: read tab addresses and titles to keep locked tabs at their address, order new tabs, walk tabs by recent use, and name windows for the mini browser's picker.
- `tabGroups`: recognize the locked group by title, put tabs back into it, and offer groups as places to move a mini browser's page.
- `storage`: keep locked addresses, the recent-tab order, the mini browser size and the locked group's title on the user's computer.
- `webNavigation`: notice a navigation in a locked tab, to re-apply the peek catch in that tab's frames, and notice a link handed to Chrome by another app, to open it as a mini browser.
- `scripting`: inject the peek catch into locked tabs only, and the fallback bar and shade into mini browser pages when the companion app is not running.
- `search`: run what the user types in a mini browser's box through their default search engine.
- `alarms`: reconnect to the companion app and close mini browsers left unused for 12 hours while the service worker is otherwise idle.
- `nativeMessaging`: talk to the Monochrome app on the user's Mac, which draws the switcher, bars and player, and routes links. The extension works without it.
- `favicon`: show site icons in the switcher and the mini browser bar.
- Host permission `<all_urls>`: capture a scaled-down picture of the tab in front for the switcher's thumbnails, which happens on activation without a click, and inject the peek catch into locked tabs on any site. No page content is read or stored; the picture is kept in the companion app's memory only.

**Remote code:** No.

**Data usage:** The extension does not collect or transmit user data. Tab addresses, titles and a picture of the front tab are passed to a companion app on the same computer over Chrome's native messaging port and are not sent anywhere else. Certify: not sold, not used for unrelated purposes, not used for creditworthiness.

**Privacy policy URL:** https://artifact.com/privacy?Monochrome, the shared policy for Artifact apps with no tracking and no server; `docs/privacy.md` is the detailed statement for this one.

## Distribution

**Visibility:** Unlisted, until the companion app has a release page to link to.

**Regions:** All.

**Pricing:** Free.

## Test instructions

No account or sign-in. The extension works on its own for locked tabs, new tabs at the top, ⌃Tab by recent use and mini browsers; the rest of the features need the free Monochrome app for macOS running alongside it.

```
No account is needed. The extension works on its own: pin a tab and close it to see it come back; press ⌃. to go to the tab you used last; set a shortcut for "New mini browser" under chrome://extensions/shortcuts to open a small window.

The thumbnail switcher, the bar on mini browsers, the peek shade, profile switching and link routing come from a companion macOS app, Monochrome, which talks to the extension over native messaging. To test those, on a Mac: download Monochrome.app from https://github.com/alcor/monochrome/releases/latest, move it to Applications and open it (it is signed with a development certificate and not notarized, so the first open is right-click, Open), allow Accessibility when it asks, and quit and reopen Chrome from the app's Dock icon. Then hold Control after pressing ⌃Tab for the switcher, and press ⌥⇧N from any app for a mini browser with a native bar.

Without the app, everything the app would draw is simply absent; nothing in the extension errors or asks for it.
```

## Before submitting

- After the first upload, install the store's copy once and run `store/adopt-key.sh <id>` so the unpacked extension takes the store's ID.

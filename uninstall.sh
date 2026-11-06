#!/bin/sh
# Undoes setup.sh: removes the helper app (login item, Dock icon, Chrome registration, the app itself),
# this project's Chrome App Shortcuts (other App Shortcuts stay), and anything left from earlier
# versions (Chrome Launcher, the Karabiner rule; Karabiner itself stays installed).
# The extension is removed by hand in chrome://extensions. If the helper was your default browser,
# macOS falls back to asking next time a link is opened; pick Chrome in System Settings → Desktop & Dock.
set -eu
app="$HOME/Applications/Arc for Chrome.app"
hosts="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

[ -d "$app" ] && open -W -a "$app" --args --unregister 2>/dev/null || true
osascript -e 'tell application id "local.arc-for-chrome.helper" to quit' >/dev/null 2>&1 || true
pkill -x ArcHelper 2>/dev/null || true
rm -rf "$app" "$HOME/Library/Application Support/Arc for Chrome"
rm -f "$hosts/erics_arc_helper.json" "$hosts/erics_arc_player.json"

launcher_agent="$HOME/Library/LaunchAgents/local.arc-for-chrome.launcher.plist"
launchctl bootout "gui/$(id -u)" "$launcher_agent" 2>/dev/null || true
rm -rf "$HOME/Applications/Chrome Launcher.app" "$launcher_agent"

python3 -I - <<'EOF'
import json, os, plistlib, subprocess

def edit_defaults(domain, change):
    raw = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True, check=True).stdout
    prefs = plistlib.loads(raw)
    if change(prefs):
        subprocess.run(['defaults', 'import', domain, '-'], input=plistlib.dumps(prefs), check=True)

def drop_dock_tile(dock):
    tiles = dock.get('persistent-apps', [])
    keep = [t for t in tiles if t.get('tile-data', {}).get('file-label') not in ('Chrome Launcher', 'Arc for Chrome')]
    dock['persistent-apps'] = keep
    return len(keep) != len(tiles)

def drop_chrome_prefs(chrome):
    keys = chrome.get('NSUserKeyEquivalents', {})
    removed = [k for k in ('Collapse Vertical Tabs', 'Save Page As…', 'Select Next Tab', 'Select Previous Tab') if keys.pop(k, None) is not None]
    return bool(removed) | (chrome.pop('DefaultBrowserSettingEnabled', None) is not None)

edit_defaults('com.apple.dock', drop_dock_tile)
edit_defaults('com.google.Chrome', drop_chrome_prefs)

path = os.path.expanduser('~/.config/karabiner/karabiner.json')
if os.path.exists(path):
    cfg = json.load(open(path))
    for p in cfg.get('profiles', []):
        rules = p.get('complex_modifications', {}).get('rules')
        if rules is not None:
            rules[:] = [r for r in rules if not r.get('description', '').startswith('Chrome: Ctrl+Tab / Ctrl+Shift+Tab')]
    with open(path + '.tmp', 'w') as f:
        json.dump(cfg, f, indent=2)
    os.replace(path + '.tmp', path)
EOF
rm -f "$HOME/.config/karabiner/assets/complex_modifications/arc-for-chrome.json"
killall Dock
echo "Uninstalled. Remove the extension in chrome://extensions; quit and reopen Chrome to drop its launch flags."

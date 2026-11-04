#!/bin/sh
# Undoes setup.sh: removes Chrome Launcher (app, login item, Dock icon), the mini player's Chrome
# registration, this project's Chrome App Shortcuts (other App Shortcuts stay), and its Karabiner rule
# (Karabiner itself stays installed).
# The extension is removed by hand in chrome://extensions.
set -eu
app="$HOME/Applications/Chrome Launcher.app"
agent="$HOME/Library/LaunchAgents/local.arc-for-chrome.launcher.plist"

launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
rm -rf "$app" "$agent"
rm -f "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/erics_arc_player.json"

python3 -I - <<'EOF'
import json, os, plistlib, subprocess

def edit_defaults(domain, change):
    raw = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True, check=True).stdout
    prefs = plistlib.loads(raw)
    if change(prefs):
        subprocess.run(['defaults', 'import', domain, '-'], input=plistlib.dumps(prefs), check=True)

def drop_dock_tile(dock):
    tiles = dock.get('persistent-apps', [])
    keep = [t for t in tiles if t.get('tile-data', {}).get('file-label') != 'Chrome Launcher']
    dock['persistent-apps'] = keep
    return len(keep) != len(tiles)

def drop_app_shortcuts(chrome):
    keys = chrome.get('NSUserKeyEquivalents', {})
    removed = [k for k in ('Collapse Vertical Tabs', 'Save Page As…', 'Select Next Tab', 'Select Previous Tab') if keys.pop(k, None) is not None]
    return bool(removed)

edit_defaults('com.apple.dock', drop_dock_tile)
edit_defaults('com.google.Chrome', drop_app_shortcuts)

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

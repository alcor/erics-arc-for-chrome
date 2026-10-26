#!/bin/sh
# Sets up everything on this Mac that can be scripted. Safe to re-run. The README lists the steps
# that need clicks (loading the extension, its shortcuts, Karabiner's driver approval).
set -eu
here=$(cd "$(dirname "$0")" && pwd)

[ -d "/Applications/Google Chrome.app" ] || { echo "Install Google Chrome first: https://www.google.com/chrome/"; exit 1; }

# 1. Chrome menu shortcuts (macOS App Shortcuts): ⌘S collapses/expands the vertical tab sidebar like
#    Arc; Save Page As moves to ⇧⌘S so the two don't clash; ⌃⌘↓ / ⌃⌘↑ move down / up the tab list.
#    Takes effect next time Chrome starts. (\357\234\201 and \357\234\200 are the UTF-8 for the
#    down/up arrow key characters, U+F701 / U+F700.)
defaults write com.google.Chrome NSUserKeyEquivalents -dict-add \
  "Collapse Vertical Tabs" "@s" \
  "Save Page As…" '@$s' \
  "Select Next Tab" "$(printf '@^\357\234\201')" \
  "Select Previous Tab" "$(printf '@^\357\234\200')"
echo "chrome menu shortcuts: set"

# 2. Karabiner-Elements, which turns ⌃Tab / ⌃⇧Tab into keys the extension can use (Chrome only).
if [ ! -d "/Applications/Karabiner-Elements.app" ]; then
  command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
  brew install --cask karabiner-elements
fi
mkdir -p "$HOME/.config/karabiner/assets/complex_modifications"
cp "$here/karabiner/ctrl-tab.json" "$HOME/.config/karabiner/assets/complex_modifications/arc-for-chrome.json"
python3 -I - "$here/karabiner/ctrl-tab.json" "$HOME/.config/karabiner/karabiner.json" <<'EOF'
import json, os, shutil, sys, time
rules = json.load(open(sys.argv[1]))['rules']
path = sys.argv[2]
if os.path.exists(path):
    cfg = json.load(open(path))
    shutil.copy2(path, f'{path}.bak-{time.strftime("%Y%m%d-%H%M%S")}')
else:
    cfg = {'profiles': [{'name': 'Default profile', 'selected': True}]}
profile = next((p for p in cfg['profiles'] if p.get('selected')), cfg['profiles'][0])
mods = profile.setdefault('complex_modifications', {}).setdefault('rules', [])
names = {r['description'] for r in rules}
mods[:] = [r for r in mods if r.get('description') not in names] + rules
# Write a sibling file, then rename over the original, so an interruption can't leave half a config.
with open(path + '.tmp', 'w') as f:
    json.dump(cfg, f, indent=2)
os.replace(path + '.tmp', path)
print('karabiner rule: installed in profile', repr(profile['name']))
EOF

# 3. Chrome Launcher: starts Chrome with the launch flags, at login and from the Dock.
"$here/launcher/install.sh"

cat <<'EOF'

Done with the scripted part. Continue with step 3 of "Set up on a new Mac" in README.md:
approve Karabiner's driver, reopen Chrome from Chrome Launcher, load the extension, set its shortcuts.
EOF

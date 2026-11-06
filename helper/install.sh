#!/bin/sh
# Builds Arc for Chrome.app from the Swift here, installs it to ~/Applications, registers it with Chrome
# as the extension's native messaging host, and puts it in the Dock in place of Google Chrome (wearing
# Chrome's icon, so opening Chrome goes through it and gets its launch flags). Needs the Xcode command
# line tools. Safe to re-run; re-run after moving the repo, since the extension's ID comes from its folder.
#
# Signing: macOS ties the Accessibility grant (for the ⌃Tab tap) to the app's signature. Signed with a
# Developer ID, that's the team and bundle id and survives rebuilds; ad-hoc signed, it's a hash of the
# binary and every rebuild has to be allowed again in System Settings.
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
name="Arc for Chrome"
build="$here/build/$name.app"
app="$HOME/Applications/$name.app"
bundle_id="local.arc-for-chrome.helper"
host="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/erics_arc_helper.json"

swiftc --version >/dev/null 2>&1 || { echo "helper: needs the command line tools: xcode-select --install"; exit 1; }
[ -d "/Applications/Google Chrome.app" ] || { echo "Install Google Chrome first: https://www.google.com/chrome/"; exit 1; }

rm -rf "$build"
mkdir -p "$build/Contents/MacOS" "$build/Contents/Resources"
swiftc -O -o "$build/Contents/MacOS/ArcHelper" "$here"/*.swift
cp "$here/Info.plist" "$build/Contents/Info.plist"
cp "$here/host.sh" "$build/Contents/Resources/host.sh"
chmod +x "$build/Contents/Resources/host.sh"
cp "/Applications/Google Chrome.app/Contents/Resources/app.icns" "$build/Contents/Resources/AppIcon.icns"
identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
codesign --force --deep --sign "${identity:--}" "$build"
echo "helper: built, signed ${identity:+with $identity}${identity:-ad hoc (Accessibility has to be allowed again after each rebuild)}"

# Replace the installed copy. A running one is quit first so the new one is what starts.
osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
pkill -x ArcHelper 2>/dev/null || true
sleep 0.5
mkdir -p "$HOME/Applications"
rm -rf "$app"
cp -R "$build" "$app"

# An unpacked extension's ID is the first 32 hex digits of its folder path's SHA-256, written with a-p for 0-f.
id=$(printf %s "$(dirname "$here")" | shasum -a 256 | head -c 32 | tr 0-9a-f a-p)
mkdir -p "$(dirname "$host")"
python3 -I - "$host" "$app/Contents/Resources/host.sh" "$id" <<'EOF'
import json, sys
host, path, id = sys.argv[1:]
with open(host, 'w') as f:
    json.dump({'name': 'erics_arc_helper', 'description': "Eric's Arc for Chrome: helper app",
               'path': path, 'type': 'stdio', 'allowed_origins': [f'chrome-extension://{id}/']}, f, indent=2)
EOF
rm -f "$(dirname "$host")/erics_arc_player.json"
echo "helper: registered with Chrome for extension $id"

# Dock: swap a pinned Google Chrome icon (which would start Chrome without the flags) for the helper.
dock_bak="$HOME/Library/Preferences/com.apple.dock.plist.pre-arc-for-chrome.bak"
[ -e "$dock_bak" ] || cp "$HOME/Library/Preferences/com.apple.dock.plist" "$dock_bak"
# The Dock drops icons for apps macOS hasn't registered yet, and the app was just rebuilt.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
python3 -I - "$name" <<'EOF'
import plistlib, subprocess, sys
name = sys.argv[1]
raw = subprocess.run(['defaults', 'export', 'com.apple.dock', '-'], capture_output=True, check=True).stdout
dock = plistlib.loads(raw)
tiles = dock.get('persistent-apps', [])
keep = [t for t in tiles if t.get('tile-data', {}).get('bundle-identifier') != 'com.google.Chrome'
        and t.get('tile-data', {}).get('file-label') not in ('Chrome Launcher', name)]
if len(keep) != len(tiles):
    dock['persistent-apps'] = keep
    subprocess.run(['defaults', 'import', 'com.apple.dock', '-'], input=plistlib.dumps(dock), check=True)
EOF
in_dock() { defaults read com.apple.dock persistent-apps | grep -q "\"file-label\" = \"$name\""; }
# A Dock that restarted in the last few seconds writes its old icons back over the change, so wait
# until it has been up a while before each attempt, then check.
wait_for_settled_dock() {
  # etime is [[dd-]hh:]mm:ss; only mm:ss can be under 15 seconds.
  up=$(ps -o etime= -p "$(pgrep -x Dock | head -1)" 2>/dev/null | tr -d ' ' | awk -F: 'NF == 2 { print $1 * 60 + $2; next } { print 999 }')
  [ "${up:-99}" -lt 15 ] && sleep $((15 - up))
  return 0
}
for attempt in 1 2 3 4 5; do
  wait_for_settled_dock
  in_dock || defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$app</string><key>_CFURLStringType</key><integer>0</integer></dict><key>file-label</key><string>$name</string></dict><key>tile-type</key><string>file-tile</string></dict>"
  killall Dock
  sleep 3
  in_dock && break
done
if in_dock; then echo "dock: $name icon in place"; else echo "dock: icon didn't stick; drag $app into the Dock"; fi

open "$app"
echo "installed: $app (allow it under System Settings → Privacy & Security → Accessibility when asked)"

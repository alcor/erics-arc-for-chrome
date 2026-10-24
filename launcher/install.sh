#!/bin/sh
# Installs ~/Applications/Chrome Launcher.app (runs chrome-launcher.sh, wears Chrome's icon), a login
# item that starts Chrome through it, and points the Dock's Chrome icon at it. Safe to re-run.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
app="$HOME/Applications/Chrome Launcher.app"
agent="$HOME/Library/LaunchAgents/local.arc-for-chrome.launcher.plist"

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$app"
osacompile -o "$app" -e 'do shell script quoted form of (POSIX path of (path to resource "chrome-launcher.sh"))'
cp "$here/chrome-launcher.sh" "$app/Contents/Resources/chrome-launcher.sh"
chmod +x "$app/Contents/Resources/chrome-launcher.sh"
cp "/Applications/Google Chrome.app/Contents/Resources/app.icns" "$app/Contents/Resources/applet.icns"
rm -f "$app/Contents/Resources/Assets.car" # else its script icon wins over applet.icns
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$app/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.arc-for-chrome.launcher" "$app/Contents/Info.plist" 2>/dev/null ||
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string local.arc-for-chrome.launcher" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$app/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep --sign - "$app" # edits above break osacompile's ad-hoc signature
touch "$app"

cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.arc-for-chrome.launcher</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>$app</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF

# Dock: swap a pinned Google Chrome icon (which would start Chrome without the flags) for the launcher.
dock_bak="$HOME/Library/Preferences/com.apple.dock.plist.pre-chrome-launcher.bak"
[ -e "$dock_bak" ] || cp "$HOME/Library/Preferences/com.apple.dock.plist" "$dock_bak"
# The Dock drops icons for apps macOS hasn't registered yet, and the app was just rebuilt.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
python3 -I - <<'EOF'
import plistlib, subprocess
raw = subprocess.run(['defaults', 'export', 'com.apple.dock', '-'], capture_output=True, check=True).stdout
dock = plistlib.loads(raw)
tiles = dock.get('persistent-apps', [])
keep = [t for t in tiles if t.get('tile-data', {}).get('bundle-identifier') != 'com.google.Chrome'
        and t.get('tile-data', {}).get('file-label') != 'Chrome Launcher']
if len(keep) != len(tiles):
    dock['persistent-apps'] = keep
    subprocess.run(['defaults', 'import', 'com.apple.dock', '-'], input=plistlib.dumps(dock), check=True)
EOF
# A Dock that restarted in the last few seconds writes its old icons back over the change, so wait
# until it has been up a while before each attempt, then check.
in_dock() { defaults read com.apple.dock persistent-apps | grep -q '"file-label" = "Chrome Launcher"'; }
wait_for_settled_dock() {
  # etime is [[dd-]hh:]mm:ss; only mm:ss can be under 15 seconds.
  up=$(ps -o etime= -p "$(pgrep -x Dock | head -1)" 2>/dev/null | tr -d ' ' | awk -F: 'NF == 2 { print $1 * 60 + $2; next } { print 999 }')
  [ "${up:-99}" -lt 15 ] && sleep $((15 - up))
  return 0
}
for attempt in 1 2 3 4 5; do
  wait_for_settled_dock
  in_dock || defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$app</string><key>_CFURLStringType</key><integer>0</integer></dict><key>file-label</key><string>Chrome Launcher</string></dict><key>tile-type</key><string>file-tile</string></dict>"
  killall Dock
  sleep 3
  in_dock && break
done
if in_dock; then echo "dock: Chrome Launcher icon in place"; else echo "dock: icon didn't stick; drag ~/Applications/Chrome Launcher.app into the Dock"; fi
echo "installed: $app"

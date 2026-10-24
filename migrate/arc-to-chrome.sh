#!/bin/sh
# One-time move from Arc to Chrome: merges Arc's browsing history (last 90 days, with visit and typed
# counts, so Chrome's address bar ranks those pages like Arc did) and form autocomplete entries into
# Chrome's Default profile. Quits Arc and Chrome, backs up Chrome's databases, merges into copies and
# only swaps them in if both merges succeed, then reopens Chrome.
# Running it twice would count every visit twice, so it leaves a marker and refuses a second run.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
arc="$HOME/Library/Application Support/Arc/User Data/Default"
chrome="$HOME/Library/Application Support/Google/Chrome/Default"
marker="$chrome/.arc-migrated"

[ -f "$arc/History" ] || { echo "No Arc profile at $arc"; exit 1; }
[ -f "$chrome/History" ] || { echo "Open Chrome once first so it creates $chrome"; exit 1; }
[ -e "$marker" ] && { echo "Already migrated ($marker). Delete it to run again."; exit 1; }

quit_app() { # quit_app <name> <process name>
  osascript -e "tell application \"$1\" to quit" 2>/dev/null || true
  i=0
  while pgrep -xq "$2"; do
    i=$((i + 1)); [ $i -gt 30 ] && { echo "$1 didn't quit"; exit 1; }
    sleep 1
  done
}
# Both browsers hold their databases open; with them closed, plain file copies are consistent.
quit_app Arc Arc
quit_app "Google Chrome" "Google Chrome"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/arc" "$tmp/chrome"
for f in History "Web Data"; do
  for suffix in "" -journal -wal; do
    [ -f "$arc/$f$suffix" ] && cp "$arc/$f$suffix" "$tmp/arc/$f$suffix"
    [ -f "$chrome/$f$suffix" ] && cp "$chrome/$f$suffix" "$tmp/chrome/$f$suffix"
  done
done

# -bail stops at the first error, so a failed merge never reaches COMMIT; set -e then stops the script
# before anything touches the real profile.
sqlite3 -bail "$tmp/chrome/History" ".param set :arc '$tmp/arc/History'" ".read '$here/history.sql'"
sqlite3 -bail "$tmp/chrome/Web Data" ".param set :arc '$tmp/arc/Web Data'" ".read '$here/autofill.sql'"
for f in History "Web Data"; do
  sqlite3 -bail "$tmp/chrome/$f" "pragma integrity_check" | grep -qx ok || { echo "$f failed integrity check; nothing changed"; exit 1; }
done

stamp=$(date +%Y%m%d-%H%M%S)
for f in History "Web Data"; do
  cp "$chrome/$f" "$chrome/$f.pre-arc-import.$stamp.bak"
  rm -f "$chrome/$f-journal" "$chrome/$f-wal" "$chrome/$f-shm" # merged copy already includes them
  mv "$tmp/chrome/$f" "$chrome/$f"
done
touch "$marker"
echo "Merged. Backups: $chrome/{History,Web Data}.pre-arc-import.$stamp.bak"

if [ -d "$HOME/Applications/Chrome Launcher.app" ]; then open "$HOME/Applications/Chrome Launcher.app"; else open -a "Google Chrome"; fi

#!/bin/sh
# Starts Chrome with the command-line features its flags page doesn't offer. Chrome only reads these
# at startup, so if it's already running without them, say so instead of silently doing nothing.
#
# OmniboxForceAllowedToBeDefault: lets a history page be the address bar's Enter target even when
# what you typed isn't the start of its address ("acme/commits" -> github.com/acme-corp/app/commits).
FEATURES="OmniboxForceAllowedToBeDefault" # comma-separated

running_features() { # the --enable-features list of the running main Chrome process, one per line
  ps -axo args | grep "Google Chrome.app/Contents/MacOS/Google Chrome" | grep -v -- "--type=" |
    tr ' ' '\n' | sed -n 's/^--enable-features=//p' | tr ',' '\n'
}

if pgrep -xq "Google Chrome"; then
  have=$(running_features)
  for f in $(echo "$FEATURES" | tr ',' ' '); do
    if ! printf '%s\n' "$have" | grep -qx "$f"; then
      osascript -e 'display notification "Quit Chrome (⌘Q) and open it from Chrome Launcher to turn the address-bar fix back on." with title "Chrome is running without its launch flags"'
      break
    fi
  done
  open -a "Google Chrome"
else
  open -a "Google Chrome" --args --enable-features="$FEATURES"
fi

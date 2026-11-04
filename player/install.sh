#!/bin/sh
# Builds the sidebar mini player (ArcPlayer.swift, into this folder) and registers it with Chrome as
# this extension's native messaging host. Needs the Xcode command line tools. Safe to re-run; re-run
# after moving the repo, since the extension's ID comes from its folder.
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
host="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/erics_arc_player.json"

swiftc --version >/dev/null 2>&1 || { echo "mini player: skipped, install the command line tools first: xcode-select --install"; exit 0; }
swiftc -O -o "$here/ArcPlayer" "$here/ArcPlayer.swift"

# An unpacked extension's ID is the first 32 hex digits of its folder path's SHA-256, written with a-p for 0-f.
id=$(printf %s "$(dirname "$here")" | shasum -a 256 | head -c 32 | tr 0-9a-f a-p)
mkdir -p "$(dirname "$host")"
python3 -I - "$host" "$here/ArcPlayer" "$id" <<'EOF'
import json, sys
host, path, id = sys.argv[1:]
with open(host, 'w') as f:
    json.dump({'name': 'erics_arc_player', 'description': "Eric's Arc for Chrome: sidebar mini player",
               'path': path, 'type': 'stdio', 'allowed_origins': [f'chrome-extension://{id}/']}, f, indent=2)
EOF
echo "mini player: built and registered for extension $id"

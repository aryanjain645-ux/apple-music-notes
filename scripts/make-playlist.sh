#!/bin/bash
# Create an Apple Music playlist from Music persistent IDs, in the order given.
# Usage: scripts/make-playlist.sh "Sunset set" 1A2B3C4D5E6F7A8B 9C8D...
set -euo pipefail
if [ $# -lt 2 ]; then
  echo "usage: $0 \"Playlist name\" <persistent_id>..." >&2
  exit 1
fi

osascript - "$@" <<'EOF'
on run argv
  set pname to item 1 of argv
  set added to 0
  set missingIDs to {}
  tell application "Music"
    set p to make new user playlist with properties {name:pname}
    repeat with i from 2 to count of argv
      set pid to item i of argv
      try
        duplicate (first track of library playlist 1 whose persistent ID is pid) to p
        set added to added + 1
      on error
        set end of missingIDs to pid
      end try
    end repeat
  end tell
  set msg to "Created \"" & pname & "\" with " & added & " tracks."
  if (count of missingIDs) > 0 then
    set AppleScript's text item delimiters to ", "
    set msg to msg & " Not in library (skipped): " & (missingIDs as text)
  end if
  return msg
end run
EOF

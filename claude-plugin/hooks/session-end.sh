#!/bin/sh
# Tells seshka that this session has ended, by leaving an empty file named after the session where
# seshka looks. Nothing else: what to do about it is seshka's decision, by the user's own settings.
# A hook has a moment to run as Claude Code closes, so it does no more than this.
input=$(cat)
field() { printf '%s' "$input" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }

# After /clear and --resume the same Claude Code process goes on under another session. Nothing ended.
case "$(field reason)" in clear | resume) exit 0 ;; esac

session=$(field session_id)
# Only what a session ID looks like becomes a file name.
case "$session" in "" | *[!0-9a-fA-F-]*) exit 0 ;; esac

folder="$HOME/Library/Application Support/Seshka/ended"
mkdir -p "$folder" && : > "$folder/$session"
exit 0

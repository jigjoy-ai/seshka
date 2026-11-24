#!/bin/sh
# Tells Claude, as a session starts, what earlier sessions left running in the folder it starts in:
# a dev server that still holds its port, a watcher, a database. What this prints goes into the
# session's context. It prints nothing when there is nothing, or when seshka is not running.
input=$(cat)
folder=$(printf '%s' "$input" | /usr/bin/plutil -extract cwd raw -o - - 2>/dev/null)
[ -n "$folder" ] || exit 0

# seshka writes this after every scan, one process a line: its folder, a tab, the process in words.
list="$HOME/Library/Application Support/Seshka/leftovers.tsv"
# Older than ten minutes means seshka is not running, and the list is no longer true.
[ -n "$(/usr/bin/find "$list" -mmin -10 2>/dev/null)" ] || exit 0

/usr/bin/awk -F'\t' -v folder="$folder" '
    $1 == folder || index($1, folder "/") == 1 { count++; lines = lines "\n- " $2 }
    END {
        if (!count) exit
        print "seshka: " count (count == 1 ? " process is" : " processes are") " still running in this folder, left by earlier Claude Code sessions that have closed:" lines
        print "They keep their ports and memory until they are killed. /seshka:status lists them again, /seshka:clean kills them."
    }' "$list"
exit 0

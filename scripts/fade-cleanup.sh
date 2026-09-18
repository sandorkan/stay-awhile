#!/usr/bin/env bash
# A watchdog owns only the old player's stop marker, never the shared loop.pid.
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" 2>/dev/null || exit 0
PID="$1"
case "$PID" in ''|*[!0-9]*) exit 0 ;; esac
sleep 2
if ours "$PID"; then
  kill -- "-$PID" 2>/dev/null || kill "$PID" 2>/dev/null
fi
rm -f "$STOP_FILE.$PID" "$DATA/fade.$PID.pid" 2>/dev/null
exit 0

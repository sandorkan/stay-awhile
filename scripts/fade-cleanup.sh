#!/usr/bin/env bash
# A watchdog owns only the old player's stop marker, never the shared loop.pid.
#   fade-cleanup.sh <pid> [marker]   — marker defaults to loop.stop.<pid>
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" 2>/dev/null || exit 0
PID="$1"
case "$PID" in ''|*[!0-9]*) exit 0 ;; esac
MARKER="${2:-$STOP_FILE.$PID}"
sleep 2
if ours "$PID"; then
  kill -- "-$PID" 2>/dev/null || kill "$PID" 2>/dev/null
fi
rm -f "$MARKER" "$DATA/fade.$PID.pid" 2>/dev/null
exit 0

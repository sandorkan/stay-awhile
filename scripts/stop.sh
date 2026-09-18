#!/usr/bin/env bash
# Stop / StopFailure / Notification / SessionEnd hook.
# Argument is the cue to play: done | failed | needs-you | silent
#
# needs-you stops the bed too. A loop playing on while Claude sits blocked on
# a permission prompt is worse than silence — it tells you work is happening
# when nothing is. The PostToolUse resume brings it back once work continues.
#
# The bed only stops when no other session is still working.

source "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" 2>/dev/null || exit 0

CUE="${1:-silent}"
# SessionEnd passes `session-end`: silent like the others, but it also retires
# the viewer server once no session is left to watch. An idle_prompt sends
# plain `silent`, which must never shut anything down.
ENDING=""
if [ "$CUE" = "session-end" ]; then ENDING=1; CUE=silent; fi

INPUT="$(cat)"
SID="$(printf '%s' "$INPUT" | session_id)"
rm -f "$ACTIVE/$SID"
[ -n "$ENDING" ] && rm -f "$SESSIONS/$SID"

[ "$CUE" = "needs-you" ] && count_bump "$(perm_count "$SID")"
wait_end "$SID" "$CUE" \
  "$(printf '%s' "$INPUT" | json_str transcript_path)" \
  "$(printf '%s' "$INPUT" | json_str cwd)"

if ! any_active; then
  stop_loop
  kill_pidfile "$EYE_PID"
fi

if [ "$CUE" != "silent" ] && [ "$CUES" != "false" ]; then
  play_once "$CUE"
fi

# Recheck open-session leases in the setup tool, including idle sessions.
if [ -n "$ENDING" ] && command -v python3 >/dev/null 2>&1; then
  python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py" stop --if-idle </dev/null >/dev/null 2>&1 &
fi

exit 0

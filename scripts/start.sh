#!/usr/bin/env bash
# UserPromptSubmit hook, and PostToolUse hook with the argument `resume`.
#
# This event blocks model processing until it returns, so everything here
# either backgrounds immediately or is a file read. It also exits 0 on every
# path: exit 2 on UserPromptSubmit rejects your prompt, and a stray non-zero
# from `cat` or arithmetic would do exactly that.
#
# `resume` brings the bed back once a tool runs after a needs-you prompt
# silenced it. It's a no-op while the bed is already playing, and it doesn't
# count toward the look-away cue.

source "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" 2>/dev/null || exit 0

# Hook JSON arrives on stdin and can only be read once.
INPUT="$(cat)"
SID="$(printf '%s' "$INPUT" | session_id)"
touch "$SESSIONS/$SID" "$ACTIVE/$SID" 2>/dev/null

if [ "$1" = "resume" ]; then
  count_bump "$(tool_count "$SID")"  # one tool call done; the turn carries on
else
  wait_start "$SID"
fi

TRACK="${CLAUDE_PLUGIN_OPTION_TRACK:-breathing/4-6-calm}"
# Claude may keep the plugin option environment from session startup. Read the
# shared saved preference on a new turn instead. Simulations keep their explicit
# audition track and must never pick up the user's live preference.
TURN_TRACK="$DATA/turn-track/$SID"
if [ "$1" = "resume" ] && [ -f "$TURN_TRACK" ]; then
  TRACK="$(cat "$TURN_TRACK" 2>/dev/null)"
elif [ "${STAY_AWHILE_SIMULATION:-}" != 1 ] && command -v python3 >/dev/null 2>&1; then
  SAVED_TRACK="$(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py" music current 2>/dev/null)"
  [ -n "$SAVED_TRACK" ] && TRACK="$SAVED_TRACK"
fi

# Validate against a real file rather than trusting the configured string.
# The value comes from a settings file and lands in a path; tracks live in
# category folders, so `/` is allowed but `..` is not.
case "$TRACK" in *..*) TRACK=none ;; esac

# shuffle-<category> picks a new song per prompt. A resume, or a prompt while
# another session's song is still playing, keeps the current one instead.
case "$TRACK" in
  shuffle-*)
    LAST="$(cat "$CURRENT" 2>/dev/null)"
    if [ -n "$LAST" ] && { [ "$1" = "resume" ] || loop_alive; }; then
      TRACK="$LAST"
    else
      TRACK="$(pick_track "${TRACK#shuffle-}" "$LAST")"
      echo "$TRACK" > "$CURRENT" 2>/dev/null
    fi ;;
esac

# Remember the resolved song for permission-pause resumes of this turn.
# A setting changed mid-turn takes effect on a later prompt, not on resume.
mkdir -p "$DATA/turn-track" 2>/dev/null
printf '%s\n' "$TRACK" > "$TURN_TRACK.$$" 2>/dev/null &&
  mv -f "$TURN_TRACK.$$" "$TURN_TRACK" 2>/dev/null

if [ "$TRACK" != "none" ] && [ -f "$SOUNDS/$TRACK.wav" ]; then
  start_loop "$TRACK"
fi

[ "$1" = "resume" ] && exit 0

# --- look-away cue ----------------------------------------------------------
EVERY="${CLAUDE_PLUGIN_OPTION_EYE_CUE_EVERY:-8}"
case "$EVERY" in ''|*[!0-9]*) EVERY=0 ;; esac
[ "$EVERY" -eq 0 ] && exit 0

N=$(( $(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))

if [ "$N" -ge "$EVERY" ]; then
  echo 0 > "$COUNT_FILE"
  # Armed, not fired. If the turn finishes inside 15s you were never idle
  # long enough to need a break, and stop.sh cancels this before it speaks.
  kill_pidfile "$EYE_PID"
  detach "$EYE_PID" bash -c '
    sleep 15
    "$0"/scripts/cue.sh look-away
    sleep 20
    "$0"/scripts/cue.sh come-back
  ' "${CLAUDE_PLUGIN_ROOT}"
else
  echo "$N" > "$COUNT_FILE"
fi

exit 0

#!/usr/bin/env bash
# Behind /stay-awhile:mute and :unmute (through `setup.py sound`).
#
#   sound.sh off     — write $DATA/muted, fade the loop that is playing now and
#                      cancel an armed look-away cue; every hook stays silent
#                      while the file exists. Music and volume are untouched.
#   sound.sh on      — remove it; sound returns with the next prompt or tool call.
#   sound.sh status  — print on|off.
#
# A flag in the data directory rather than a setting: mute is "quiet for now",
# it must take effect at once, and it must not write settings.json or restart
# anything. The directory is shared, so it silences every session.
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" 2>/dev/null || exit 1
case "$1" in
  off)    : > "$MUTED" 2>/dev/null; stop_loop; kill_pidfile "$EYE_PID"; echo off ;;
  on)     rm -f "$MUTED"; echo on ;;
  status) if [ -f "$MUTED" ]; then echo off; else echo on; fi ;;
  *)      echo "usage: sound.sh on|off|status" >&2; exit 2 ;;
esac
exit 0

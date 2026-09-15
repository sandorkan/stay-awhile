#!/usr/bin/env bash
# Shared helpers. Sourced by the hook scripts.
# Every function here must be safe to call when no audio player exists.

SOUNDS="${CLAUDE_PLUGIN_ROOT}/sounds"
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/working-sounds}"
mkdir -p "$DATA/active" 2>/dev/null

VOLUME="${CLAUDE_PLUGIN_OPTION_VOLUME:-0.4}"
CUES="${CLAUDE_PLUGIN_OPTION_CUES:-true}"

# One bed at a time across all sessions, because overlapping beds sound like
# mud. Each session that's working holds a marker in $ACTIVE; the bed stops
# when the last marker goes.
ACTIVE="$DATA/active"
CURRENT="$DATA/current-track"
LOOP_PID="$DATA/loop.pid"
EYE_PID="$DATA/eye.pid"
COUNT_FILE="$DATA/eye.count"

# --- player detection -------------------------------------------------------

detect_player() {
  if command -v afplay >/dev/null 2>&1; then echo afplay
  elif command -v paplay >/dev/null 2>&1; then echo paplay
  elif command -v ffplay >/dev/null 2>&1; then echo ffplay
  elif command -v aplay  >/dev/null 2>&1; then echo aplay
  elif command -v powershell.exe >/dev/null 2>&1; then echo powershell
  else echo none
  fi
}

PLAYER="$(detect_player)"

# play <name>  — plays one sound and waits for it to finish
play() {
  local f="$SOUNDS/$1.wav"
  [ -f "$f" ] || return 0
  case "$PLAYER" in
    afplay)  afplay -v "$VOLUME" "$f" ;;
    paplay)  paplay --volume="$(vol_pulse)" "$f" ;;
    ffplay)  ffplay -nodisp -autoexit -loglevel quiet -volume "$(vol_pct)" "$f" ;;
    aplay)   aplay -q "$f" ;;
    powershell)
      powershell.exe -NoProfile -Command \
        "(New-Object Media.SoundPlayer '$(win_path "$f")').PlaySync()" ;;
    *) return 1 ;;
  esac >/dev/null 2>&1
}

# play_once <name>  — fire and forget, never blocks the hook
play_once() {
  play "$1" </dev/null >/dev/null 2>&1 &
  return 0
}

# PowerShell needs a Windows path: wslpath under WSL, cygpath under Git Bash.
win_path() { wslpath -w "$1" 2>/dev/null || cygpath -w "$1" 2>/dev/null || echo "$1"; }

# Volume conversions for players that want something other than 0.0-1.0
vol_pulse() { awk -v v="$VOLUME" 'BEGIN{printf "%d", v*65536}'; }
vol_pct()   { awk -v v="$VOLUME" 'BEGIN{printf "%d", v*100}'; }

# pick_track <category> <last>  — a random track from sounds/<category>/, never
# <last> unless it's the only one there. Prints e.g. `8-bit/harbor`.
pick_track() {
  local files=() f found=0
  for f in "$SOUNDS/$1"/*.wav; do
    [ -f "$f" ] || continue
    found=1
    f="${f#"$SOUNDS/"}"; f="${f%.wav}"
    [ "$f" = "$2" ] || files+=("$f")
  done
  if [ ${#files[@]} -eq 0 ]; then
    [ "$found" = 1 ] && echo "$2"  # the only song there is the last one
    return 0
  fi
  echo "${files[RANDOM % ${#files[@]}]}"
}

# --- sessions ---------------------------------------------------------------

# session_id  — read from the hook's JSON on stdin. Kept to [A-Za-z0-9_-]
# because it becomes a filename.
session_id() {
  local id
  id="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | tr -cd 'A-Za-z0-9_-')"
  echo "${id:-default}"
}

# ponytail: a session killed without SessionEnd leaves its marker behind; it's
# ignored after 2h without a prompt or tool call. A liveness check on the
# Claude process would be exact, if 2h proves too long.
any_active() {
  find "$ACTIVE" -type f -mmin +120 -exec rm -f {} + 2>/dev/null
  [ -n "$(ls -A "$ACTIVE" 2>/dev/null)" ]
}

# --- loop control -----------------------------------------------------------

# detach <pidfile> <cmd...>  — run in the background in its own process group
# and record the PID. `set -m` gives the job its own group (PGID == PID), which
# kill_pidfile relies on. Used instead of setsid, which macOS doesn't ship.
detach() {
  local pf="$1"; shift
  set -m
  "$@" </dev/null >/dev/null 2>&1 &
  echo $! > "$pf"
  set +m
}

# ours <pid>  — true if the PID is still one of our background jobs. PIDs get
# reused once a process exits, and killing a stranger's process group is the
# one thing this plugin must never do. Both jobs carry the plugin path in
# their command line.
ours() {
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o command= -p "$1" 2>/dev/null)" in
    *"$CLAUDE_PLUGIN_ROOT"*) return 0 ;;
    *) return 1 ;;
  esac
}

kill_pidfile() {
  local pf="$1"
  [ -f "$pf" ] || return 0
  local pid
  pid="$(cat "$pf" 2>/dev/null)"
  if ours "$pid"; then
    # Negative PID kills the whole process group, so the `while` wrapper and
    # the player it spawned both go. Without this the current note keeps
    # playing after the turn ends.
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null
  fi
  rm -f "$pf"
  return 0
}

loop_alive() { ours "$(cat "$LOOP_PID" 2>/dev/null)"; }

# start_loop <track>  — no-op if a bed is already playing, so a second session
# or a resume doesn't restart it mid-phrase.
start_loop() {
  local track="$1"
  [ -f "$SOUNDS/$track.wav" ] || return 0
  [ "$PLAYER" = "none" ] && return 0
  loop_alive && return 0
  local f="$SOUNDS/$track.wav"
  case "$PLAYER" in
    # Restarting a player per pass leaves a gap (~0.5s for afplay) and a hard
    # restart, so use a player that loops the file itself where there is one.
    afplay)
      detach "$LOOP_PID" osascript -l JavaScript -e '
        function run(argv) {
          ObjC.import("AVFoundation");
          var p = $.AVAudioPlayer.alloc.initWithContentsOfURLError(
            $.NSURL.fileURLWithPath(argv[0]), null);
          p.setNumberOfLoops(-1);
          p.setVolume(parseFloat(argv[1]));
          p.play;
          $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.distantFuture);
        }' "$f" "$VOLUME" ;;
    ffplay)
      detach "$LOOP_PID" ffplay -nodisp -loop 0 -loglevel quiet -volume "$(vol_pct)" "$f" ;;
    *)
      # ponytail: paplay/aplay/PowerShell can't loop a file, so these restart
      # with a small gap. Pre-rendering a longer file would hide it.
      # `|| sleep 1` stops a player that fails instantly from spinning the CPU.
      detach "$LOOP_PID" bash -c 'while true; do "$0" "$1" || sleep 1; done' \
        "${CLAUDE_PLUGIN_ROOT}/scripts/play-blocking.sh" "$track" ;;
  esac
  return 0
}

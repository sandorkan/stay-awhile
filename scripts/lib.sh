#!/usr/bin/env bash
# Shared helpers. Sourced by the hook scripts.
# Every function here must be safe to call when no audio player exists.

SOUNDS="${CLAUDE_PLUGIN_ROOT}/sounds"
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/waiting-room}"
mkdir -p "$DATA/active" "$DATA/started" 2>/dev/null

# Claude Code hands plugins their own data dir, but the status line runs from
# the user's settings with no plugin environment and can't know where that is.
# So publish it here, in the one place everything can agree on.
POINTER="$HOME/.claude/waiting-room/data-dir"
if [ "$DATA" != "$HOME/.claude/waiting-room" ] &&
   [ "$(cat "$POINTER" 2>/dev/null)" != "$DATA" ]; then
  mkdir -p "$HOME/.claude/waiting-room" 2>/dev/null
  printf '%s\n' "$DATA" > "$POINTER" 2>/dev/null
fi

VOLUME="${CLAUDE_PLUGIN_OPTION_VOLUME:-0.4}"
CUES="${CLAUDE_PLUGIN_OPTION_CUES:-true}"

# One bed at a time across all sessions, because overlapping beds sound like
# mud. Each session that's working holds a marker in $ACTIVE; the bed stops
# when the last marker goes.
ACTIVE="$DATA/active"
STARTED="$DATA/started"
WAITS="$DATA/waits.log"
CURRENT="$DATA/current-track"
LOOP_PID="$DATA/loop.pid"
EYE_PID="$DATA/eye.pid"
COUNT_FILE="$DATA/eye.count"
STOP_FILE="$DATA/loop.stop"   # its presence asks the player to fade out

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

# json_str <key>  — pull a plain string field out of the hook's JSON on stdin.
# Good enough for the flat fields we want (ids and paths, never the prompt).
json_str() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

# session_id  — from the hook's JSON on stdin. Kept to [A-Za-z0-9_-] because it
# becomes a filename.
session_id() {
  local id
  id="$(json_str session_id | tr -cd 'A-Za-z0-9_-')"
  echo "${id:-default}"
}

# ponytail: a session killed without SessionEnd leaves its marker behind; it's
# ignored after 2h without a prompt or tool call. A liveness check on the
# Claude process would be exact, if 2h proves too long.
any_active() {
  find "$ACTIVE" -type f -mmin +120 -exec rm -f {} + 2>/dev/null
  [ -n "$(ls -A "$ACTIVE" 2>/dev/null)" ]
}

# --- what the waits are actually like ---------------------------------------
# One tab-separated line per turn in $WAITS. Counts and timings only: no prompt
# text, no file contents, no repo path beyond its folder name. A local file,
# never sent anywhere. Columns, in order:
#
#   1 ended          when the turn ended, ISO 8601
#   2 seconds        how long it ran
#   3 outcome        done | failed | needs-you | silent
#   4 session        Claude Code's session id
#   5 words          the prompt, in words
#   6 chars          the prompt, in characters
#   7 images         images attached to it
#   8 paths          file paths mentioned
#   9 code_blocks    fenced code blocks
#  10 urls
#  11 bullets        bulleted or numbered lines
#  12 questions      question marks
#  13 is_slash       1 if the prompt was a /command
#  14 tools          tool calls in the turn
#  15 permissions    permission prompts during it
#  16 think_secs     gap between the last turn ending and this prompt
#  17 switched_away  1 if you prompted another session while this one ran
#  18 concurrent     other turns already in flight when this one started
#  19 project        folder name of the working directory
#
# 5-13 come from prompt-metrics.py, which reads the transcript's last user
# message. Zeros mean "couldn't measure" (no python3, no transcript), never 0.

count_bump() {
  local n
  n="$(cat "$1" 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  echo $((n + 1)) > "$1" 2>/dev/null
}

count_get() {
  local n
  n="$(cat "$1" 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

tool_count() { echo "$DATA/count/$1.tools"; }
perm_count() { echo "$DATA/count/$1.perms"; }

# wait_start <session>  — begins a turn: notes the time, how many other turns
# were already running, and flags those as switched away from.
wait_start() {
  mkdir -p "$DATA/count" "$DATA/switched" 2>/dev/null
  local other concurrent=0
  for other in "$STARTED"/*; do
    [ -f "$other" ] || continue
    [ "${other##*/}" = "$1" ] && continue
    concurrent=$((concurrent + 1))
    # You just prompted here while that one was still working.
    : > "$DATA/switched/${other##*/}" 2>/dev/null
  done
  local last think=0
  last="$(cat "$DATA/count/$1.lastend" 2>/dev/null)"
  case "$last" in ''|*[!0-9]*) ;; *) think=$(( $(date +%s) - last )) ;; esac
  [ "$think" -lt 0 ] && think=0
  printf '%s %s %s\n' "$(date +%s)" "$concurrent" "$think" > "$STARTED/$1" 2>/dev/null
  : > "$(tool_count "$1")" 2>/dev/null
  : > "$(perm_count "$1")" 2>/dev/null
}

# wait_end <session> <outcome> [transcript] [cwd]  — needs-you keeps the start
# time, because the turn isn't over: it logs the stretch up to the prompt and
# keeps counting.
wait_end() {
  local began concurrent think
  read -r began concurrent think < "$STARTED/$1" 2>/dev/null
  case "$began" in ''|*[!0-9]*) return 0 ;; esac

  local metrics="0	0	0	0	0	0	0	0	0"
  if [ -n "$3" ] && [ -f "$3" ] && command -v python3 >/dev/null 2>&1; then
    metrics="$(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/prompt-metrics.py" "$3" 2>/dev/null)" \
      || metrics="0	0	0	0	0	0	0	0	0"
  fi

  local switched=0
  [ -f "$DATA/switched/$1" ] && switched=1

  # ponytail: one ~90-byte line per turn, never rotated. Trim it if it matters.
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date +%FT%T%z)" "$(( $(date +%s) - began ))" "$2" "$1" \
    "$metrics" \
    "$(count_get "$(tool_count "$1")")" "$(count_get "$(perm_count "$1")")" \
    "${think:-0}" "$switched" "${concurrent:-0}" "$(basename "${4:-unknown}")" \
    >> "$WAITS" 2>/dev/null

  if [ "$2" != "needs-you" ]; then
    date +%s > "$DATA/count/$1.lastend" 2>/dev/null
    rm -f "$STARTED/$1" "$DATA/switched/$1" "$(tool_count "$1")" "$(perm_count "$1")"
  fi
  return 0
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

# stop_loop — fade where the player can (macOS), cut where it can't. The hook
# never waits: the player exits on its own, and a watchdog cleans up after it.
stop_loop() {
  if [ "$PLAYER" = "afplay" ] && loop_alive; then
    : > "$STOP_FILE" 2>/dev/null
    local pid
    pid="$(cat "$LOOP_PID" 2>/dev/null)"
    detach "$DATA/fade.pid" bash -c \
      'sleep 2; kill -- -"$0" 2>/dev/null; rm -f "$1" "$2" 2>/dev/null' \
      "$pid" "$LOOP_PID" "$STOP_FILE"
  else
    kill_pidfile "$LOOP_PID"
  fi
  return 0
}

# start_loop <track>  — no-op if a bed is already playing, so a second session
# or a resume doesn't restart it mid-phrase.
start_loop() {
  local track="$1"
  [ -f "$SOUNDS/$track.wav" ] || return 0
  [ "$PLAYER" = "none" ] && return 0
  if loop_alive; then
    [ -f "$STOP_FILE" ] || return 0   # already playing; leave it alone
    kill_pidfile "$LOOP_PID"        # it's fading out: start again cleanly
  fi
  local f="$SOUNDS/$track.wav"
  case "$PLAYER" in
    # Restarting a player per pass leaves a gap (~0.5s for afplay) and a hard
    # restart, so use a player that loops the file itself where there is one.
    afplay)
      rm -f "$STOP_FILE" 2>/dev/null
      detach "$LOOP_PID" osascript -l JavaScript -e '
        function run(argv) {
          ObjC.import("AVFoundation");
          var p = $.AVAudioPlayer.alloc.initWithContentsOfURLError(
            $.NSURL.fileURLWithPath(argv[0]), null);
          p.setNumberOfLoops(-1);
          p.setVolume(parseFloat(argv[1]));
          p.play;
          // Being killed mid-note is a hard cut. Watch for the stop file
          // instead and fade out, which AVAudioPlayer does for us.
          var fm = $.NSFileManager.defaultManager, stop = argv[2], fade = 0.9;
          var run = $.NSRunLoop.currentRunLoop;
          while (true) {
            run.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
            if (fm.fileExistsAtPath(stop)) {
              p.setVolumeFadeDuration(0, fade);
              run.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(fade + 0.1));
              return;
            }
          }
        }' "$f" "$VOLUME" "$STOP_FILE" ;;
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

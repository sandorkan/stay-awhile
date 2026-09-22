#!/usr/bin/env bash
# Legacy names remain valid for existing launchers and isolated auditions.
export STAY_AWHILE_SIMULATION="${STAY_AWHILE_SIMULATION:-${WAITING_ROOM_SIMULATION:-}}"
# Shared helpers. Sourced by the hook scripts.
# Every function here must be safe to call when no audio player exists.
#
# Forks are the cost that matters. Each external command is ~1ms on macOS and
# ~100ms under Git Bash on Windows, where the hooks run inside the prompt's
# critical path. So: bash builtins for reads, regexes and string surgery, and
# an external command only where there is no builtin (find, ps, mv, rm).

# readf <var> <file>  — first line of a file into a variable, empty if missing.
readf() {
  local __line=
  [ -f "$2" ] && { IFS= read -r __line < "$2"; } 2>/dev/null
  printf -v "$1" '%s' "$__line"
}

# slashes <var> <path>  — backslashes to forward slashes, no fork. Pattern
# substitution with a backslash behaves differently in every bash (quoted,
# unquoted, 3.2 or 5); splitting on the character and rejoining does not.
slashes() {
  # shellcheck disable=SC2141  # the literal backslash is the point
  local IFS='\' __parts __joined
  read -r -a __parts <<< "$2"
  printf -v __joined '%s/' "${__parts[@]}"
  printf -v "$1" '%s' "${__joined%/}"
}

# data_dir_ok <path>  — a data directory worth following or publishing: one
# that exists under a .claude directory, where Claude Code assigns them. The
# pointer file below redirects every hook, so a stray value (a test run with a
# scratch CLAUDE_PLUGIN_DATA and no simulation flag, say) must not get in.
data_dir_ok() {
  local p
  slashes p "$1"
  case "$p" in */.claude/*) [ -d "$1" ] ;; *) return 1 ;; esac
}

SOUNDS="${CLAUDE_PLUGIN_ROOT}/sounds"
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/waiting-room}"
# A renamed plugin receives a new assigned directory. Reuse its predecessor's
# published directory to preserve history, without moving live runtime files.
if [ "${STAY_AWHILE_SIMULATION:-}" != 1 ]; then
  case "$DATA" in
    *stay-awhile*)
      readf legacy_data "$HOME/.claude/waiting-room/data-dir"
      [ -n "$legacy_data" ] || { [ ! -f "$HOME/.claude/waiting-room/waits.log" ] || legacy_data="$HOME/.claude/waiting-room"; }
      ! data_dir_ok "$legacy_data" || DATA="$legacy_data" ;;
  esac
fi
[ -d "$DATA/active" ] && [ -d "$DATA/started" ] && [ -d "$DATA/sessions" ] ||
  mkdir -p "$DATA/active" "$DATA/started" "$DATA/sessions" 2>/dev/null

# Claude Code hands plugins their own data dir, but the status line runs from
# the user's settings with no plugin environment and can't know where that is.
# So publish it here, in the one place everything can agree on.
POINTER="$HOME/.claude/waiting-room/data-dir"
if [ "${STAY_AWHILE_SIMULATION:-}" != 1 ] && [ "$DATA" != "$HOME/.claude/waiting-room" ] && data_dir_ok "$DATA"; then
  readf published "$POINTER"
  if [ "$published" != "$DATA" ]; then
    mkdir -p "$HOME/.claude/waiting-room" 2>/dev/null
    printf '%s\n' "$DATA" > "$POINTER.$$" 2>/dev/null &&
      mv -f "$POINTER.$$" "$POINTER" 2>/dev/null
  fi
fi

VOLUME="${CLAUDE_PLUGIN_OPTION_VOLUME:-0.4}"
# The viewer's slider saves `volume` to settings.json; Claude only refreshes
# the option environment at session start. start.sh reads the saved value on
# each prompt and caches it here, so cues and resumes pick it up without a
# Python start. Simulations keep their explicit level.
if [ "${STAY_AWHILE_SIMULATION:-}" != 1 ]; then
  readf saved_volume "$DATA/volume"
  case "$saved_volume" in ''|*[!0-9.]*|.) ;; *) VOLUME="$saved_volume" ;; esac
fi
CUES="${CLAUDE_PLUGIN_OPTION_CUES:-true}"

# One bed at a time across all sessions, because overlapping beds sound like
# mud. Each session that's working holds a marker in $ACTIVE; the bed stops
# when the last marker goes.
ACTIVE="$DATA/active"
STARTED="$DATA/started"
SESSIONS="$DATA/sessions"
WAITS="$DATA/waits.log"
CURRENT="$DATA/current-track"
LOOP_PID="$DATA/loop.pid"
LOOP_MARKER="$DATA/loop.marker"   # Windows: the stop marker the running loop watches
EYE_PID="$DATA/eye.pid"
COUNT_FILE="$DATA/eye.count"
STOP_FILE="$DATA/loop.stop"   # each player watches loop.stop.<its PID>
MUTED="$DATA/muted"           # /stay-awhile:mute: while it exists, no loop and no cue

# --- platform ---------------------------------------------------------------

case "$OSTYPE" in msys*|cygwin*) WINDOWS=1 ;; *) WINDOWS= ;; esac

# The Python for the helper scripts. Unix ships `python3`. Windows ships
# `python`; its `python3` is a slower Store alias, or a stub that opens the
# Store. Empty when there is none: callers then skip what needs it.
PY=
py_pick() { local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; return 0; }; done; return 1; }
if [ -n "$WINDOWS" ]; then py_pick python python3; else py_pick python3 python; fi

# to_native <var> <path>  — a path as a Windows program wants it. Forward
# slashes are kept: PowerShell accepts them, and ours() matches the plugin root
# against command lines, so the spelling must not change on the way.
to_native() {
  local p="$2"
  if [ -n "$WINDOWS" ]; then
    case "$p" in /*) p="$(cygpath -m "$p" 2>/dev/null)" || p="$2" ;; esac
  elif command -v wslpath >/dev/null 2>&1; then
    p="$(wslpath -w "$p" 2>/dev/null)" || p="$2"
  fi
  printf -v "$1" '%s' "$p"
}

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
  local f="$SOUNDS/$1.wav" ps1 wav
  [ -f "$f" ] || return 0
  case "$PLAYER" in
    afplay)  afplay -v "$VOLUME" "$f" ;;
    paplay)  paplay --volume="$(vol_pulse)" "$f" ;;
    ffplay)  ffplay -nodisp -autoexit -loglevel quiet -volume "$(vol_pct)" "$f" ;;
    aplay)   aplay -q "$f" ;;
    powershell)
      to_native ps1 "$SCRIPTS/play.ps1"; to_native wav "$f"
      powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File "$ps1" -Path "$wav" -Volume "$VOLUME" ;;
    *) return 1 ;;
  esac >/dev/null 2>&1
}

# play_once <name>  — fire and forget, never blocks the hook
play_once() {
  [ -f "$MUTED" ] && return 0
  play "$1" </dev/null >/dev/null 2>&1 &
  return 0
}

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

# json_get <var> <key> <json>  — a plain string field out of the hook's JSON.
# Good enough for the flat fields we want (ids and paths, never the prompt):
# the first occurrence wins, which is the top-level one. Bash's own regex; the
# sed|head|tr pipeline it replaces cost ~300ms per field under MSYS.
json_get() {
  local re="\"$2\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  if [[ $3 =~ $re ]]; then printf -v "$1" '%s' "${BASH_REMATCH[1]}"; else printf -v "$1" ''; fi
}

# session_id <var> <json>  — kept to [A-Za-z0-9_-] because it becomes a filename.
session_id() {
  local id
  json_get id session_id "$2"
  id="${id//[^A-Za-z0-9_-]/}"
  printf -v "$1" '%s' "${id:-default}"
}

# ponytail: a session killed without SessionEnd leaves its marker behind; it's
# ignored after 2h without a prompt or tool call. A liveness check on the
# Claude process would be exact, if 2h proves too long.
any_active() {
  find "$ACTIVE" -type f -mmin +120 -exec rm -f {} + 2>/dev/null
  local f
  for f in "$ACTIVE"/*; do [ -f "$f" ] && return 0; done
  return 1
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
# message. Zeros mean "couldn't measure" (no python, no transcript), never 0.

# count_get <var> <file>  — a non-negative integer from a file, 0 otherwise.
# Locals in these <var>-setting helpers are double-underscored: bash scopes
# dynamically, so a local with the caller's name would swallow the result.
count_get() {
  local __n
  readf __n "$2"
  case "$__n" in ''|*[!0-9]*) __n=0 ;; esac
  printf -v "$1" '%s' "$__n"
}

count_bump() {
  local n
  count_get n "$1"
  echo $((n + 1)) > "$1" 2>/dev/null
}

# now_epoch <var>  — seconds since the epoch. Bash 5 knows without forking.
now_epoch() { printf -v "$1" '%s' "${EPOCHSECONDS:-$(date +%s)}"; }

# wait_start <session>  — begins a turn: notes the time, how many other turns
# were already running, and flags those as switched away from.
wait_start() {
  [ -d "$DATA/count" ] && [ -d "$DATA/switched" ] || mkdir -p "$DATA/count" "$DATA/switched" 2>/dev/null
  local other concurrent=0
  for other in "$STARTED"/*; do
    [ -f "$other" ] || continue
    [ "${other##*/}" = "$1" ] && continue
    concurrent=$((concurrent + 1))
    # You just prompted here while that one was still working.
    : > "$DATA/switched/${other##*/}" 2>/dev/null
  done
  local last think=0 now
  now_epoch now
  readf last "$DATA/count/$1.lastend"
  case "$last" in ''|*[!0-9]*) ;; *) think=$((now - last)) ;; esac
  [ "$think" -lt 0 ] && think=0
  printf '%s %s %s\n' "$now" "$concurrent" "$think" > "$STARTED/$1" 2>/dev/null
  : > "$DATA/count/$1.tools" 2>/dev/null
  : > "$DATA/count/$1.perms" 2>/dev/null
}

# wait_end <session> <outcome> [transcript] [cwd]  — needs-you keeps the start
# time, because the turn isn't over: it logs the stretch up to the prompt and
# keeps counting.
wait_end() {
  local began concurrent think
  { read -r began concurrent think < "$STARTED/$1"; } 2>/dev/null
  case "$began" in ''|*[!0-9]*) return 0 ;; esac

  local metrics="0	0	0	0	0	0	0	0	0"
  if [ -n "$3" ] && [ -f "$3" ] && [ -n "$PY" ]; then
    metrics="$("$PY" "$SCRIPTS/prompt-metrics.py" "$3" 2>/dev/null)" \
      || metrics="0	0	0	0	0	0	0	0	0"
  fi

  local switched=0
  [ -f "$DATA/switched/$1" ] && switched=1

  local now stamp tools perms project="${4:-unknown}"
  now_epoch now
  if [ "${BASH_VERSINFO[0]}" -ge 5 ]; then printf -v stamp '%(%FT%T%z)T' -1; else stamp="$(date +%FT%T%z)"; fi
  count_get tools "$DATA/count/$1.tools"
  count_get perms "$DATA/count/$1.perms"
  # basename, for either slash. Hook JSON carries C:\\Users\\... on Windows.
  slashes project "$project"; project="${project%/}"; project="${project##*/}"

  # ponytail: one ~90-byte line per turn, never rotated. Trim it if it matters.
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$stamp" "$((now - began))" "$2" "$1" \
    "$metrics" \
    "$tools" "$perms" \
    "${think:-0}" "$switched" "${concurrent:-0}" "${project:-unknown}" \
    >> "$WAITS" 2>/dev/null

  if [ "$2" != "needs-you" ]; then
    printf '%s\n' "$now" > "$DATA/count/$1.lastend" 2>/dev/null
    rm -f "$STARTED/$1" "$DATA/switched/$1" "$DATA/count/$1.tools" "$DATA/count/$1.perms"
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
# one thing this plugin must never do. Every job carries the plugin path in
# its command line.
ours() {
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null || return 1
  local cmd root
  if [ -n "$WINDOWS" ]; then
    # /proc has the whole command line (arguments run together, NULs dropped)
    # and costs no fork. MSYS ps would do, but it has no -o and it truncates
    # rows to $COLUMNS, which Claude Code sets for hooks — the plugin root at
    # the end of the line was cut off and every hook started another loop.
    { cmd="$(</proc/$1/cmdline)"; } 2>/dev/null
    [ -n "$cmd" ] || { cmd="$(COLUMNS=32767 ps -fp "$1" 2>/dev/null)"; cmd="${cmd#*$'\n'}"; }
  else
    cmd="$(ps -ww -o command= -p "$1" 2>/dev/null)"   # -ww: never truncate
  fi
  # Compare with forward slashes only: Windows spells the same path C:\x,
  # C:/x, and (seen from WSL) \wsl$\...\x.
  slashes cmd "$cmd"; slashes root "$CLAUDE_PLUGIN_ROOT"
  case "$cmd" in *"$root"*) return 0 ;; esac
  if [ -n "$WINDOWS" ]; then   # an MSYS-style root (/c/...) shows up as C:/... in ps
    root="$(cygpath -m "$CLAUDE_PLUGIN_ROOT" 2>/dev/null)"
    case "$cmd" in *"$root"*) [ -n "$root" ] && return 0 ;; esac
  fi
  return 1
}

kill_pidfile() {
  local pf="$1"
  [ -f "$pf" ] || return 0
  local pid
  readf pid "$pf"
  if ours "$pid"; then
    # Negative PID kills the whole process group, so the `while` wrapper and
    # the player it spawned both go. Without this the current note keeps
    # playing after the turn ends.
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null
  fi
  rm -f "$pf"
  return 0
}

loop_alive() { local pid; readf pid "$LOOP_PID"; ours "$pid"; }

# loop_marker <var> <pid>  — the file that asks the loop with this PID to fade
# out. macOS players derive it from their own PID. The Windows player can't
# see its MSYS PID, so start_loop chooses the name and leaves it in
# $LOOP_MARKER.
loop_marker() {
  local m=
  [ "$PLAYER" = powershell ] && readf m "$LOOP_MARKER"
  printf -v "$1" '%s' "${m:-$STOP_FILE.$2}"
}

# stop_loop — fade where the player can (macOS, Windows), cut where it can't.
# The hook never waits: the player exits on its own, and a watchdog cleans up
# after it.
stop_loop() {
  if { [ "$PLAYER" = afplay ] || [ "$PLAYER" = powershell ]; } && loop_alive; then
    local pid marker
    readf pid "$LOOP_PID"
    loop_marker marker "$pid"
    [ -f "$marker" ] && return 0
    : > "$marker" 2>/dev/null
    detach "$DATA/fade.$pid.pid" bash "$SCRIPTS/fade-cleanup.sh" "$pid" "$marker"
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
  [ -f "$MUTED" ] && return 0
  if loop_alive; then
    local pid marker
    readf pid "$LOOP_PID"
    loop_marker marker "$pid"
    [ -f "$marker" ] || return 0   # already playing; leave it alone
    kill_pidfile "$LOOP_PID"        # it's fading out: start again cleanly
  fi
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
          // Being killed mid-note is a hard cut. Watch for the stop file
          // instead and fade out, which AVAudioPlayer does for us.
          var fm = $.NSFileManager.defaultManager, stop = argv[2] + "." + $.NSProcessInfo.processInfo.processIdentifier, fade = 0.9;
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
    powershell)
      # play.ps1 loops through winmm and fades when its marker appears. The
      # marker is chosen here (see loop_marker) and handed over as an argument.
      local marker="$STOP_FILE.$$.$RANDOM" ps1 wav nmarker
      printf '%s\n' "$marker" > "$LOOP_MARKER" 2>/dev/null
      to_native ps1 "$SCRIPTS/play.ps1"; to_native wav "$f"; to_native nmarker "$marker"
      detach "$LOOP_PID" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File "$ps1" -Path "$wav" -Volume "$VOLUME" -Loop -StopFile "$nmarker" ;;
    *)
      # ponytail: paplay/aplay can't loop a file, so these restart with a
      # small gap. Pre-rendering a longer file would hide it.
      # `|| sleep 1` stops a player that fails instantly from spinning the CPU.
      detach "$LOOP_PID" bash -c 'while true; do "$0" "$1" || sleep 1; done' \
        "$SCRIPTS/play-blocking.sh" "$track" ;;
  esac
  return 0
}

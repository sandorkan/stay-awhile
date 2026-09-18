#!/usr/bin/env bash
# Legacy names remain valid for existing launchers and isolated auditions.
export STAY_AWHILE_SIMULATION="${STAY_AWHILE_SIMULATION:-${WAITING_ROOM_SIMULATION:-}}"
# statusLine hook. Two jobs:
#   1. save the payload, which is the only local source of the real rate-limit
#      numbers (the same ones /usage shows), for the viewer to read;
#   2. print one compact row.
#
# It runs on every UI update (debounced to 300ms) and on each refreshInterval
# tick, and Claude Code cancels it if a new update arrives while it's still
# running — so it must stay cheap. No network, no git, no sleeps. And few
# forks: an external command is ~100ms under Git Bash on Windows, so the JSON
# is picked apart in one jq or awk call and the rest is bash builtins. Cache
# files are rewritten only when their content changed.
#
# Configure it in settings.json (see README):
#   "statusLine": { "type": "command", "command": "<plugin>/scripts/statusline.sh",
#                   "refreshInterval": 5 }

IFS= read -r -d '' INPUT
BS='\'
readf() { local __l=; [ -f "$2" ] && { IFS= read -r __l < "$2"; } 2>/dev/null; printf -v "$1" '%s' "$__l"; }
# Same rule as lib.sh: follow the pointer only to an existing dir under .claude.
data_dir_ok() { local p="${1//"$BS"//}"; case "$p" in */.claude/*) [ -d "$1" ] ;; *) return 1 ;; esac; }

DATA="${CLAUDE_PLUGIN_DATA:-}"
if [ -z "$DATA" ]; then
  # the hooks publish their real data dir here; fall back to the default
  readf DATA "$HOME/.claude/waiting-room/data-dir"
  data_dir_ok "$DATA" || DATA="$HOME/.claude/waiting-room"
fi
# Match the renamed hooks when Claude passes the new assigned data directory.
if [ "${STAY_AWHILE_SIMULATION:-}" != 1 ]; then
  case "$DATA" in *stay-awhile*)
    readf legacy_data "$HOME/.claude/waiting-room/data-dir"
    [ -n "$legacy_data" ] || { [ ! -f "$HOME/.claude/waiting-room/waits.log" ] || legacy_data="$HOME/.claude/waiting-room"; }
    ! data_dir_ok "$legacy_data" || DATA="$legacy_data" ;;
  esac
fi
[ -d "$DATA" ] || mkdir -p "$DATA" 2>/dev/null

# save <file> <content>  — atomic, and only when the content is new. The
# viewer parses these files, so a reader must never catch a half-written one.
save() {
  local old
  readf old "$1"
  [ "$old" = "$2" ] && return 0
  local tmp="$1.$$"
  if printf '%s' "$2" > "$tmp" 2>/dev/null; then mv -f "$tmp" "$1" 2>/dev/null
  else rm -f "$tmp" 2>/dev/null; fi
}

save "$DATA/status.json" "$INPUT"

# One pass over the payload: five_hour, seven_day and spend_limit usage, the
# five-hour reset, and the session id, `|`-separated. jq when it's there, awk
# when it isn't. Fields stay empty for windows that are missing or null.
if command -v jq >/dev/null 2>&1; then
  FIELDS="$(jq -r '[.rate_limits.five_hour.used_percentage, .rate_limits.seven_day.used_percentage,
                    .rate_limits.spend_limit.used_percentage, .rate_limits.five_hour.resets_at, .session_id]
                   | map(if . == null then "" else tostring end) | join("|")' <<< "$INPUT" 2>/dev/null)"
else
  FIELDS="$(awk '
    { s = s $0 }
    END { printf "%s|%s|%s|%s|%s", win("five_hour", "used_percentage", "[0-9.]+"),
            win("seven_day", "used_percentage", "[0-9.]+"), win("spend_limit", "used_percentage", "[0-9.]+"),
            win("five_hour", "resets_at", "[0-9]+"), str("session_id") }
    # a number inside the flat object under "name"; nothing for null or absent
    function win(name, key, num,   rest, i) {
      i = index(s, "\"" name "\""); if (!i) return ""
      rest = substr(s, i + length(name) + 2)
      if (!match(rest, /^[ \t\r\n]*:[ \t\r\n]*\{/)) return ""
      rest = substr(rest, RLENGTH)
      i = index(rest, "}"); if (i) rest = substr(rest, 1, i)
      if (!match(rest, "\"" key "\"[ \t\r\n]*:[ \t\r\n]*" num)) return ""
      rest = substr(rest, RSTART, RLENGTH); sub(/^"[a-z_]+"[ \t\r\n]*:[ \t\r\n]*/, "", rest)
      return rest
    }
    function str(key,   v) {
      if (!match(s, "\"" key "\"[ \t\r\n]*:[ \t\r\n]*\"[^\"]*\"")) return ""
      v = substr(s, RSTART, RLENGTH); sub(/^"[a-z_]+"[ \t\r\n]*:[ \t\r\n]*"/, "", v); sub(/"$/, "", v)
      return v
    }' <<< "$INPUT" 2>/dev/null)"
fi
IFS='|' read -r FIVE WEEK SPEND RESETS SID <<< "$FIELDS"
SID="${SID//[^A-Za-z0-9_-]/}"
case "$FIVE" in *[!0-9.]*|.) FIVE= ;; esac
case "$WEEK" in *[!0-9.]*|.) WEEK= ;; esac
case "$SPEND" in *[!0-9.]*|.) SPEND= ;; esac
case "$RESETS" in *[!0-9]*) RESETS= ;; esac

# Keep only payloads with actual window data, and replace the cache atomically.
# Null/empty rate_limits from a new session must not erase a still-valid cache.
[ -n "$FIVE$WEEK" ] && save "$DATA/limits.json" "$INPUT"

# Cache windows independently: weekly-only updates must not erase five-hour
# data. Separate atomic files also avoid read/merge/write races across sessions.
[ -n "$FIVE" ]  && save "$DATA/limits-five_hour.json" "$INPUT"
[ -n "$WEEK" ]  && save "$DATA/limits-seven_day.json" "$INPUT"
[ -n "$SPEND" ] && save "$DATA/limits-spend_limit.json" "$INPUT"

# Refresh the open-session lease even while no turn is running.
if [ -n "$SID" ] && [ "${STAY_AWHILE_SIMULATION:-}" != 1 ]; then
  [ -d "$DATA/sessions" ] || mkdir -p "$DATA/sessions" 2>/dev/null
  : > "$DATA/sessions/$SID" 2>/dev/null
fi

NOW="${EPOCHSECONDS:-$(date +%s)}"

# Capture genuine exhaustion; clear it when usage drops or the reset passes.
if [ -z "$FIVE" ]; then
  if [ -n "$RESETS" ] && [ "$RESETS" -le "$NOW" ]; then
    rm -f "$DATA/ran-out" "$DATA/ran-out-reset" 2>/dev/null
  fi
elif [ "${FIVE%%.*}" -ge 100 ] 2>/dev/null && { [ -z "$RESETS" ] || [ "$RESETS" -gt "$NOW" ]; }; then
  readf RAN_RESET "$DATA/ran-out-reset"
  if [ ! -f "$DATA/ran-out" ] || [ "$RAN_RESET" != "$RESETS" ]; then
    printf '%s\n' "$NOW" > "$DATA/ran-out" 2>/dev/null
    printf '%s' "$RESETS" > "$DATA/ran-out-reset" 2>/dev/null
  fi
else
  [ -f "$DATA/ran-out" ] && rm -f "$DATA/ran-out" "$DATA/ran-out-reset" 2>/dev/null
fi

# --- the row itself ---------------------------------------------------------
# Percentages are what you've used, like the usage page on claude.ai, and the
# same wording the viewer shows: "43% · 3:21 · wk 27%".
used() {  # 43.5 -> 44, 43.2 -> 43, 27 -> 27
  local n="${1%%.*}" d="${1#*.}"
  [ "$d" = "$1" ] && d=0
  d="${d}0"; d="${d:0:1}"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$d" -ge 5 ] && n=$((n + 1))
  echo "$n"
}

SEGMENTS=""
add() { [ -n "$1" ] && SEGMENTS="${SEGMENTS:+$SEGMENTS · }$1"; }

[ -n "$FIVE" ] && add "$(used "$FIVE")%"

if [ -n "$RESETS" ]; then
  secs=$(( RESETS - NOW ))
  [ "$secs" -gt 0 ] && add "$(printf '%d:%02d' $((secs / 3600)) $(((secs % 3600) / 60)))"
fi

[ -n "$WEEK" ] && add "wk $(used "$WEEK")%"

# Someone else's status line goes first, so installing this doesn't replace it.
CHAIN="${CLAUDE_PLUGIN_OPTION_STATUSLINE_CHAIN:-}"
if [ -n "$CHAIN" ]; then
  chained="$(printf '%s' "$INPUT" | eval "$CHAIN" 2>/dev/null | head -n 1)"
  [ -n "$chained" ] && SEGMENTS="${chained}${SEGMENTS:+   $SEGMENTS}"
fi

# rate_limits only exists for Pro/Max, and only after the session's first API
# response — an empty row then is correct, not an error.
printf '%s' "$SEGMENTS"

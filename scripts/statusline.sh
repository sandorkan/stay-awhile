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
# running — so it must stay cheap. No network, no git, no sleeps.
#
# Configure it in settings.json (see README):
#   "statusLine": { "type": "command", "command": "<plugin>/scripts/statusline.sh",
#                   "refreshInterval": 5 }

INPUT="$(cat)"
DATA="${CLAUDE_PLUGIN_DATA:-}"
if [ -z "$DATA" ]; then
  # the hooks publish their real data dir here; fall back to the default
  DATA="$(cat "$HOME/.claude/waiting-room/data-dir" 2>/dev/null)"
  [ -d "$DATA" ] || DATA="$HOME/.claude/waiting-room"
fi
# Match the renamed hooks when Claude passes the new assigned data directory.
if [ "${STAY_AWHILE_SIMULATION:-}" != 1 ]; then
  case "$DATA" in *stay-awhile*)
    legacy_data="$(cat "$HOME/.claude/waiting-room/data-dir" 2>/dev/null)"
    [ -n "$legacy_data" ] || { [ ! -f "$HOME/.claude/waiting-room/waits.log" ] || legacy_data="$HOME/.claude/waiting-room"; }
    [ ! -d "$legacy_data" ] || DATA="$legacy_data" ;;
  esac
fi
mkdir -p "$DATA" 2>/dev/null

# Keep the payload whole: the viewer parses it, so write it atomically rather
# than letting a reader catch a half-written file.
tmp="$DATA/.status.$$"
if printf '%s' "$INPUT" > "$tmp" 2>/dev/null; then
  mv -f "$tmp" "$DATA/status.json" 2>/dev/null
else rm -f "$tmp" 2>/dev/null; fi

# field <jq path> <sed script>  — jq when it's there, sed when it isn't.
field() {
  if command -v jq >/dev/null 2>&1; then printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null
  else printf '%s' "$INPUT" | sed -n "$2" | head -n 1; fi
}
pct_of() {  # the used_percentage inside one rate_limits window
  field ".rate_limits.$1.used_percentage" \
    "s/.*\"$1\"[^}]*\"used_percentage\"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p"
}

FIVE="$(pct_of five_hour)"
WEEK="$(pct_of seven_day)"
RESETS="$(field '.rate_limits.five_hour.resets_at' \
  's/.*"five_hour"[^}]*"resets_at"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')"
SID="$(field '.session_id' 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr -cd 'A-Za-z0-9_-')"

# Keep only payloads with actual window data, and replace the cache atomically.
# Null/empty rate_limits from a new session must not erase a still-valid cache.
if [ -n "$FIVE$WEEK" ]; then
  limits_tmp="$DATA/.limits.$$"
  printf '%s' "$INPUT" > "$limits_tmp" 2>/dev/null &&
    mv -f "$limits_tmp" "$DATA/limits.json" 2>/dev/null
fi

# Cache windows independently: weekly-only updates must not erase five-hour
# data. Separate atomic files also avoid read/merge/write races across sessions.
cache_window() {
  [ -n "$2" ] || return 0
  local window_tmp="$DATA/.limits-$1.$$"
  printf '%s' "$INPUT" > "$window_tmp" 2>/dev/null &&
    mv -f "$window_tmp" "$DATA/limits-$1.json" 2>/dev/null
}
cache_window five_hour "$FIVE"
cache_window seven_day "$WEEK"
cache_window spend_limit "$(pct_of spend_limit)"

# Refresh the open-session lease even while no turn is running.
if [ -n "$SID" ] && [ "${STAY_AWHILE_SIMULATION:-}" != 1 ]; then
  mkdir -p "$DATA/sessions" 2>/dev/null
  touch "$DATA/sessions/$SID" 2>/dev/null
fi

# Capture genuine exhaustion; clear it when usage drops or the reset passes.
case "$FIVE" in
  ''|*[!0-9.]*)
    if [ -n "$RESETS" ] && [ "$RESETS" -le "$(date +%s)" ] 2>/dev/null; then
      rm -f "$DATA/ran-out" "$DATA/ran-out-reset" 2>/dev/null
    fi ;;
  *) if [ "${FIVE%%.*}" -ge 100 ] 2>/dev/null &&
        { [ -z "$RESETS" ] || [ "$RESETS" -gt "$(date +%s)" ] 2>/dev/null; }; then
       if [ ! -f "$DATA/ran-out" ] ||
          [ "$(cat "$DATA/ran-out-reset" 2>/dev/null)" != "$RESETS" ]; then
         date +%s > "$DATA/ran-out" 2>/dev/null
         printf '%s' "$RESETS" > "$DATA/ran-out-reset" 2>/dev/null
       fi
     else rm -f "$DATA/ran-out" "$DATA/ran-out-reset" 2>/dev/null; fi ;;
esac

# --- the row itself ---------------------------------------------------------
# Percentages are what you've used, like the usage page on claude.ai, and the
# same wording the viewer shows: "43% · 3:21 · wk 27%".
used() { awk -v p="$1" 'BEGIN { printf "%d", p + 0.5 }' 2>/dev/null; }

SEGMENTS=""
add() { [ -n "$1" ] && SEGMENTS="${SEGMENTS:+$SEGMENTS · }$1"; }

[ -n "$FIVE" ] && add "$(used "$FIVE")%"

case "$RESETS" in
  ''|*[!0-9]*) ;;
  *) secs=$(( RESETS - $(date +%s) ))
     [ "$secs" -gt 0 ] && add "$(printf '%d:%02d' $((secs / 3600)) $(((secs % 3600) / 60)))" ;;
esac

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

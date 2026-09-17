#!/usr/bin/env bash
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
mkdir -p "$DATA" 2>/dev/null

# Keep the payload whole: the viewer parses it, so write it atomically rather
# than letting a reader catch a half-written file.
tmp="$DATA/.status.$$"
if printf '%s' "$INPUT" > "$tmp" 2>/dev/null; then
  mv -f "$tmp" "$DATA/status.json" 2>/dev/null
  # Keep the last payload that actually carried rate_limits: they're missing
  # before a session's first API response, and a window disappears once it
  # resets. Without this the viewer would blank out whenever that happened.
  case "$INPUT" in
    *'"rate_limits"'*) cp -f "$DATA/status.json" "$DATA/limits.json" 2>/dev/null ;;
  esac
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

# The moon needs to know when the window ran out; the payload only says what the
# level is now, so catch the moment it hits the ceiling.
case "$FIVE" in
  ''|*[!0-9.]*) ;;
  *) if [ "${FIVE%%.*}" -ge 99 ] 2>/dev/null; then
       [ -f "$DATA/ran-out" ] || date +%s > "$DATA/ran-out" 2>/dev/null
     else rm -f "$DATA/ran-out" 2>/dev/null; fi ;;
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

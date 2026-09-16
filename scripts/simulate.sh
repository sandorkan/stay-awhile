#!/usr/bin/env bash
# Fake a Claude Code turn by firing the hooks directly. Costs no tokens.
#
#   scripts/simulate.sh [done|failed|needs-you] [seconds]
#
# Options go through the same env vars Claude Code sets, e.g.
#   CLAUDE_PLUGIN_OPTION_TRACK=soundscapes/rain scripts/simulate.sh done 15
#   CLAUDE_PLUGIN_OPTION_EYE_CUE_EVERY=1 scripts/simulate.sh done 40

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$ROOT"
# Own state dir, so a simulation never stops a real session's loop.
export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/working-sounds-sim}"

END="${1:-done}"
SECS="${2:-8}"

trap '"$ROOT/scripts/stop.sh" silent </dev/null; exit 130' INT

echo "working ${SECS}s  (track=${CLAUDE_PLUGIN_OPTION_TRACK:-breathing/4-6-calm})"
"$ROOT/scripts/start.sh" </dev/null
sleep "$SECS"
echo "-> $END"
"$ROOT/scripts/stop.sh" "$END" </dev/null
sleep 2 # let the cue finish before returning

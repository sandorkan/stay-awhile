#!/usr/bin/env bash
# Plays a single named cue. Called by the armed look-away timer.
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" 2>/dev/null || exit 0
play_once "$1"
exit 0

#!/usr/bin/env bash
# Plays one named sound and waits for it to finish. Used only inside the loop.
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" 2>/dev/null || exit 1
play "$1"

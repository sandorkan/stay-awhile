#!/usr/bin/env bash
# SessionStart registers a lease even before the first prompt. The status line
# refreshes it while idle; SessionEnd removes it. No audio starts here.
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" 2>/dev/null || exit 0
SID="$(session_id)"
touch "$SESSIONS/$SID" 2>/dev/null
exit 0

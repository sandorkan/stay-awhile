---
description: Close the Waiting Room window and stop its local server
allowed-tools: Bash(python3:*)
---

Close the Waiting Room viewer.

Run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py" stop` and report what it
says in a line.

Mention that the window closes itself straight away: the server tells it it's
stopping before exiting.

This isn't normally needed: the server stops on its own when the last session
ends. It's for putting the window away mid-session, or for starting over if
something looks stuck (`close`, then `/waiting-room:show`).

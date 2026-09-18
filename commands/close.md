---
description: Close the Stay awhile window and stop its local server
allowed-tools: Bash(python3:*)
---

Close the Stay awhile viewer.

Run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py" stop` and report what it
says in a line.

On a successful stop, mention that the floating window closes itself straight away: the server tells it it's
stopping before exiting. A browser-created host window may remain open. If the
command cannot verify the server's ownership, relay that warning instead of
claiming it was closed.

This isn't normally needed: the server stops on its own when the last session
ends. It's for putting the window away mid-session, or for starting over if
something looks stuck (`close`, then `/stay-awhile:show`).

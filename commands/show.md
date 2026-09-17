---
description: Open the Waiting Room window (starts the local viewer server if needed)
allowed-tools: Bash(python3:*)
---

Open the Waiting Room viewer.

Run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py" open`. It starts the
local server if it isn't already running, opens a small window, and prints an
explanation of how to use it.

**Show that output to the user as it is.** Don't paraphrase, summarise or
re-order it: it's written to be read directly, and rewording it has produced
wrong descriptions before.

If the output says the status line isn't configured, tell them to run
`/waiting-room:init` first — without it the scene runs, but with no usage
numbers.

Don't mention stopping the server: it stops on its own when the last session
ends. `/waiting-room:close` exists if they want it gone sooner.

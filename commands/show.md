---
description: Open the Stay awhile window (starts the local viewer server if needed)
allowed-tools: Bash(python3:*)
---

Open the Stay awhile viewer.

Run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py" open`. It starts the
local server if it isn't already running, opens a small window, and prints an
explanation of how to use it.

**Show that output to the user as it is.** Don't paraphrase, summarise or
re-order it: it's written to be read directly, and rewording it has produced
wrong descriptions before.

If the output says the status line is not configured, tell them to run
`/stay-awhile:init` first — without it the scene runs, but with no usage
numbers.

Don't mention stopping the server: it stops on its own when the last session
ends. `/stay-awhile:close` exists if they want it gone sooner.

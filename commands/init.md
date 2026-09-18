---
description: One-time setup for the Stay awhile viewer (adds the status line to your settings)
allowed-tools: Bash(python3:*)
---

Set up the Stay awhile viewer. This is meant to be run **once, after
installing the plugin** — the audio side works without it, but the viewer's
usage numbers do not.

Run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py" status` and show what it
reports. Then:

- **Status line not configured** — run `install` (no flags) to print the plan
  and show it to the user. Say plainly that a configured status line replaces
  some of Claude Code's footer hints (`esc to interrupt`, `? for shortcuts`).
  Ask whether to apply it. Only if they agree, run `install --apply`. Never
  apply without asking: it edits their own settings.json.
- **Another status line is configured** — the plan chains to it rather than
  replacing it. Show the chained command so they can see theirs is kept.
- **Already configured** — still run `install` without flags to check for
  options to migrate from Waiting Room. If it proposes a migration, show the
  plan and ask before running `install --apply`. Otherwise nothing needs changing.

Explain briefly why it's needed: the 5-hour and weekly percentages only reach
a plugin through the status line, so without it the scene can't show them.

Finish by telling them to run `/stay-awhile:show` to open the window. Don't
open it yourself here.

If `status` reports a settings.json that isn't valid JSON, stop and tell the
user; don't try to repair it.

---
description: Turn the Stay awhile sound back on after /stay-awhile:mute
allowed-tools: Bash(python3:*), Bash(python:*)
---

Turn the sound back on.

Run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py" sound on` and relay
what it prints in one line. Sound returns with the next prompt or tool call;
nothing needs restarting.

The commands here say `python3`. Where that is not on PATH (typical on
Windows), run the same command with `python`.

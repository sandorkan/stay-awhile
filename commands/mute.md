---
description: Turn the Stay awhile sound off (loop and cues) until you unmute
allowed-tools: Bash(python3:*), Bash(python:*)
---

Turn the sound off.

Run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py" sound off` and relay
what it prints in one line. It fades the loop that is playing now and keeps
every session silent, cues included, until `/stay-awhile:unmute`. The chosen
music and volume are kept.

The commands here say `python3`. Where that is not on PATH (typical on
Windows), run the same command with `python`.

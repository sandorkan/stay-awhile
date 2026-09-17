---
description: Hear the Waiting Room tracks and choose one
allowed-tools: Bash(python3:*), AskUserQuestion
---

Let the user hear the tracks and pick one. Take no arguments; this is a menu,
not a syntax to remember.

Start with `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py" music list`, which
prints every track grouped by category and marks the current one with `*`.

Then ask, using the question tool so they can click rather than type. **Each
question takes at most four options** — more than that is rejected, and the
tool adds its own free-text choice, so anything extra goes in the wording.

1. **Which kind?** Exactly these four: breathing, ambient, 8-bit, soundscapes.
   One line each: breathing is paced bowls, ambient is slow synthesized music,
   8-bit is the same songs on NES-style voices, soundscapes are recordings.
   Add to the question text that they can type `shuffle`, `heartbeat` or
   `none` instead.
2. **Which one?** The four tracks in that category, marking the current one.
   If they asked for shuffle, offer `shuffle-ambient`, `shuffle-8-bit` and
   `shuffle-soundscapes` (there is no shuffle-breathing: swapping patterns
   between prompts breaks the rhythm).
3. **Play it**: `music play <track>`. Five seconds, the loop alone, and it
   changes nothing. Say what's playing while it does.
4. **Keep it?** Three options: keep, hear another, cancel. On "hear another",
   go back to step 2.
5. **On keep**: `music set <track>`. Say it applies from their next prompt and
   that settings.json is backed up first.

Play before setting, so nothing changes until they say so. If they already
know what they want, setting it directly is fine — but still play it first
unless they say not to.

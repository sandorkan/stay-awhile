# Waiting Room

Claude Code plugin: hooks in `hooks/hooks.json` call `scripts/start.sh` and
`scripts/stop.sh`, which play loops and cues from `sounds/`. See README.md for
behaviour and options.

## Testing

- `scripts/simulate.sh [done|failed|needs-you] [seconds]` fires the hooks the
  way a turn would. Costs no tokens; use it before a real session.
- For silent tests set `CLAUDE_PLUGIN_OPTION_VOLUME=0` and point
  `CLAUDE_PLUGIN_DATA` at a scratch dir, so a test never touches a real
  session's loop. Hooks read JSON on stdin: `echo '{"session_id":"A"}' | scripts/start.sh`.
- Run test scripts with `/bin/bash`, not zsh: `set -m` behaves differently.
- Only a real session verifies hook wiring (which events fire when). Cheapest:
  `claude --plugin-dir . --model haiku`, then ask it to run `sleep 10 && false`.

## Hook scripts

- Must exit 0 on every path. Exit 2 on UserPromptSubmit rejects the prompt.
- Anything slow is backgrounded through `detach` (lib.sh), with stdio closed,
  or Claude Code waits on it.
- macOS has no `setsid`; `detach` uses `set -m` for a process group instead.
- Loops on macOS use AVAudioPlayer via `osascript`, not repeated `afplay` —
  restarting afplay leaves a ~0.5s gap at every loop point.
- Only kill PIDs that pass `ours` (command line contains the plugin path).

## Wait logging

- `wait_start` / `wait_end` in lib.sh write `$DATA/started/<session>` and
  append to `$DATA/waits.log`. Measurement first: the point is to learn how
  long waits actually are before building anything that reacts to their length.
- `needs-you` deliberately keeps the start file, so one turn logs twice: the
  stretch up to the permission prompt, then the whole turn.
- Hooks read stdin once. start.sh and stop.sh capture it into `INPUT`, then
  parse fields out of that with `json_str`; calling a parser twice on stdin
  returns nothing the second time.
- Prompt metrics (words, images, paths…) come from `prompt-metrics.py`, which
  reads the last real user message in the transcript — tool-result messages
  don't count. It runs at turn end, not on UserPromptSubmit: that event blocks
  the prompt, and the prompt isn't in the transcript yet anyway. It reads only
  the last 512 KB, so a 131 MB transcript still costs ~80 ms.
- Missing python3 or transcript logs zeros in columns 5-13. Zero means
  "couldn't measure" — keep that distinction in anything that reads the log.
- `wait_start` flags every other in-flight session as switched away from, so
  the switch is recorded against the turn that got abandoned, not the new one.

## Status line

- `scripts/statusline.sh` is the only way to get real rate-limit numbers
  locally: hooks don't carry them, and there's no `claude usage` command. It
  saves the raw payload to `$DATA/status.json` (atomic write) for the viewer.
- It runs on every UI update and is cancelled if a newer update arrives while
  it's still going, so it must stay ~free: no network, no git, no sleeps.
  Measured ~25ms per run with jq present; it falls back to sed without jq.
- `$DATA/ran-out` records when the 5-hour window first hit 100%. The payload
  only gives the current level, and the viewer's moon needs a rise time.
- Configured by the user in settings.json, not shipped by the plugin, so it
  can chain to an existing status line instead of replacing it.

## Sounds

- `scripts/gen-sounds.py <name ...>` regenerates only the named sounds, e.g.
  `8-bit/harbor`. **With no arguments it rewrites every generated file.**
- `sounds/soundscapes/` are ElevenLabs recordings, not generated. Never
  regenerate or overwrite them.
- Songs share compositions: `HOLD_BARS` drives both `ambient/hold-music` and
  `8-bit/town`. After refactoring the generator, compare `md5 -q` of existing
  files before and after — they should be byte-identical.
- Keep new loops level with the rest: RMS about 0.10–0.14, measured with a few
  lines of Python.
- A new track must be added to `userConfig.track.options` in
  `.claude-plugin/plugin.json`, or the `/config` picker won't offer it.
  Shuffle picks up new files in a category folder on its own.

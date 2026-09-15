# Working Sounds

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

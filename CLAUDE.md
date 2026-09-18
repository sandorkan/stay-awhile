# Waiting Room

Claude Code plugin: hooks in `hooks/hooks.json` call `scripts/start.sh` and
`scripts/stop.sh`, which play loops and cues from `sounds/`. See README.md for
behaviour and options.

## Testing

- `scripts/simulate.sh [done|failed|needs-you] [seconds]` fires the hooks the
  way a turn would. Costs no tokens; use it before a real session.
- For silent tests set `CLAUDE_PLUGIN_OPTION_VOLUME=0`,
  `WAITING_ROOM_SIMULATION=1`, and `CLAUDE_PLUGIN_DATA` to a scratch dir.
  Simulation mode suppresses publication of the shared data-directory pointer.
  `simulate.sh` always creates its own temporary data directory, even if it
  inherits `CLAUDE_PLUGIN_DATA`. Hooks read JSON on stdin: `echo '{"session_id":"A"}' | scripts/start.sh`.
- Run test scripts with `/bin/bash`, not zsh: `set -m` behaves differently.
- Only a real session verifies hook wiring (which events fire when). Cheapest:
  `claude --plugin-dir . --model haiku`, then ask it to run `sleep 10 && false`.

- Regression checks: `python3 -m unittest discover -s tests -v` and
  `node tests/viewer.cjs`. These use temporary data and DOM mocks; they do not
  replace a real Claude session or a browser PiP smoke test.

## Hook scripts

- Must exit 0 on every path. Exit 2 on UserPromptSubmit rejects the prompt.
- Anything slow is backgrounded through `detach` (lib.sh), with stdio closed,
  or Claude Code waits on it.
- macOS has no `setsid`; `detach` uses `set -m` for a process group instead.
- Loops on macOS use AVAudioPlayer via `osascript`, not repeated `afplay` —
  restarting afplay leaves a ~0.5s gap at every loop point.
- Only kill audio PIDs that pass `ours` (command line contains the plugin path).
  Each fade watchdog owns `loop.stop.<PID>` and must never delete `loop.pid`.
- `session.sh` registers SessionStart; prompts and the status line refresh
  `sessions/<sid>`. SessionEnd removes it. `active/` means working, while
  `started/` also includes permission-paused turns; do not interchange them.
- New prompts resolve music via `setup.py music current`, reading the saved
  user preference ahead of Claude's session-cached track environment. Simulations
  bypass this read. `turn-track/<sid>` holds the resolved song for permission
  resumes; completed turns remove it. Saving settings must not restart audio.
- Server PID records include process start time and command. Never signal an
  unverified or legacy bare PID; refuse safely if ownership can't be established.

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
  Each window is cached independently in `limits-<window>.json`, so partial
  payloads cannot erase another window. Cached windows expire at `resets_at`; a missing payload is not proof that
  an old, already-expired limit is still current.
- Configured by the user in settings.json, not shipped by the plugin, so it
  can chain to an existing status line instead of replacing it.

## Viewer

- `scripts/setup.py` owns anything that touches the user's settings.json.
  Its `install` command is dry-run by default; `--apply` writes after a backup and
  chains to an existing statusLine instead of replacing it.
- `commands/` holds four slash commands: `init` (one-time status-line setup,
  must ask before applying), `show` (start the server, open the window),
  `close` and `music` (audition and choose a loop). Keep them thin: logic belongs
  in setup.py, and `show` relays
  setup.py's printed explanation rather than writing its own — a model
  paraphrasing it has produced wrong descriptions.
- `scripts/viewer-server.py` reads hook-owned data without modifying it. It
  writes and cleans up its own `server.pid` identity record; `/settings` delegates
  music saves to `setup.save_music`, also used by the music command. Keep saves
  atomic, preserve unrelated settings, and never start/stop playback here.
- `/settings` requires the viewer's custom header and a loopback Host with the
  server's port; reject foreign origins and do not enable CORS. Never expose
  arbitrary settings edits or shell commands through this endpoint.
- Scene selection (`wr-scene` in localStorage) is browser-local. Both scenes
  share usage, reset timing, HUD, and history. Alpine terrain overlays the sky
  after clouds/stars; foreground pines overlay birds. Cache keys include scene
  identity. Keep lake rings out of the river and verify all four lighting moods.
- The gear and its settings panel live inside the adopted frame. The turn-stats
  checkbox keeps the `wr-strip-2` browser preference. File demos disable music
  changes. Keyboard shortcuts must not fire inside form controls.
  It sends the turn's start time, not a clock, so the SSE stream stays quiet
  until something real changes. The moon and reset countdown advance locally.
- The strip uses the local date and excludes `needs-you` checkpoints; it shows
  at most the latest 120 completed turns. The raw log keeps every checkpoint.
- PiP moves the scene DOM into another document. Capture references before
  adoption; don't look up moved nodes through the host document or use implicit
  named window globals. Test updates and toggling after adoption, too.
- The page runs from file:// too (sample data, controls) — that's how to work
  on the scene without a server. Headless Chrome can't screenshot it while an
  SSE connection is open; use file:// for rendering checks.
- Syntax-checking the page is not enough: a runtime ReferenceError leaves a
  black canvas. Load it in headless Chrome and grep the console for `Uncaught`.

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

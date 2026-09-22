# Stay awhile

Claude Code plugin: hooks in `hooks/hooks.json` call `scripts/start.sh` and
`scripts/stop.sh`, which play loops and cues from `sounds/`. See README.md for
behaviour and options.

## Testing

- `scripts/simulate.sh [done|failed|needs-you] [seconds]` fires the hooks the
  way a turn would. Costs no tokens; use it before a real session.
- For silent tests set `CLAUDE_PLUGIN_OPTION_VOLUME=0`,
  `STAY_AWHILE_SIMULATION=1`, and `CLAUDE_PLUGIN_DATA` to a scratch dir.
  Simulation mode suppresses publication of the shared data-directory pointer.
  `simulate.sh` always creates its own temporary data directory, even if it
  inherits `CLAUDE_PLUGIN_DATA`. Hooks read JSON on stdin: `echo '{"session_id":"A"}' | scripts/start.sh`.
- Run test scripts with `/bin/bash`, not zsh: `set -m` behaves differently.
- Only a real session verifies hook wiring (which events fire when). Cheapest:
  `claude --plugin-dir . --model haiku`, then ask it to run `sleep 10 && false`.
- **Never run a hook without `STAY_AWHILE_SIMULATION=1` while pointing
  `CLAUDE_PLUGIN_DATA` at a scratch directory.** Non-simulation hooks publish
  that directory in `~/.claude/waiting-room/data-dir`, and every live hook
  then follows it. `data_dir_ok` now ignores pointers outside `.claude`, but
  the flag is still the rule.

- Regression checks: `python3 -m unittest discover -s tests -v` and
  `node tests/viewer.cjs`. These use temporary data and DOM mocks; they do not
  replace a real Claude session or a browser PiP smoke test. On Windows use
  `python`; the tests run the scripts through Git's bash (`BASH` in
  `test_runtime.py`) and skip the symlink test without that privilege.

## Windows

- Claude Code runs hooks and `Bash(...)` tools in Git for Windows' bash
  (MSYS). `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA` arrive as `C:/...`
  with forward slashes; hook JSON carries `C:\\Users\\...`. MSYS accepts both,
  and lib.sh normalises with `slashes VAR PATH`, which splits on the
  backslash with `read -a` and rejoins. Do not use `${var//\\//}` or its
  quoted variants: each behaves differently across bash 3.2 and 5.
- `ours()` reads `/proc/<pid>/cmdline` on Windows (no fork, full length) and
  compares with slashes normalised. Not MSYS `ps`: it has no `-o` and it
  truncates rows to `$COLUMNS`, which Claude Code sets for hooks but not for
  the Bash tool — so a bug can pass every simulation and still bite in a real
  session. Elsewhere `ps -ww` for the same reason. Every detached job must
  carry the plugin root in its command line, spelled with forward slashes:
  `play.ps1` gets `-File C:/.../play.ps1`. `kill -- -PGID` does take native
  children down.
- The Windows player is `scripts/play.ps1`: the winmm waveOut API called
  directly, one buffer the device loops itself (gapless). Volume is applied
  to the samples by an IL loop emitted at run time, so 0.4 means the same as
  `afplay -v 0.4`; `waveOutSetVolume` on the handle is *not* linear (0.4 was
  inaudible) and is used only for the fade, and with a device id it does
  nothing to a `PlaySound` stream at all. WPF MediaPlayer and the WMP COM
  object need the Media Feature Pack and were dead on the machine this was
  built on. Audible checks need a person: a process that is alive and exits
  cleanly proved nothing about sound twice. PowerShell can't see its MSYS
  PID, so `start_loop` picks the fade marker and leaves it in `loop.marker`;
  `loop_marker` resolves it, and `fade-cleanup.sh <pid> [marker]` removes it.
- Several sessions share the status files; an idle one repeats stale numbers.
  `newest` in statusline.sh keeps `limits-<window>.max` monotonic within a
  `resets_at`, and the viewer prefers the cached window when it is higher for
  the same reset. Usage cannot fall inside a window, so higher means newer.
- Each external command costs ~100 ms under MSYS, and hooks sit in the
  prompt's critical path. lib.sh provides builtin replacements: `readf`,
  `json_get`, `session_id VAR JSON`, `count_get VAR`, `now_epoch`; use `: >`
  for touch and one `rm -f` for several files. A prompt hook is ~4 forks now
  (python, ps, mv, the player). Measure with the sim before adding one.
- `$PY` (lib.sh) is the Python for helper scripts: `python` first on Windows,
  `python3` elsewhere; empty when neither exists. `setup.py` runs `.sh`
  scripts through `bash_command()` (Git's bash, never `System32\bash.exe`,
  which is WSL) and detaches children with `DETACHED_PROCESS`.
- `runtime.process_identity` reads start time and command line from WMI on
  Windows, so `setup.py stop` can own the server there. `os.kill` is a plain
  terminate: the `bye` SSE event never fires on Windows.
- `.gitattributes` forces LF. With `core.autocrlf=true` git prints CRLF
  warnings on add; that is normal.

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
- New prompts resolve music and volume via `setup.py prefs current` (one
  Python start, tab-separated), reading the saved user preference ahead of
  Claude's session-cached option environment. Simulations bypass this read.
  `turn-track/<sid>` holds the resolved song for permission resumes;
  completed turns remove it. The volume is cached in `$DATA/volume`, which
  lib.sh reads on every hook so cues and resumes match without Python.
  Saving settings must not restart audio.
- Server PID records include process start time and command. Never signal an
  unverified or legacy bare PID; refuse safely if ownership can't be established.

## Wait logging

- `wait_start` / `wait_end` in lib.sh write `$DATA/started/<session>` and
  append to `$DATA/waits.log`. Measurement first: the point is to learn how
  long waits actually are before building anything that reacts to their length.
- `needs-you` deliberately keeps the start file, so one turn logs twice: the
  stretch up to the permission prompt, then the whole turn.
- Hooks read stdin once. start.sh and stop.sh capture it into `INPUT` with a
  builtin `read -d ''`, then parse fields out of that with `json_get` and
  `session_id VAR JSON`; stdin has nothing left for a second reader.
- Prompt metrics (words, images, paths…) come from `prompt-metrics.py`, which
  reads the last real user message in the transcript — tool-result messages
  don't count. It runs at turn end, not on UserPromptSubmit: that event blocks
  the prompt, and the prompt isn't in the transcript yet anyway. It reads only
  the last 512 KB, so a 131 MB transcript still costs ~80 ms.
- Missing Python or transcript logs zeros in columns 5-13. Zero means
  "couldn't measure" — keep that distinction in anything that reads the log.
  So does a long tool-heavy turn: the last prompt can lie beyond the 512 KB
  tail the metrics script reads.
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
- `commands/` holds six slash commands: `init` (one-time status-line setup,
  must ask before applying), `show` (start the server, open the window),
  `close`, `music` (audition and choose a loop), `mute` and `unmute`. Keep
  them thin: logic belongs in setup.py, and `show` relays setup.py's printed
  explanation rather than writing its own — a model paraphrasing it has
  produced wrong descriptions.
- Mute is the file `$DATA/muted`, not a setting: `scripts/sound.sh off`
  writes it and fades the running loop through `stop_loop`; `start_loop`,
  `play_once` and the eye-cue arming return early while it exists; `on`
  removes it and the next resume hook restarts the loop. It is the one
  `/settings` write that touches playback, on purpose.
- `scripts/viewer-server.py` reads hook-owned data without modifying it. It
  writes and cleans up its own `server.pid` identity record; `/settings`
  accepts exactly `{track, expected}`, `{volume}` or `{muted}` and delegates
  to `setup.save_music` / `setup.save_volume` (thin wrappers over
  `save_option`) / `setup.set_muted`. Keep saves atomic, preserve unrelated
  settings, and never start/stop playback here except through mute.
- `/settings` requires the viewer's custom header and a loopback Host with the
  server's port; reject foreign origins and do not enable CORS. Never expose
  arbitrary settings edits or shell commands through this endpoint.
- Scene selection (`sa-scene` in localStorage) is browser-local. All scenes
  share usage, reset timing, HUD, and history. Alpine terrain overlays the sky
  after clouds/stars; foreground pines overlay birds. Cache keys include scene
  identity. Coast uses its own water, cliff/tower foreground, and dusk/night
  beacon; no lake rings or fireflies. Keep lake rings out of the river and
  verify all four lighting moods for every scene. Desert has a separate
  sandstone palette, cached terraced cliffs, a rocky yucca overlook and subtle heat/dust;
  its effects use the shared reduced-motion clock.
- The gear and its settings panel live inside the adopted frame. The turn-stats
  checkbox keeps the `sa-strip-2` browser preference. File demos disable music
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

## Rename compatibility

- Public identity is `stay-awhile` / **Stay awhile**; command filenames stay
  `init`, `show`, `close`, and `music` and inherit that namespace.
- The public repository is `sandorkan/stay-awhile`. Retain the legacy data
  directory/pointer, old environment-variable fallbacks, and browser-key
  migration intentionally; do not mechanically replace those strings.
- `setup.py install` plans migration of missing legacy plugin options even if
  the status line is already configured. Apply only through its existing
  explicit `--apply` flow; never erase the old configuration entry.

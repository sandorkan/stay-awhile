# Waiting Room

Audio for the dead minute while Claude Code works.

A loop plays while a turn is running and stops when it ends. Finishing,
failing, and needing your input each get a distinct one-shot, so you can tell
what happened without looking at the terminal.

## Why

The wait isn't the expensive part. Switching is.

When a turn takes a minute, the obvious move is to go do something else, and
the something else is usually another conversation. That's the worst available
choice. You leave one task unfinished to pick up another unfinished one, and
part of your attention stays behind on each — what researchers on task
switching call attention residue. You come back having paid to leave and
paying again to return, several times an hour.

The second-best choice is to stay and stare at the terminal, waiting for
output. That keeps the thread but burns the minute on vigilance: watching for
a change that a sound could have told you about.

This plugin is for the third option. The loop says work is still happening, so
there's no reason to check. The cues say what happened, so you can stand up,
look out of the window, or close your eyes without monitoring anything. And
the breathing tracks give you something to *do* that doesn't compete for the
part of your mind still holding the task — following a paced breath costs
almost nothing, where reading another thread costs exactly what you were
about to need.

Two honest caveats. Audio doesn't stop you switching; it removes one reason to
(the uncertainty), and the rest is yours. And background sound can make a wait
comfortable enough that you stop noticing when Claude is slow or heading the
wrong way — which is worth noticing.

## Install

```bash
/plugin marketplace add sandorkan/waiting-room
/plugin install waiting-room@waiting-room-marketplace
```

Or load it locally while developing:

```bash
claude --plugin-dir ./waiting-room
```

To hear it without spending tokens, `scripts/simulate.sh` fires the hooks the
way a turn would:

```bash
scripts/simulate.sh [done|failed|needs-you] [seconds]
CLAUDE_PLUGIN_OPTION_TRACK=soundscapes/rain scripts/simulate.sh done 15
```

## Configure

Run `/config` and pick a track, or set it at install time:

```bash
claude plugin install waiting-room@waiting-room-marketplace \
  --config track=breathing/5.5-5.5-resonance --config volume=0.3
```

| Option          | Default     | Notes |
|-----------------|-------------|-------|
| `track`         | `breathing/4-6-calm` | A loop from the table below, e.g. `8-bit/harbor`; `shuffle-ambient`, `shuffle-8-bit` or `shuffle-soundscapes` for a new random one from that category each prompt; or `none` |
| `volume`        | `0.4`       | 0.0–1.0, applied where the player supports it |
| `cues`          | `true`      | The done / failed / needs-you one-shots |
| `eye_cue_every` | `8`         | Look-away nudge every Nth wait. `0` disables |

The `/config` picker needs Claude Code v2.1.271 or later. On older versions
the field is free text and the values above still work.

## The sounds

**Loops** — each category is a folder in `sounds/`. Shuffle picks from
whatever `.wav` files are in the folder, never the same song twice in a row,
and keeps a song for the whole turn:

| Track | What it is |
|-------|------------|
| `ambient/hold-music`, `ambient/dusk`, `ambient/lantern`, `ambient/drift` | Slow synthesized music: pad, bass, vibraphone-ish arpeggio |
| `8-bit/town`, `8-bit/harbor`, `8-bit/snowfield`, `8-bit/ruins` | The same kind of songs on NES-style voices: triangle bass, pulse-wave pad and arpeggio, fake echo. `town` is hold-music's composition |
| `soundscapes/rain`, `soundscapes/forest`, `soundscapes/beach`, `soundscapes/fireplace` | Recordings |
| `breathing/4-6-calm`, `breathing/5.5-5.5-resonance`, `breathing/4-4-4-4-box`, `breathing/sigh` | Paced breathing, seconds per phase in the name (see below). No shuffle: switching patterns between prompts would break the rhythm |
| `heartbeat` | A soft lub-dub at 60 bpm, for when music is worse than the wait |

**Breathing** — a struck singing bowl marks the start of every phase: the
higher bowl means breathe in, the lower bowl means breathe out, both equally
loud. A soft wooden tap marks a hold. In `sigh`, the higher bowl sounds twice,
the second a little lighter, for the short second inhale.

| Pattern | Rhythm | |
|---------|--------|---|
| `4-6-calm` | in 4 · out 6 | Six breaths a minute with a longer exhale |
| `5.5-5.5-resonance` | in 5.5 · out 5.5 | "Resonance" or "coherent" breathing, about 5.5 breaths a minute |
| `4-4-4-4-box` | in 4 · hold 4 · out 4 · hold 4 | Box breathing |
| `sigh` | in 2 · top-up 1 · out 6 | Cyclic sighing: a nose inhale, a short second inhale to fill up, then a long, slow exhale |

What the evidence supports, plainly:

- **Slow breathing around six breaths a minute** (`4-6-calm` and
  `5.5-5.5-resonance` both sit there) has the best support of these. It
  reliably raises heart-rate variability while you do it, and reviews of
  HRV-biofeedback studies find small-to-moderate reductions in stress and
  anxiety. Most studies are small and short-term. The exact "resonance" rate
  differs from person to person, roughly 4.5–6.5 breaths a minute, so
  5.5 is a sensible middle rather than a personal optimum.
- **A longer exhale than inhale** is widely taught as extra calming. The idea
  is plausible, but the direct evidence that it beats equal-length slow
  breathing is mixed.
- **Cyclic sighing and box breathing** were compared in one randomized study
  (Balban et al., 2023, about 110 people, five minutes a day for a month).
  All breathing groups improved mood somewhat more than a mindfulness group;
  cyclic sighing did best on positive mood. That's one study, and none of
  these patterns has been tested as background audio over long stretches.
- **Box breathing** is popular with the military and first responders; most
  of its reputation comes from that use rather than from research on box
  breathing specifically.

None of this is treatment for anything. You don't have to follow it for a
whole turn, and if you feel light-headed, stop and breathe normally.
4-7-8 and fast "power breathing" patterns are left out on purpose: the first
is meant for a few rounds before sleep, not minutes at a desk, and the second
is hyperventilation.

**Cues** — `done` rises and resolves, `failed` falls, `needs-you` is a double
knock. Different shapes rather than different pitches, so they're
distinguishable from the next room.

`needs-you` plays for permission prompts and questions Claude asks you, and
silences the loop while it waits. The loop comes back when the next tool
runs.

**Eye cue** — every Nth wait, a rising chime means look at something at least
six metres away and blink a few times deliberately; a falling chime twenty
seconds later means come back. It only fires if the turn is still running
after fifteen seconds, and it's cancelled if the turn finishes first. Worth
saying plainly: 20-20-20 is widely recommended and costs nothing, but the
evidence it prevents anything is thinner than its popularity suggests. Treat
it as a nudge to unstick your eyes.

## Replacing the audio

Everything except `sounds/soundscapes/` is synthesized by
`scripts/gen-sounds.py`. Edit the script and re-run it for the sounds you
changed (`python3 scripts/gen-sounds.py 8-bit/harbor`), or drop a replacement
file in `sounds/` under the same name — the scripts resolve by filename.
Running the script with no names regenerates everything, replacements
included. The soundscapes are ElevenLabs recordings.

If you add a song, keep it loopable and unresolved: the wait has
no known length, so anything that builds toward a cadence will keep promising
an ending that doesn't come.

Don't bundle commercial music. A plugin shipping copyrighted tracks gets taken
down rather than popular.

## Usage numbers (the status line)

`scripts/statusline.sh` prints a compact row and saves the payload Claude Code
hands it to `status.json` in the plugin’s data directory. That payload is the only
local source for the numbers `/usage` shows — the 5-hour and weekly
percentages and their reset times — which is what the visual viewer needs.

```
18% · 1:35 · wk 46%
```

These are percentages **used**, followed by hours and minutes until the
five-hour window resets. The weekly percentage also means used.

**After installing the plugin, run `/waiting-room:init` once.** It shows what
it would change, asks before touching your settings, and explains the trade.
Then `/waiting-room:show` opens the window whenever you want it, and
`/waiting-room:close` puts it away early (it stops by itself when your last
session ends).

Under the hood that's `scripts/setup.py`, which also works on its own:

```bash
python3 scripts/setup.py status     # what's configured, is the server up
python3 scripts/setup.py install    # dry run; add --apply to write it
python3 scripts/setup.py open       # start the server and open the viewer
python3 scripts/setup.py stop
```

Or add it to `settings.json` by hand, substituting the actual installed plugin
path printed by `python3 scripts/setup.py status`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/absolute/path/to/waiting-room/scripts/statusline.sh\"",
    "refreshInterval": 5
  }
}
```

`refreshInterval` matters: status-line updates are event-driven and go quiet
while a session is idle, which is exactly when you'd be watching the number.

Two things worth knowing before you add it:

- **A configured status line replaces some of Claude Code's footer hints**
  (`esc to interrupt`, `? for shortcuts`, the voice-dictation hint). That's
  the trade for a permanent usage readout.
- **`rate_limits` only appears for Pro and Max subscribers, and only after the
  session's first API response.** An empty row before then is correct, not a
  failure. Each window also disappears from the payload once it resets.

**Already have a status line?** `/waiting-room:init` offers to chain to it. By
hand, set `CLAUDE_PLUGIN_OPTION_STATUSLINE_CHAIN` to it and its output is printed first, with the
usage segments appended:

```json
"command": "CLAUDE_PLUGIN_OPTION_STATUSLINE_CHAIN='~/.claude/my-statusline.sh' \"/absolute/path/to/waiting-room/scripts/statusline.sh\""
```

## The viewer

`scripts/viewer-server.py` serves `viewer/` on `127.0.0.1:8787` and streams
state to the page as it changes. It reads hook/status data, maintains its own
server identity file, and saves music selections through the setup helper.
The scene shows your usage window as a sky: the sun rises when the window is
fresh and moves toward sunset as you spend it. Its position along the arc
represents the percentage used; the corner label shows the exact percentage.
When the window is spent the moon takes over, carrying the time until reset.
Wind and water move while a turn runs and settle when it ends or waits for input;
a flock lifts when a turn completes. The strip along the bottom shows up
to 120 of today's completed turns, using your computer's local date. Permission
checkpoints stay in the log but don't count as additional turns in the strip.
The strip is hidden initially; press `b` or open the top-right gear and toggle
**Show turn stats**. Its visibility is remembered in this browser. Hover, tap, or use arrow keys on the bars for duration and outcome.

`/waiting-room:show` opens a small host window. Click **Open the window** to
move the scene into a floating, always-on-top window (Chrome and Edge only).
Keep the host open; it can be minimised. Closing the floating window returns
to the launcher. On other browsers, add `?dev` to the URL to view the scene in
the page instead.

For development, `python3 scripts/setup.py open --dev` shows the scene and test
controls, including **pop out ⧉** on supported browsers. Opening
`viewer/scene.html` directly uses sample data instead of live data.

The top-right gear opens **Settings** in both the browser scene and floating
window. **Scene** switches between **Lakeside**, **Alpine Valley**, and
**Coastal Lighthouse**, and **Desert Canyon**, remembered
in this browser. Alpine Valley has layered peaks, snow that changes with the
light, pine forests, drifting mist, and a winding river. Lakeside and Alpine Valley share the
same usage-driven sun/moon cycle, birds, dusk fireflies, and turn stats. River
shimmer and pine movement respond to working/idle state; clouds and mist drift
slowly. Lake rings belong to Lakeside only. Coastal Lighthouse has an open sea,
distant islands, a rocky headland, wind-swept grass, and a shaded lighthouse.
Ocean swells and reflections respond to activity; the lantern and a slow
sweeping beam appear at dusk and remain through the night. Coastal scenes
use the same birds and usage cycle, without lake rings or fireflies. Desert Canyon
looks down from a rocky overlook across overlapping sandstone terraces and a
pale winding wash, with a foreground yucca and clustered dry scrub. Warm rock
colors cool to violet at night, the sun moves across the canyon sky, daytime heat shimmer
softens the distant basin, and occasional dust passes across the canyon floor.
It shares the usage cycle and stars, without water effects or fireflies.

**Music** lists tracks by category, with shuffle options and **Off**.
Selections save automatically to Claude's user plugin settings, sharing the
same preference as `/config` and `/waiting-room:music`. The current loop keeps
playing; each new prompt reads the saved preference directly, so the choice
applies when a new loop starts without restarting Claude. A permission-pause
resume keeps that turn's original track. Reopening the panel reads the latest saved choice. **Show turn
stats** is a browser preference and does not change Claude settings. Press
Escape or click outside the panel to close it.

Music settings need the local server; the `file://` demo still lets you toggle
turn stats but explains that music changes require the live viewer.

The moon advances locally even while no new server events arrive. When a
cached usage window expires, the viewer clears its percentage to a dash until
fresh numbers arrive; it doesn't keep showing an expired “spent” window.
Partial status updates preserve the last known values for each window until
that window resets; a weekly-only update does not clear the five-hour display.

The server stays available while another session is open, including between
prompts. Session hooks register leases and the status line refreshes them.
Leases older than two hours are ignored; after 30 minutes with no viewers or
fresh session/activity leases, an abandoned server retires. A deliberate
`/waiting-room:close` stops it earlier. Server ownership is checked before any
process is signalled.

## How long are the waits, really

Completed turns append tab-separated rows to `waits.log` in the plugin's data
directory; permission prompts append intermediate checkpoints too.
Claude Code normally assigns this directory through `CLAUDE_PLUGIN_DATA`.
`~/.claude/waiting-room/data-dir` points to it, and
`python3 scripts/setup.py status` prints the resolved path. Without an assigned
directory, the fallback is `~/.claude/waiting-room`.
Counts and timings only: no prompt text, no file contents, no path beyond the
project's folder name. Local file, goes nowhere, delete it whenever.

| # | Column | |
|---|--------|---|
| 1 | `ended` | when the turn ended |
| 2 | `seconds` | how long it ran |
| 3 | `outcome` | `done`, `failed`, `needs-you`, `silent` |
| 4 | `session` | Claude Code's session id |
| 5–6 | `words`, `chars` | how long the prompt was |
| 7 | `images` | images attached to it |
| 8–13 | `paths`, `code_blocks`, `urls`, `bullets`, `questions`, `is_slash` | how the prompt was shaped |
| 14–15 | `tools`, `permissions` | tool calls, and permission prompts during the turn |
| 16 | `think_secs` | gap between the last turn ending and this prompt |
| 17 | `switched_away` | 1 if you prompted another session while this one ran |
| 18 | `concurrent` | other turns already running when this one started |
| 19 | `project` | folder name of the working directory |

Columns 5–13 are measured from the transcript's last user message. Zeros there
mean "couldn't measure" (no `python3`, no transcript), not "none".

A turn stopped by a permission prompt logs a `needs-you` line and keeps
counting, so you see both the stretch before the prompt and the whole turn.

```bash
# Use the data directory printed by: python3 scripts/setup.py status
cd /path/to/plugin-data

# the shape of your day
awk -F'\t' '$3 != "needs-you" {n++; s+=$2; if ($2>m) m=$2; if ($2>120) long++}
  END {printf "%d turns, %.0f min waiting, mean %.0fs, longest %ds, %d over 2 min\n",
       n, s/60, (n ? s/n : 0), m, long}' waits.log

# mid-task switching: how often, and what you were leaving
awk -F'\t' '$3 != "needs-you" && $17==1 {n++; s+=$2} END {printf "%d switches, average turn %.0fs\n", n, (n ? s/n : 0)}' waits.log

# do longer prompts mean fewer corrections? (a turn re-prompted within 20s)
awk -F'\t' '$3 == "needs-you" {next} NR>1 && $16<20 && $16>=0 {short[bucket]++} {bucket = ($5<25 ? "under 25 words" : "25+ words"); all[bucket]++}
  END {for (b in all) printf "%-15s %d turns, %d quick re-prompts\n", b, all[b], short[b]}' waits.log
```

## Choosing music

`/waiting-room:music` opens a category/track menu, plays a short preview, and
asks whether to keep it. Previews use a separate temporary directory and
never redirect live status data or stop another session's audio. Keeping a
track backs up `settings.json` and saves the choice without interrupting audio.
The viewer's Music picker uses the same save function, with atomic writes and
checks for a selection changed elsewhere. New turns read the user preference
directly because Claude can keep plugin option environment variables unchanged
for an entire session. A valid saved track takes priority over the hook's track
environment variable; missing or unreadable settings fall back to that variable.
Simulations and previews always honor their explicit track instead. An already
playing loop shared with another session continues until all active turns stop.
You can also run `python3 scripts/setup.py music list`, `music play <track>`,
and `music set <track>` directly.

## Requirements

The viewer and setup commands need Python 3. The floating window needs a
browser with Document Picture-in-Picture support (Chrome or Edge); the regular
`?dev` page works without that feature. `jq` is optional for the status line.

An audio player on `PATH`: `afplay` (macOS), `paplay` or `aplay` (Linux),
`ffplay` (anywhere), or PowerShell (Windows/WSL). With none of them the plugin
does nothing rather than erroring.

## Known limits

**One bed at a time.** Several sessions working at once share a single loop,
because overlapping beds sound like mud. It keeps playing until the last of
them stops. A session killed without a clean exit is forgotten after two
hours.

**Interrupts.** Claude Code has no hook for pressing Esc. If a turn you
interrupt keeps the loop playing, it stops when Claude Code reports you idle,
or at your next prompt.

**No per-session identity.** You can't tell which session just finished. Pitch
-shifting per session would fix it and needs `sox` or `ffmpeg`.

**No progress texture.** A `PostToolBatch` hook emitting one blip per batch
would let you hear pace — fast ticking means it's chewing through edits, long
gaps mean it's thinking. Left out of v1 to keep the surface small.

## License

MIT. Audio generated by `scripts/gen-sounds.py` is released under CC0.

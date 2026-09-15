# Working Sounds

Audio for the dead minute while Claude Code works.

A loop plays while a turn is running and stops when it ends. Finishing,
failing, and needing your input each get a distinct one-shot, so you can tell
what happened without looking at the terminal.

## Install

```bash
/plugin marketplace add sandorkan/claude-working-sounds
/plugin install working-sounds@working-sounds-marketplace
```

Or load it locally while developing:

```bash
claude --plugin-dir ./claude-working-sounds
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
claude plugin install working-sounds@working-sounds-marketplace \
  --config track=breathing --config volume=0.3
```

| Option          | Default     | Notes |
|-----------------|-------------|-------|
| `track`         | `breathing` | A loop from the table below, e.g. `8-bit/harbor`; `shuffle-ambient`, `shuffle-8-bit` or `shuffle-soundscapes` for a new random one from that category each prompt; or `none` |
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
| `breathing` | Paces 4-in / 6-out with singing bowls: a higher bowl to breathe in, a lower one to breathe out |
| `heartbeat` | A soft lub-dub at 60 bpm, for when music is worse than the wait |

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

## Requirements

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

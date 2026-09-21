# Audio and configuration

[Back to the README](../README.md)

For music and volume, the live viewer’s gear menu is the quickest option.
`/config` also exposes cue settings and the look-away interval. You can set
options at install time:

```bash
claude plugin install stay-awhile@stay-awhile-marketplace \
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

## Tracks and cues

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

| Pattern | Rhythm | Notes |
|---------|--------|---|
| `4-6-calm` | in 4 · out 6 | Six breaths a minute with a longer exhale |
| `5.5-5.5-resonance` | in 5.5 · out 5.5 | "Resonance" or "coherent" breathing, about 5.5 breaths a minute |
| `4-4-4-4-box` | in 4 · hold 4 · out 4 · hold 4 | Box breathing |
| `sigh` | in 2 · top-up 1 · out 6 | Cyclic sighing: a nose inhale, a short second inhale to fill up, then a long, slow exhale |

These are optional pacing cues, not a requirement to follow a breathing
pattern for a whole turn. Choose a rhythm that feels comfortable, or use music
or a soundscape instead. No health benefit is promised by this plugin.

**Cues** — `done` rises and resolves, `failed` falls, `needs-you` is a double
knock. Different shapes rather than different pitches, so they're
distinguishable from the next room.

`needs-you` plays for permission prompts and questions Claude asks you, and
silences the loop while it waits. The loop comes back when the next tool
runs.

**Eye cue** — every Nth wait, a rising chime means look at something at least
six metres away and blink a few times deliberately; a falling chime twenty
seconds later means come back. It only fires if the turn is still running
after fifteen seconds, and it's cancelled if the turn finishes first. Use it as a reminder to take a brief screen break.

## Choosing and previewing music

`/stay-awhile:music` opens a category/track menu, plays a short preview, and
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

## Replacing audio

Everything except `sounds/soundscapes/` is synthesized by
`scripts/gen-sounds.py`. Edit the script and re-run it for the sounds you
changed (`python3 scripts/gen-sounds.py 8-bit/harbor`), or drop a replacement
file in `sounds/` under the same name — the scripts resolve by filename.
Running the script with no names regenerates everything, replacements
included. The soundscapes are ElevenLabs recordings.

If you add a song, keep it loopable and unresolved: the wait has
no known length, so anything that builds toward a cadence will keep promising
an ending that doesn't come.

Only add audio you have permission to redistribute.

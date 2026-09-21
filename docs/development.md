# Development

[Back to the README](../README.md)

From the parent of your checkout:

```bash
claude --plugin-dir ./stay-awhile
```

From the repository root, audition the hooks without an API request:

```bash
scripts/simulate.sh done 10
CLAUDE_PLUGIN_OPTION_TRACK=soundscapes/rain scripts/simulate.sh done 15
```

The simulator accepts `done`, `failed`, or `needs-you`, followed by a duration
in seconds. It uses an isolated temporary data directory.

Open the viewer with its test controls:

```bash
python3 scripts/setup.py open --dev
```

The development page includes usage controls and animation triggers. Open
`viewer/scene.html` directly for sample data without a server. Music and volume
changes require the live server. The **pop out** button is available in
supported browsers.

Run the regression checks:

```bash
python3 -m unittest discover -s tests -v
node tests/viewer.cjs
```

The viewer checks model DOM adoption, settings, scene selection, lighting,
and animation. They do not replace checking a real browser pop-out or listening
to playback on the target platform. See [CLAUDE.md](../CLAUDE.md) for contributor
notes and [audio customization](audio.md#replacing-audio) for sound generation.

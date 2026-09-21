# Stay awhile v0.1.0

Draft release notes. Version matches the plugin manifest. Sandro confirmed
the installation and viewer checks in [the launch plan](launch-plan.md) passed;
release publication is pending.

---

A little atmosphere to keep you with the task.

Stay awhile adds ambient audio and living pixel-art landscapes to Claude Code,
designed to help you stay with one task while Claude works.

## What's included

- Music during working turns, with distinct cues for completion, failure, and
  requests for your input.
- Four animated scenes: Lakeside, Alpine Valley, Coastal Lighthouse, and
  Desert Canyon.
- A floating viewer with usage percentages, reset time, and optional turn history.
- Settings for scene, music, volume, and turn stats inside the viewer.
- Optional support links in the README and viewer settings.

## Install

Run inside Claude Code:

```text
/plugin marketplace add sandorkan/stay-awhile
/plugin install stay-awhile@stay-awhile-marketplace
/reload-plugins
/stay-awhile:init
/stay-awhile:show
```

Run `/reload-plugins` after installation to load the plugin into the current
session before testing audio or running its commands.

The viewer needs Python 3. Chrome or Edge is required for the floating window;
the scene can also run in a regular browser tab. Audio requirements vary by
platform. See the [README](https://github.com/sandorkan/stay-awhile#quick-start)
for setup instructions and troubleshooting.

`init` proposes a status-line integration and asks before applying it. This
provides the viewer's usage information; audio can work without it.

## Things to know

- The sun and moon follow the usage window, not the local time of day.
- Music and volume changes apply when a new loop starts; they do not change
  playback already in progress.
- Concurrent sessions share one background loop.
- Browser pop-out behavior and audible playback need checking on the target
  platform; automated tests alone do not verify them.

Found a problem or have an idea? Please [open an issue](https://github.com/sandorkan/stay-awhile/issues)
with your platform, what happened, and steps to reproduce it.

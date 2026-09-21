# Platform requirements

[Back to the README](../README.md)

The viewer and setup commands need Python 3, on `PATH` as `python3` or
`python`. The floating window needs a browser with Document
Picture-in-Picture support (Chrome or Edge); the regular `?dev` page works
without that feature. `jq` is optional for the status line.

An audio player on `PATH`: `afplay` (macOS), `paplay` or `aplay` (Linux),
`ffplay` (anywhere), or PowerShell (Windows/WSL). With none of them the plugin
does nothing rather than erroring.

### Windows

Install [Git for Windows](https://gitforwindows.org/): Claude Code runs hook
commands in its bash, and the plugin's scripts are bash. Python 3 from
python.org or the Store both work (`python` is preferred, because the
`python3` alias is slower or a Store stub).

Audio goes through `scripts/play.ps1`, which uses core Windows audio (winmm)
via PowerShell: loops repeat without a gap, `volume` applies, and the loop
fades out when a turn ends. It needs no Media Feature Pack, so N editions and
locked-down machines work too. The first cue after a prompt arrives about half
a second late — that is PowerShell starting.

Hooks cost more here than on macOS because every external command is a
process spawn (~100 ms). The scripts are written to fork as little as
possible; a prompt or tool call still adds roughly 0.3–0.5 s on a typical
laptop. `python3 scripts/setup.py open` finds Chrome or Edge under Program
Files. WSL is untested but should behave like Linux with PowerShell as the
player.

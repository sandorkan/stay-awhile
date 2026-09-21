# Upgrading from Waiting Room

[Back to the README](../README.md)

The plugin is now **Stay awhile**, with commands under `/stay-awhile:`. The
GitHub repository is `sandorkan/stay-awhile`; the installed plugin is
`stay-awhile@stay-awhile-marketplace`. Disable the old `waiting-room` plugin
before enabling the renamed one, so hooks do not run twice.

Run `/stay-awhile:init` after installing. Its setup plan copies missing plugin
options from the old identity, preserving existing Stay awhile choices. It
also updates an old viewer status-line path rather than chaining it twice.
The previous plugin settings are retained for rollback.

The existing `~/.claude/waiting-room` data directory and pointer deliberately
keep their old paths for compatibility. If a previous pointer exists, the
renamed hooks reuse that directory so turn history stays available. Browser
scene and turn-strip preferences migrate on first load. The old
`WAITING_ROOM_PORT` and `WAITING_ROOM_SIMULATION` environment variables remain
accepted as fallbacks for `STAY_AWHILE_PORT` and `STAY_AWHILE_SIMULATION`.

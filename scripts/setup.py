#!/usr/bin/env python3
"""Set up and run the Waiting Room viewer.

    setup.py status              what's configured, and whether the server runs
    setup.py install             show what would change in settings.json
    setup.py install --apply     make those changes (backs the file up first)
    setup.py start | stop        the local viewer server
    setup.py open                start it if needed, then open the viewer

A plugin can't ship a statusLine — plugin settings.json only supports `agent`
and `subagentStatusLine` — so the one setting has to go in the user's own
settings.json. That's what `install` does, chaining to an existing status line
rather than replacing it.
"""

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import time
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
STATUSLINE = os.path.join(HERE, "statusline.sh")
SERVER = os.path.join(HERE, "viewer-server.py")
SETTINGS = os.path.expanduser("~/.claude/settings.json")
DEFAULT_HOME = os.path.expanduser("~/.claude/waiting-room")


def resolve_data():
    """The hooks publish their real data dir in a pointer file; they're the only
    ones who know it, since Claude Code assigns it per plugin."""
    env = os.environ.get("CLAUDE_PLUGIN_DATA")
    if env:
        return env
    try:
        with open(os.path.join(DEFAULT_HOME, "data-dir"), encoding="utf-8") as f:
            pointed = f.read().strip()
        if os.path.isdir(pointed):
            return pointed
    except OSError:
        pass
    return DEFAULT_HOME


DATA = resolve_data()
PORT = int(os.environ.get("WAITING_ROOM_PORT", 8787))
URL = f"http://127.0.0.1:{PORT}/"


# ----------------------------------------------------------------- helpers

def load_settings():
    try:
        with open(SETTINGS, encoding="utf-8") as f:
            return json.load(f), None
    except FileNotFoundError:
        return {}, None
    except ValueError as e:
        return None, f"{SETTINGS} isn't valid JSON ({e}); fix it first"


def server_running():
    with socket.socket() as s:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", PORT)) == 0


def statusline_plan(settings):
    """(action, new statusLine value, human explanation)."""
    current = settings.get("statusLine")
    if isinstance(current, dict) and STATUSLINE in str(current.get("command", "")):
        return "keep", current, "status line already points at Waiting Room"
    entry = {"type": "command", "command": STATUSLINE, "refreshInterval": 5}
    if not current:
        return "add", entry, "no status line configured — add Waiting Room's"
    existing = current.get("command", "") if isinstance(current, dict) else str(current)
    entry["command"] = (f"CLAUDE_PLUGIN_OPTION_STATUSLINE_CHAIN={json.dumps(existing)} "
                        f"{STATUSLINE}")
    return "chain", entry, f"keep your status line ({existing}) and append the usage segments"


# ----------------------------------------------------------------- commands

# ----------------------------------------------------------------- music

CUES = {"done", "failed", "needs-you", "look-away", "come-back"}
SOUNDS = os.path.join(ROOT, "sounds")


def tracks():
    """Every playable loop, grouped: {category or '': [names]}. Categories are
    folders, so a new one appears here the moment sounds are dropped in."""
    found = {}
    for entry in sorted(os.listdir(SOUNDS)):
        full = os.path.join(SOUNDS, entry)
        if os.path.isdir(full):
            names = sorted(f[:-4] for f in os.listdir(full) if f.endswith(".wav"))
            if names:
                found[entry] = [f"{entry}/{n}" for n in names]
        elif entry.endswith(".wav") and entry[:-4] not in CUES:
            found.setdefault("", []).append(entry[:-4])
    return found


def plugin_id(settings):
    """The key this plugin's options live under. An inline (--plugin-dir) load
    and a marketplace install use different ids, so prefer what's already there."""
    for key in (settings.get("pluginConfigs") or {}):
        if key.split("@")[0] == "waiting-room":
            return key
    for key in (settings.get("enabledPlugins") or {}):
        if key.split("@")[0] == "waiting-room":
            return key
    return "waiting-room@inline"


def current_track(settings):
    pid = plugin_id(settings)
    return ((settings.get("pluginConfigs") or {}).get(pid) or {}).get("options", {}).get("track")


def resolve(name, grouped):
    """Accept a full name, or a bare one if it's unambiguous."""
    every = [t for group in grouped.values() for t in group]
    specials = ["none"] + [f"shuffle-{c}" for c in grouped if c and c != "breathing"]
    if name in every or name in specials:
        return name
    hits = [t for t in every if t.split("/")[-1] == name]
    return hits[0] if len(hits) == 1 else None


def cmd_music(args):
    settings, err = load_settings()
    if err:
        print(err, file=sys.stderr)
        return 1
    grouped, now = tracks(), current_track(settings)

    if args.action == "list":
        for group, names in grouped.items():
            print(f"{group or 'other'}:")
            for n in names:
                print(f"  {'*' if n == now else ' '} {n}")
        print("shuffle:")
        for c in grouped:
            # no shuffle for breathing: swapping patterns between prompts breaks
            # the rhythm you're settling into
            if c and c != "breathing":
                print(f"  {'*' if now == 'shuffle-' + c else ' '} shuffle-{c}")
        print(f"  {'*' if now == 'none' else ' '} none")
        print(f"\ncurrent: {now or 'the default (breathing/4-6-calm)'}")
        return 0

    track = resolve(args.track or "", grouped)
    if not track:
        print(f"no track called {args.track!r} — run `music list`", file=sys.stderr)
        return 1

    if args.action == "play":
        # the simulator plays a loop for N seconds without touching any setting
        # `silent` and no cues: an audition is the loop alone, with no
        # finishing chime and no waiting for one to ring out
        env = dict(os.environ, CLAUDE_PLUGIN_OPTION_TRACK=track,
                   CLAUDE_PLUGIN_OPTION_CUES="false")
        subprocess.run([os.path.join(HERE, "simulate.sh"), "silent", str(args.seconds)],
                       env=env, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"played {track}")
        return 0

    # set
    if os.path.exists(SETTINGS):
        backup = f"{SETTINGS}.bak-{datetime.now():%Y%m%d-%H%M%S}"
        shutil.copy2(SETTINGS, backup)
    settings.setdefault("pluginConfigs", {}).setdefault(plugin_id(settings), {}) \
            .setdefault("options", {})["track"] = track
    with open(SETTINGS, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print(f"track set to {track} (under {plugin_id(settings)}); it applies from your next prompt")
    return 0


def cmd_status(_):
    settings, err = load_settings()
    print(f"plugin   {ROOT}")
    print(f"data     {DATA}{'' if os.path.isdir(DATA) else '   (not created yet)'}")
    if err:
        print(f"settings {err}")
    else:
        action, _, why = statusline_plan(settings)
        print(f"status   {why}")
    stamp = os.path.join(DATA, "status.json")
    if os.path.isfile(stamp):
        age = int(time.time() - os.path.getmtime(stamp))
        print(f"payload  status.json written {age}s ago")
    else:
        print("payload  no status.json yet (needs the status line, and one API response)")
    print(f"server   {'running on ' + URL if server_running() else 'not running'}")
    return 0


def cmd_install(args):
    settings, err = load_settings()
    if err:
        print(err, file=sys.stderr)
        return 1
    action, entry, why = statusline_plan(settings)
    if action == "keep":
        print(f"nothing to do: {why}")
        return 0

    print(f"{SETTINGS}")
    print(f"  {why}")
    print("  statusLine = " + json.dumps(entry, indent=2).replace("\n", "\n  "))
    print("\nnote: a configured status line replaces some of Claude Code's footer hints")
    print("      (esc to interrupt, ? for shortcuts).")
    if not args.apply:
        print("\nthis was a dry run — re-run with --apply to write it")
        return 0

    if os.path.exists(SETTINGS):
        backup = f"{SETTINGS}.bak-{datetime.now():%Y%m%d-%H%M%S}"
        shutil.copy2(SETTINGS, backup)
        print(f"\nbacked up to {backup}")
    else:
        os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    settings["statusLine"] = entry
    with open(SETTINGS, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print(f"wrote {SETTINGS}")
    print("Claude Code picks it up on its own; the row appears after the next response.")
    return 0


def cmd_start(_):
    if server_running():
        print(f"already running on {URL}")
        return 0
    os.makedirs(DATA, exist_ok=True)
    log = open(os.path.join(DATA, "viewer-server.log"), "ab")
    proc = subprocess.Popen([sys.executable, SERVER, "--port", str(PORT), "--data", DATA],
                            stdout=log, stderr=log, stdin=subprocess.DEVNULL,
                            start_new_session=True)   # outlives this shell
    for _ in range(20):
        time.sleep(0.1)
        if server_running():
            with open(os.path.join(DATA, "server.pid"), "w") as f:
                f.write(str(proc.pid))
            print(f"viewer on {URL}  (pid {proc.pid})")
            return 0
    print("server didn't come up; see viewer-server.log", file=sys.stderr)
    return 1


def cmd_stop(_):
    # Look in both places: a server started before the data-dir pointer existed
    # left its pidfile under the default home.
    stopped = []
    for d in {DATA, DEFAULT_HOME}:
        pidfile = os.path.join(d, "server.pid")
        try:
            with open(pidfile) as f:
                pid = int(f.read().strip())
            os.kill(pid, 15)
            stopped.append(pid)
        except (OSError, ValueError):
            pass
        try:
            os.remove(pidfile)
        except OSError:
            pass
    if stopped:
        print("stopped " + ", ".join(f"pid {p}" for p in stopped))
    elif server_running():
        print(f"something is listening on {PORT} that we didn't start; stop it yourself")
    else:
        print("no server running")
    return 0


# Printed verbatim after `open`, so the explanation is identical every time
# rather than paraphrased by whoever relays it.
HOW_IT_WORKS = """
Click "Open the window" to get a small window that floats above your terminal
(Chrome and Edge only). The window you just opened only hosts it — minimise it
once the floating one is up, and close the floating one to bring the scene back.

How to read it
  The sun is this session's usage window: it rises at 0% used and sets as you
  approach 100%. Once the window is spent the moon takes over, carrying the
  time until the reset.
  Water and trees move while a turn is running and settle when it ends; birds
  lift when a turn finishes.
  The two corner numbers are the percentage used and the time to reset — the
  same figures as the usage page on claude.ai. Press `b` for today's turns.

Why
  So you stay in one session instead of switching to another while you wait.
  Leaving an unfinished task and coming back costs more than the wait does.

Usage numbers need one API response from Claude Code first, and only exist on
Pro and Max plans; until then they show as a dash.
"""

CHROMES = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
           "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
           "google-chrome", "chromium", "microsoft-edge"]


def cmd_open(args):
    """Open the viewer. In app mode where we can: a small chromeless window is a
    better host for the floating scene than a tab in your main browser."""
    if not server_running() and cmd_start(args) != 0:
        return 1
    url = URL + ("?dev" if getattr(args, "dev", False) else "")
    for chrome in CHROMES:
        path = chrome if os.path.isabs(chrome) else shutil.which(chrome)
        if path and os.path.exists(path):
            subprocess.Popen([path, f"--app={url}", "--window-size=520,300"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
            print(f"opened {url} in a standalone window")
            print(HOW_IT_WORKS)
            return 0
    opener = "open" if sys.platform == "darwin" else "xdg-open"
    subprocess.run([opener, url], check=False)
    print(f"opened {url}")
    print(HOW_IT_WORKS)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("status")
    p = sub.add_parser("install"); p.add_argument("--apply", action="store_true")
    sub.add_parser("start"); sub.add_parser("stop")
    o = sub.add_parser("open"); o.add_argument("--dev", action="store_true",
                                               help="the full page with controls")
    m = sub.add_parser("music")
    m.add_argument("action", choices=["list", "play", "set"])
    m.add_argument("track", nargs="?")
    m.add_argument("--seconds", type=int, default=5)
    args = ap.parse_args()
    return {"status": cmd_status, "install": cmd_install, "start": cmd_start,
            "stop": cmd_stop, "open": cmd_open, "music": cmd_music}.get(args.cmd, cmd_status)(args)


if __name__ == "__main__":
    sys.exit(main())

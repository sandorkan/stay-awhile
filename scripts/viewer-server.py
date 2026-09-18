#!/usr/bin/env python3
"""Serve the viewer and stream what the plugin already wrote to disk.

    python3 scripts/viewer-server.py [--port 8787] [--data DIR] [--open]

Routes:
    /            the scene
    /state       one JSON snapshot (handy for curl)
    /events      the same snapshot pushed on change (server-sent events)

Reads (only its own server.pid identity record is written):
    status.json     the status line's payload — the real rate-limit numbers
    ran-out         when the 5-hour window hit 100%, for the moon's rise
    started/<sid>   a turn in flight: "<epoch> <concurrent> <think>"
    active/<sid>    a session working
    current-track   the loop playing right now
    waits.log       one line per finished turn, for the day strip

Pure stdlib, loopback only. No external network requests.
"""

import argparse
import json
import math
from datetime import datetime
import signal
import os
import socketserver
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from runtime import fresh_markers, write_server_record, remove_server_record

HERE = os.path.dirname(os.path.abspath(__file__))
VIEWER = os.path.join(HERE, os.pardir, "viewer")
DEFAULT_HOME = os.path.expanduser("~/.claude/waiting-room")


def default_data():
    """Where the plugin's hooks actually write, which they publish in a pointer
    file because only they know it (Claude Code assigns it per plugin)."""
    try:
        with open(os.path.join(DEFAULT_HOME, "data-dir"), encoding="utf-8") as f:
            pointed = f.read().strip()
        if os.path.isdir(pointed):
            return pointed
    except OSError:
        pass
    return DEFAULT_HOME


DEFAULT_DATA = default_data()
TAIL_TURNS = 120          # how much of the day the strip shows
POLL_SECONDS = 1.0
HEARTBEAT_SECONDS = 15
IDLE_EXIT_SECONDS = 30 * 60   # nobody watching and no session working: retire

STOPPING = threading.Event()      # set by SIGTERM, so streams can say goodbye

TYPES = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
         ".css": "text/css; charset=utf-8", ".png": "image/png", ".json": "application/json"}


# ----------------------------------------------------------------- reading state

def _num(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) else None


def read_window(limits, name, now=None):
    w = (limits or {}).get(name) or {}
    used, resets = _num(w.get("used_percentage")), _num(w.get("resets_at"))
    now = time.time() if now is None else now
    if resets is not None and resets <= now:
        return None
    return {"used": used, "resets_at": resets} if used is not None else None


def read_turns(path, now=None):
    """Latest completed turns from the local calendar day, oldest first."""
    today = datetime.fromtimestamp(time.time() if now is None else now).astimezone().date()
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            offset = max(0, f.tell() - 64 * 1024)
            f.seek(offset)
            if offset:
                f.readline()  # discard a possibly partial first record
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return []
    out = []
    for line in lines:
        c = line.split("\t")
        if len(c) < 4:
            continue
        try:
            sec = float(c[1])
            ended = datetime.fromisoformat(c[0]).astimezone()
            if (ended.date() != today or c[2] == "needs-you"
                    or not math.isfinite(sec) or sec < 0):
                continue
        except ValueError:
            continue
        out.append({"ended": c[0], "session": c[3], "sec": sec, "outcome": c[2],
                    "switched": len(c) >= 17 and c[16] == "1",
                    "project": c[18] if len(c) >= 19 else ""})
    return out[-TAIL_TURNS:]


def read_state(data):
    now = time.time()
    status = {}
    try:
        with open(os.path.join(data, "status.json"), encoding="utf-8") as f:
            status = json.load(f)
    except (OSError, ValueError):
        pass

    limits = dict(status.get("rate_limits") or {})
    for name in ("five_hour", "seven_day", "spend_limit"):
        # An explicit numeric reading wins, including an expired one. Missing
        # windows may use their own cache, but never beyond its original reset.
        if _num((limits.get(name) or {}).get("used_percentage")) is not None:
            continue
        for filename in (f"limits-{name}.json", "limits.json"):
            try:
                with open(os.path.join(data, filename), encoding="utf-8") as f:
                    cached = (json.load(f) or {}).get("rate_limits") or {}
                window = cached.get(name) or {}
                if _num(window.get("used_percentage")) is not None:
                    limits[name] = window
                    break
            except (OSError, ValueError):
                pass
    active = set(fresh_markers(data, "active", now))
    turns, started = [], []
    try:
        for name in active:
            try:
                with open(os.path.join(data, "started", name), encoding="utf-8") as f:
                    began = int(f.read().split()[0])
                started.append({"session": name, "began": began})
            except (OSError, ValueError, IndexError):
                continue
    except OSError:
        pass
    started.sort(key=lambda s: s["began"], reverse=True)

    ran_out = None
    try:
        with open(os.path.join(data, "ran-out"), encoding="utf-8") as f:
            ran_out = int(f.read().strip())
    except (OSError, ValueError):
        pass

    track = ""
    try:
        with open(os.path.join(data, "current-track"), encoding="utf-8") as f:
            track = f.read().strip()
    except OSError:
        pass

    turns = read_turns(os.path.join(data, "waits.log"), now)
    five = read_window(limits, "five_hour", now)
    if not five or five["used"] < 100:
        ran_out = None
    return {
        # No wall clock and no elapsed counter in here: they would change every
        # second and defeat the "push only when something changed" check. The
        # page ticks its own clock from started_at.
        "five_hour": five,
        "seven_day": read_window(limits, "seven_day", now),
        "spend_limit": read_window(limits, "spend_limit", now),
        "cost": (status.get("cost") or {}).get("total_cost_usd"),
        "ran_out_at": ran_out,
        # a turn is in flight; the newest one is the one you're watching
        "running": bool(active),
        "started_at": started[0]["began"] if started else None,
        "concurrent": len(active),
        "track": track,
        "turns": turns,
    }


# ----------------------------------------------------------------- http

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    data_dir = DEFAULT_DATA
    viewers = 0                      # open /events streams

    def log_message(self, *_):            # the terminal is the user's, not ours
        pass

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/state":
            return self._send(200, json.dumps(read_state(self.data_dir)).encode(),
                              "application/json")
        if path == "/events":
            return self.stream_events()
        return self.serve_file(path)

    def serve_file(self, path):
        name = "scene.html" if path == "/" else path.lstrip("/")
        full = os.path.normpath(os.path.join(VIEWER, name))
        if not full.startswith(os.path.normpath(VIEWER)) or not os.path.isfile(full):
            return self._send(404, b"not found", "text/plain")
        with open(full, "rb") as f:
            body = f.read()
        return self._send(200, body, TYPES.get(os.path.splitext(full)[1], "application/octet-stream"))

    def stream_events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        Handler.viewers += 1
        last, last_beat = None, 0.0
        try:
            while True:
                if STOPPING.is_set():
                    # a deliberate stop: let the viewer close itself at once
                    self.wfile.write(b"event: bye\ndata: {}\n\n")
                    self.wfile.flush()
                    return
                state = read_state(self.data_dir)
                blob = json.dumps(state)
                if blob != last:
                    self.wfile.write(b"data: " + blob.encode() + b"\n\n")
                    self.wfile.flush()
                    last, last_beat = blob, time.time()
                elif time.time() - last_beat > HEARTBEAT_SECONDS:
                    self.wfile.write(b": keep-alive\n\n")   # proxies and sleeping tabs
                    self.wfile.flush()
                    last_beat = time.time()
                STOPPING.wait(POLL_SECONDS)   # wakes immediately on a stop
        except (BrokenPipeError, ConnectionResetError):
            pass                                            # the page went away
        finally:
            Handler.viewers -= 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=int(os.environ.get("WAITING_ROOM_PORT", 8787)))
    ap.add_argument("--data", default=os.environ.get("CLAUDE_PLUGIN_DATA", DEFAULT_DATA))
    ap.add_argument("--open", action="store_true", help="open the viewer in a browser")
    args = ap.parse_args()

    Handler.data_dir = args.data
    socketserver.TCPServer.allow_reuse_address = True
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    except OSError as e:
        sys.exit(f"can't listen on 127.0.0.1:{args.port}: {e}")
    server.daemon_threads = True
    record = write_server_record(args.data, os.path.abspath(__file__))

    def retire():
        remove_server_record(args.data, record)
        os._exit(0)

    url = f"http://127.0.0.1:{args.port}/"
    print(f"waiting-room viewer on {url}  (data: {args.data})")
    if not os.path.isdir(args.data):
        print(f"  note: {args.data} doesn't exist yet — it appears once the plugin runs")
    if args.open:
        threading.Timer(0.3, lambda: subprocess.run(["open", url], check=False)).start()
    # Session end normally stops us. This is the backstop for a session that
    # died without one: no viewer, no working session, half an hour — retire.
    def idle_watch():
        alone_since = time.time()
        while True:
            time.sleep(30)
            busy = (Handler.viewers > 0 or fresh_markers(args.data, "active")
                    or fresh_markers(args.data, "sessions"))
            if busy:
                alone_since = time.time()
            elif time.time() - alone_since > IDLE_EXIT_SECONDS:
                print("idle for 30 minutes with nothing to show — stopping")
                retire()

    threading.Thread(target=idle_watch, daemon=True).start()

    def goodbye(_sig, _frame):
        STOPPING.set()
        threading.Timer(0.4, retire).start()   # let the streams flush

    signal.signal(signal.SIGTERM, goodbye)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        remove_server_record(args.data, record)
        server.server_close()


if __name__ == "__main__":
    main()

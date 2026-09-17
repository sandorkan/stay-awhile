#!/usr/bin/env python3
"""Serve the viewer and stream what the plugin already wrote to disk.

    python3 scripts/viewer-server.py [--port 8787] [--data DIR] [--open]

Routes:
    /            the scene
    /state       one JSON snapshot (handy for curl)
    /events      the same snapshot pushed on change (server-sent events)

Reads, never writes:
    status.json     the status line's payload — the real rate-limit numbers
    ran-out         when the 5-hour window hit 100%, for the moon's rise
    started/<sid>   a turn in flight: "<epoch> <concurrent> <think>"
    active/<sid>    a session working
    current-track   the loop playing right now
    waits.log       one line per finished turn, for the day strip

Pure stdlib, localhost only. Nothing here talks to the network.
"""

import argparse
import json
import os
import socketserver
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
VIEWER = os.path.join(HERE, os.pardir, "viewer")
DEFAULT_DATA = os.path.expanduser("~/.claude/waiting-room")
TAIL_TURNS = 120          # how much of the day the strip shows
POLL_SECONDS = 1.0
HEARTBEAT_SECONDS = 15

TYPES = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
         ".css": "text/css; charset=utf-8", ".png": "image/png", ".json": "application/json"}


# ----------------------------------------------------------------- reading state

def _num(value):
    return value if isinstance(value, (int, float)) else None


def read_window(limits, name):
    w = (limits or {}).get(name) or {}
    used, resets = _num(w.get("used_percentage")), _num(w.get("resets_at"))
    return {"used": used, "resets_at": resets} if used is not None else None


def read_turns(path):
    """The tail of waits.log as [{sec, outcome, switched}], oldest first."""
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 64 * 1024))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return []
    out = []
    for line in lines[-TAIL_TURNS:]:
        c = line.split("\t")
        if len(c) < 4:
            continue
        try:
            sec = float(c[1])
        except ValueError:
            continue
        out.append({"ended": c[0], "sec": sec, "outcome": c[2],
                    "switched": len(c) >= 17 and c[16] == "1",
                    "project": c[18] if len(c) >= 19 else ""})
    return out


def read_state(data):
    now = time.time()
    status = {}
    try:
        with open(os.path.join(data, "status.json"), encoding="utf-8") as f:
            status = json.load(f)
    except (OSError, ValueError):
        pass

    limits = status.get("rate_limits") or {}
    turns, started = [], []
    try:
        for name in os.listdir(os.path.join(data, "started")):
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

    turns = read_turns(os.path.join(data, "waits.log"))
    return {
        # No wall clock and no elapsed counter in here: they would change every
        # second and defeat the "push only when something changed" check. The
        # page ticks its own clock from started_at.
        "five_hour": read_window(limits, "five_hour"),
        "seven_day": read_window(limits, "seven_day"),
        "spend_limit": read_window(limits, "spend_limit"),
        "cost": (status.get("cost") or {}).get("total_cost_usd"),
        "ran_out_at": ran_out,
        # a turn is in flight; the newest one is the one you're watching
        "running": bool(started),
        "started_at": started[0]["began"] if started else None,
        "concurrent": len(started),
        "track": track,
        "turns": turns,
    }


# ----------------------------------------------------------------- http

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    data_dir = DEFAULT_DATA

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
        last, last_beat = None, 0.0
        try:
            while True:
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
                time.sleep(POLL_SECONDS)
        except (BrokenPipeError, ConnectionResetError):
            pass                                            # the page went away


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

    url = f"http://127.0.0.1:{args.port}/"
    print(f"waiting-room viewer on {url}  (data: {args.data})")
    if not os.path.isdir(args.data):
        print(f"  note: {args.data} doesn't exist yet — it appears once the plugin runs")
    if args.open:
        threading.Timer(0.3, lambda: subprocess.run(["open", url], check=False)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()

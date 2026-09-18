"""Shared local lifecycle helpers for the viewer and its setup tool."""
import json
import os
import subprocess
import time

MARKER_TTL = 2 * 60 * 60


def fresh_markers(data, kind, now=None):
    """Ignore abandoned session/turn leases without mutating hook-owned files."""
    now = time.time() if now is None else now
    directory = os.path.join(data, kind)
    try:
        entries = os.scandir(directory)
    except OSError:
        return []
    with entries:
        return [entry.name for entry in entries
                if _fresh(entry, now)]


def _fresh(entry, now):
    try:
        return entry.is_file() and now - entry.stat().st_mtime <= MARKER_TTL
    except OSError:
        return False


def process_identity(pid):
    """Include start time as well as command to reject reused PIDs."""
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1:
        return None
    try:
        if os.name == 'nt':
            # No ps here (MSYS's lacks -o, and hooks may not run under it at
            # all); WMI has the same two facts.
            script = ("$p = Get-CimInstance Win32_Process -Filter 'ProcessId=%d'; "
                      "if ($p) { $p.CreationDate.ToString('o') + ' ' + $p.CommandLine }" % pid)
            value = subprocess.check_output(
                ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script],
                stderr=subprocess.DEVNULL, text=True,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)).strip()
        else:
            value = subprocess.check_output(
                ['ps', '-p', str(pid), '-o', 'lstart=', '-o', 'command='],
                stderr=subprocess.DEVNULL, text=True).strip()
        return value or None
    except (OSError, subprocess.CalledProcessError):
        return None


def same_path(a, b):
    """Windows spells one path several ways (case, slashes); compare loosely there."""
    if os.name == 'nt':
        return a.replace('\\', '/').lower() == b.replace('\\', '/').lower()
    return a == b


def path_in(path, text):
    if os.name == 'nt':
        return path.replace('\\', '/').lower() in text.replace('\\', '/').lower()
    return path in text


def read_server_record(data):
    try:
        with open(os.path.join(data, 'server.pid'), encoding='utf-8') as f:
            value = json.load(f)
        return value if isinstance(value, dict) else None
    except (OSError, ValueError):
        return None


def owns_server(record, script):
    if not record or not record.get('identity'):
        return False
    return (same_path(record.get('script', ''), os.path.realpath(script))
            and path_in(record['script'], record['identity'])
            and process_identity(record.get('pid')) == record['identity'])


def write_server_record(data, script):
    pid = os.getpid()
    record = {'pid': pid, 'script': os.path.realpath(script),
              'identity': process_identity(pid)}
    os.makedirs(data, exist_ok=True)
    path = os.path.join(data, 'server.pid')
    temp = f'{path}.{pid}.tmp'
    with open(temp, 'w', encoding='utf-8') as f:
        json.dump(record, f)
    os.replace(temp, path)
    return record


def remove_server_record(data, record):
    if record and read_server_record(data) == record:
        try:
            os.remove(os.path.join(data, 'server.pid'))
        except OSError:
            pass

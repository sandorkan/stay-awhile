"""Run with: python3 -m unittest discover -s tests -v. Never uses real settings/audio."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import runtime
import setup

spec = importlib.util.spec_from_file_location('viewer_server', ROOT/'scripts/viewer-server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='wr-tests-')
        self.data = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def env(self):
        return {**os.environ, 'CLAUDE_PLUGIN_ROOT': str(ROOT),
                'CLAUDE_PLUGIN_DATA': str(self.data), 'WAITING_ROOM_SIMULATION': '1',
                'CLAUDE_PLUGIN_OPTION_TRACK': 'none', 'CLAUDE_PLUGIN_OPTION_CUES': 'false',
                'CLAUDE_PLUGIN_OPTION_EYE_CUE_EVERY': '0', 'CLAUDE_PLUGIN_OPTION_STATUSLINE_CHAIN': ''}

    def hook(self, script, sid='A', *args):
        return subprocess.run(['/bin/bash', str(ROOT/'scripts'/script), *args],
                              input=json.dumps({'session_id': sid}), text=True,
                              env=self.env(), capture_output=True, check=True)

    def test_session_leases_outlast_turn_and_permission_pause(self):
        self.hook('session.sh')
        self.hook('start.sh')
        self.assertTrue(server.read_state(str(self.data))['running'])
        self.hook('stop.sh', 'A', 'needs-you')
        self.assertTrue((self.data/'started/A').exists())
        self.assertFalse(server.read_state(str(self.data))['running'])
        self.hook('start.sh', 'A', 'resume')
        self.assertTrue(server.read_state(str(self.data))['running'])
        self.hook('stop.sh', 'A', 'done')
        self.assertEqual(runtime.fresh_markers(str(self.data), 'sessions'), ['A'])
        self.assertFalse(server.read_state(str(self.data))['running'])

    def test_stale_markers_do_not_keep_server_busy(self):
        for kind in ('sessions', 'active', 'started'):
            (self.data/kind).mkdir()
            p = self.data/kind/'abandoned'
            p.write_text('1 0 0')
            os.utime(p, (1, 1))
            self.assertEqual(runtime.fresh_markers(str(self.data), kind), [])
        self.assertFalse(server.read_state(str(self.data))['running'])

    def test_stop_preserves_idle_sessions(self):
        self.hook('session.sh', 'B')
        with patch.object(setup, 'DATA', str(self.data)), patch.object(setup, 'DEFAULT_HOME', str(self.data)), patch.object(setup.os, 'kill') as kill:
            self.assertEqual(setup.cmd_stop(argparse.Namespace(if_idle=True)), 0)
            kill.assert_not_called()

    def test_stop_rejects_reused_and_legacy_pids(self):
        for record in (12345, {'pid': 12345, 'script': str(ROOT/'scripts/viewer-server.py'), 'identity': 'old'}):
            (self.data/'server.pid').write_text(json.dumps(record))
            with patch.object(setup, 'DATA', str(self.data)), patch.object(setup, 'DEFAULT_HOME', str(self.data)), patch.object(setup, 'server_running', return_value=False), patch.object(runtime, 'process_identity', return_value='new'), patch.object(setup.os, 'kill') as kill:
                setup.cmd_stop(argparse.Namespace(if_idle=False))
                kill.assert_not_called()

    def test_server_record_cleanup_and_identity(self):
        script = str(ROOT/'scripts/viewer-server.py')
        with patch.object(runtime, 'process_identity', return_value='started '+script):
            record = runtime.write_server_record(str(self.data), script)
            self.assertTrue(runtime.owns_server(record, script))
            runtime.remove_server_record(str(self.data), {**record, 'pid': 2})
            self.assertIsNotNone(runtime.read_server_record(str(self.data)))
            runtime.remove_server_record(str(self.data), record)
            self.assertIsNone(runtime.read_server_record(str(self.data)))

    def test_chain_quotes_shell_text_and_spaced_path(self):
        stub = self.data/'capture command.sh'
        stub.write_text('#!/bin/sh\nprintf "%s" "$CLAUDE_PLUGIN_OPTION_STATUSLINE_CHAIN"\n')
        stub.chmod(0o755)
        existing = "printf '%s' '$(printf EARLY)' `printf LATER` $VALUE\n"
        with patch.object(setup, 'STATUSLINE', str(stub)):
            _, entry, _ = setup.statusline_plan({'statusLine': {'command': existing}})
        received = subprocess.check_output(['/bin/sh', '-c', entry['command']], text=True)
        self.assertEqual(received, existing)

    def test_today_completed_turns_only(self):
        now = datetime.now().astimezone()
        log = self.data/'waits.log'
        log.write_text('\n'.join(f'{date.isoformat()}\t10\t{outcome}\tA' for date, outcome in [
            (now-timedelta(days=1), 'done'), (now, 'needs-you'), (now, 'done'), (now, 'failed')]))
        turns = server.read_turns(log)
        self.assertEqual([t['outcome'] for t in turns], ['done', 'failed'])

    def test_expired_cache_and_ran_out_are_ignored(self):
        (self.data/'status.json').write_text('{}')
        (self.data/'limits.json').write_text(json.dumps({'rate_limits': {'five_hour': {'used_percentage': 100, 'resets_at': 1}}}))
        (self.data/'ran-out').write_text('1')
        state = server.read_state(str(self.data))
        self.assertIsNone(state['five_hour'])
        self.assertIsNone(state['ran_out_at'])

    def test_status_cache_survives_empty_payload_and_requires_100(self):
        env = self.env()
        statusline = ['/bin/bash', str(ROOT/'scripts/statusline.sh')]
        payload = {'rate_limits': {'five_hour': {'used_percentage': 99, 'resets_at': int(time.time())+1000}}}
        subprocess.run(statusline, input=json.dumps(payload), text=True, env=env, capture_output=True, check=True)
        self.assertFalse((self.data/'ran-out').exists())
        subprocess.run(statusline, input='{"rate_limits":null}', text=True, env=env, capture_output=True, check=True)
        self.assertEqual(json.loads((self.data/'limits.json').read_text()), payload)
        self.assertEqual(server.read_state(str(self.data))['five_hour']['used'], 99)

    def test_partial_updates_preserve_each_window_until_reset(self):
        reset = int(time.time()) + 1000
        five = {'used_percentage': 1, 'resets_at': reset}
        week = {'used_percentage': 36, 'resets_at': reset + 10000}
        snapshots = [
            {'five_hour': five, 'seven_day': week},
            {'seven_day': week},
            {'five_hour': None, 'seven_day': week},
            {'five_hour': five},
            {},
        ]
        for limits in snapshots:
            subprocess.run(['/bin/bash', str(ROOT/'scripts/statusline.sh')],
                           input=json.dumps({'rate_limits': limits}), text=True,
                           env=self.env(), capture_output=True, check=True)
            state = server.read_state(str(self.data))
            self.assertEqual(state['five_hour'], {'used': 1, 'resets_at': reset})
            self.assertEqual(state['seven_day']['used'], 36)
        with patch.object(server.time, 'time', return_value=reset + 1):
            state = server.read_state(str(self.data))
            self.assertIsNone(state['five_hour'])
            self.assertEqual(state['seven_day']['used'], 36)

    def test_old_fade_watchdog_preserves_new_loop(self):
        # No real player is launched. The expired PID cannot exist on our
        # supported platforms; the actual watchdog still runs its ownership check.
        script = '''source "$CLAUDE_PLUGIN_ROOT/scripts/lib.sh"
PLAYER=afplay
loop_alive() { return 0; }
echo 99999999 > "$LOOP_PID"
stop_loop
echo 2222 > "$LOOP_PID"
touch "$STOP_FILE.2222"
wait
[ "$(cat "$LOOP_PID")" = 2222 ] && [ -f "$STOP_FILE.2222" ] && [ ! -f "$STOP_FILE.99999999" ]
'''
        subprocess.run(['/bin/bash', '-c', script], env=self.env(), capture_output=True, check=True)

    def test_simulation_never_uses_inherited_data(self):
        (self.data/'sentinel').write_text('real session')
        result = subprocess.run(['/bin/bash', str(ROOT/'scripts/simulate.sh'), 'silent', '0'],
                                env=self.env(), text=True, capture_output=True, check=True)
        self.assertEqual(list(self.data.iterdir()), [self.data/'sentinel'])
        self.assertIn('silent', result.stdout)

    def test_simulation_does_not_publish_pointer(self):
        # Intercept filesystem commands at the shell boundary: a simulation
        # should only create its private state directories, never write HOME.
        script = '''mkdir() { printf 'mkdir %s\\n' "$*"; }
cat() { return 1; }
printf() { builtin printf "$@"; }
source "$CLAUDE_PLUGIN_ROOT/scripts/lib.sh"
'''
        result = subprocess.run(['/bin/bash', '-c', script], env=self.env(), text=True, capture_output=True, check=True)
        self.assertNotIn('.claude/waiting-room', result.stdout)


if __name__ == '__main__':
    unittest.main()

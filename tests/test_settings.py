"""Settings writes and request boundaries, isolated from real Claude settings."""
import io
import os
import subprocess
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import tempfile
import unittest
from test_runtime import ROOT, setup, server


class SettingsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="wr-settings-")
        self.addCleanup(temporary.cleanup)
        self.data = Path(temporary.name)
        self.settings = self.data / 'settings.json'
        self.patch = patch.object(setup, 'SETTINGS', str(self.settings))
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def seed(self):
        data = {'permissions': {'allow': ['Read']}, 'enabledPlugins': {'waiting-room@local': True},
                'pluginConfigs': {'waiting-room@local': {'options': {'volume': .2, 'track': 'none'}}}}
        self.settings.write_text(json.dumps(data))
        return data

    def test_save_preserves_other_settings_and_backup(self):
        old = self.seed()
        setup.save_music('ambient/dusk', 'none')
        saved = json.loads(self.settings.read_text())
        self.assertEqual(saved['permissions'], old['permissions'])
        self.assertEqual(saved['pluginConfigs']['waiting-room@local']['options'], {'volume': .2, 'track': 'ambient/dusk'})
        self.assertEqual(json.loads(next(self.data.glob('settings.json.bak-*')).read_text()), old)
        self.assertEqual(setup.music_settings()['track'], 'ambient/dusk')

    def test_stale_selection_and_invalid_track_do_not_write(self):
        self.seed()
        original = self.settings.read_bytes()
        for track, expected in [('ambient/dusk', 'heartbeat'), ('../../bad', 'none'), ([], 'none')]:
            with self.assertRaises(ValueError):
                setup.save_music(track, expected)
        self.assertEqual(self.settings.read_bytes(), original)

    def test_missing_and_malformed_settings(self):
        setup.save_music('shuffle-ambient', setup.DEFAULT_TRACK)
        self.assertEqual(setup.music_settings()['track'], 'shuffle-ambient')
        self.settings.write_text('{bad')
        with self.assertRaises(ValueError):
            setup.save_music('none')
        self.assertEqual(self.settings.read_text(), '{bad')

    def test_symlink_and_failed_replace_preserve_settings(self):
        self.seed()
        real = self.data / 'real.json'
        self.settings.rename(real)
        self.settings.symlink_to(real)
        setup.save_music('ambient/dusk', 'none')
        self.assertTrue(self.settings.is_symlink())
        self.assertEqual(json.loads(real.read_text())['pluginConfigs']['waiting-room@local']['options']['track'], 'ambient/dusk')
        original = real.read_bytes()
        with patch.object(setup.os, 'replace', side_effect=OSError('read only')):
            with self.assertRaises(OSError):
                setup.save_music('none', 'ambient/dusk')
        self.assertEqual(real.read_bytes(), original)
        self.assertFalse(list(self.data.glob('.waiting-room-*')))

    def test_hook_picks_up_saved_changes_without_session_restart(self):
        home = self.data / 'home'
        config = home / '.claude/settings.json'
        config.parent.mkdir(parents=True)
        runtime_data = self.data / 'runtime'
        played = self.data / 'played'
        env = {**os.environ, 'HOME': str(home), 'CLAUDE_PLUGIN_ROOT': str(ROOT),
               'CLAUDE_PLUGIN_DATA': str(runtime_data), 'WAITING_ROOM_SIMULATION': '0',
               'CLAUDE_PLUGIN_OPTION_TRACK': 'heartbeat',
               'CLAUDE_PLUGIN_OPTION_CUES': 'false', 'CLAUDE_PLUGIN_OPTION_EYE_CUE_EVERY': '0',
               'TEST_PLAYED': str(played)}
        # Execute the real hook and settings reader, replacing only audio launch.
        shell = '''source() {
  builtin source "$@"
  start_loop() { printf '%s\\n' "$1" >> "$TEST_PLAYED"; }
}
source "$CLAUDE_PLUGIN_ROOT/scripts/start.sh" "$@"
'''
        def turn(resume=False):
            subprocess.run(['/bin/bash', '-c', shell, 'test'] + (['resume'] if resume else []),
                           input='{"session_id":"same-session"}', text=True, env=env,
                           capture_output=True, check=True)
        with patch.object(setup, 'SETTINGS', str(config)):
            setup.save_music('ambient/dusk')
            turn()
            setup.save_music('ambient/lantern')
            turn(resume=True)  # still the old song for this turn
            turn()  # same process environment, same session, fresh preference
            setup.save_music('none')
            turn()  # no audio launch
            self.assertEqual(played.read_text().splitlines(), ['ambient/dusk', 'ambient/dusk', 'ambient/lantern'])
            self.assertEqual((runtime_data/'turn-track/same-session').read_text().strip(), 'none')
            config.write_text('{broken')
            turn()  # malformed settings fall back to the original env option
            self.assertEqual(played.read_text().splitlines()[-1], 'heartbeat')
            config.write_text('{}')
            setup.save_music('ambient/dusk')
            env['WAITING_ROOM_SIMULATION'] = '1'
            turn()  # auditions continue to honor their explicit environment
            self.assertEqual(played.read_text().splitlines()[-1], 'heartbeat')

    def request(self, payload=None, headers=None, method='POST'):
        handler = server.Handler.__new__(server.Handler)
        body = json.dumps(payload).encode()
        handler.server = SimpleNamespace(server_port=8787)
        handler.path = '/settings'
        handler.headers = {'Host': '127.0.0.1:8787', 'Origin': 'http://127.0.0.1:8787',
                           'X-Waiting-Room': '1', 'Content-Type': 'application/json',
                           'Content-Length': str(len(body)), **(headers or {})}
        handler.rfile = io.BytesIO(body)
        result = []
        handler._send = lambda code, body, kind: result.append((code, json.loads(body)))
        getattr(handler, 'do_' + method)()
        return result[0]

    def test_endpoint_saves_reads_and_never_starts_audio(self):
        self.seed()
        with patch.object(setup.subprocess, 'run', side_effect=AssertionError('No audio')):
            code, result = self.request({'track': 'ambient/dusk', 'expected': 'none'})
        self.assertEqual(code, 200)
        self.assertEqual(result['track'], 'ambient/dusk')
        code, result = self.request(method='GET')
        self.assertEqual(code, 200)
        self.assertEqual(result['track'], 'ambient/dusk')
        self.assertIn('ambient/dusk', result['groups']['ambient'])

    def test_endpoint_rejects_foreign_origins_hosts_and_bad_payloads(self):
        self.seed()
        payload = {'track': 'ambient/dusk', 'expected': 'none'}
        for headers in [{'Origin': 'https://example.com'}, {'Host': 'example.com:8787'},
                        {'X-Waiting-Room': ''}, {'Sec-Fetch-Site': 'cross-site'}]:
            self.assertEqual(self.request(payload, headers)[0], 403)
        for invalid in [{'track': 'none'}, [], {'track': 'none', 'expected': None}]:
            self.assertEqual(self.request(invalid)[0], 400)
        self.assertEqual(self.request(payload, {'Content-Length': '99999'})[0], 400)
        self.assertEqual(setup.music_settings()['track'], 'none')

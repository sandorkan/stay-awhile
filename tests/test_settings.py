"""Settings writes and request boundaries, isolated from real Claude settings."""
import io
import argparse
import contextlib
import os
import subprocess
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import tempfile
import unittest
from test_runtime import ROOT, BASH, setup, server


class SettingsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="sa-settings-")
        self.addCleanup(temporary.cleanup)
        self.data = Path(temporary.name)
        self.settings = self.data / 'settings.json'
        self.patch = patch.object(setup, 'SETTINGS', str(self.settings))
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def seed(self):
        data = {'permissions': {'allow': ['Read']}, 'enabledPlugins': {'stay-awhile@local': True},
                'pluginConfigs': {'stay-awhile@local': {'options': {'volume': .2, 'track': 'none'}}}}
        self.settings.write_text(json.dumps(data))
        return data

    def test_save_preserves_other_settings_and_backup(self):
        old = self.seed()
        setup.save_music('ambient/dusk', 'none')
        saved = json.loads(self.settings.read_text())
        self.assertEqual(saved['permissions'], old['permissions'])
        self.assertEqual(saved['pluginConfigs']['stay-awhile@local']['options'], {'volume': .2, 'track': 'ambient/dusk'})
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
        try:
            self.settings.symlink_to(real)
        except OSError as e:  # Windows needs a privilege for symlinks
            self.skipTest(f"cannot create symlinks here: {e}")
        setup.save_music('ambient/dusk', 'none')
        self.assertTrue(self.settings.is_symlink())
        self.assertEqual(json.loads(real.read_text())['pluginConfigs']['stay-awhile@local']['options']['track'], 'ambient/dusk')
        original = real.read_bytes()
        with patch.object(setup.os, 'replace', side_effect=OSError('read only')):
            with self.assertRaises(OSError):
                setup.save_music('none', 'ambient/dusk')
        self.assertEqual(real.read_bytes(), original)
        self.assertFalse(list(self.data.glob('.stay-awhile-*')))

    def test_hook_picks_up_saved_changes_without_session_restart(self):
        home = self.data / 'home'
        config = home / '.claude/settings.json'
        config.parent.mkdir(parents=True)
        runtime_data = self.data / 'runtime'
        played = self.data / 'played'
        env = {**os.environ, 'HOME': str(home), 'USERPROFILE': str(home), 'CLAUDE_PLUGIN_ROOT': str(ROOT),
               'CLAUDE_PLUGIN_DATA': str(runtime_data), 'STAY_AWHILE_SIMULATION': '0',
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
            subprocess.run([*BASH, '-c', shell, 'test'] + (['resume'] if resume else []),
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
            env['STAY_AWHILE_SIMULATION'] = '1'
            turn()  # auditions continue to honor their explicit environment
            self.assertEqual(played.read_text().splitlines()[-1], 'heartbeat')

    def test_rename_migration_preserves_existing_options(self):
        original = {'enabledPlugins': {'stay-awhile@stay-awhile-marketplace': True},
                    'pluginConfigs': {'waiting-room@old': {'options': {'track': 'ambient/dusk', 'volume': .3}},
                                      'stay-awhile@stay-awhile-marketplace': {'options': {'volume': .7}}}}
        updated, changed = setup.migrated_options(original)
        self.assertTrue(changed)
        self.assertEqual(updated['pluginConfigs']['stay-awhile@stay-awhile-marketplace']['options'],
                         {'track': 'ambient/dusk', 'volume': .7})
        self.assertEqual(updated['pluginConfigs']['waiting-room@old'], original['pluginConfigs']['waiting-room@old'])
        self.assertEqual(setup.current_track(original), 'ambient/dusk')
        self.assertFalse(setup.migrated_options(updated)[1])
        self.assertNotIn('track', original['pluginConfigs']['stay-awhile@stay-awhile-marketplace']['options'])

    def test_init_migrates_even_when_statusline_is_current(self):
        original = {'statusLine': {'type': 'command', 'command': setup.STATUSLINE},
                    'pluginConfigs': {'waiting-room@inline': {'options': {'volume': .3}}}}
        self.settings.write_text(json.dumps(original))
        with contextlib.redirect_stdout(io.StringIO()):
            setup.cmd_install(argparse.Namespace(apply=False))
            self.assertEqual(json.loads(self.settings.read_text()), original)
            setup.cmd_install(argparse.Namespace(apply=True))
        self.assertEqual(json.loads(self.settings.read_text())['pluginConfigs']['stay-awhile@inline']['options']['volume'], .3)

    def test_old_statusline_replacement_keeps_chain(self):
        command = 'CLAUDE_PLUGIN_OPTION_STATUSLINE_CHAIN="echo hello" "/old/waiting-room/scripts/statusline.sh"'
        action, entry, _ = setup.statusline_plan({'statusLine': {'command': command}})
        self.assertEqual(action, 'replace')
        self.assertIn('CLAUDE_PLUGIN_OPTION_STATUSLINE_CHAIN="echo hello"', entry['command'])
        self.assertIn(setup.shell_path(setup.STATUSLINE), entry['command'])
        self.assertNotIn('/old/waiting-room/', entry['command'])

    def test_renamed_hooks_and_setup_reuse_history_directory(self):
        home = self.data / 'home'
        old = home / '.claude/waiting-room'
        old.mkdir(parents=True)
        (old/'data-dir').write_text(str(old))
        (old/'waits.log').write_text('history')
        env = {**os.environ, 'HOME': str(home), 'USERPROFILE': str(home), 'CLAUDE_PLUGIN_ROOT': str(ROOT),
               'CLAUDE_PLUGIN_DATA': str(home/'.claude/plugins/data/stay-awhile-inline'),
               'STAY_AWHILE_SIMULATION': '0'}
        result = subprocess.run([*BASH, '-c', 'source "$CLAUDE_PLUGIN_ROOT/scripts/lib.sh"; printf "%s" "$DATA"'],
                                env=env, capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, str(old))
        with patch.dict(os.environ, env), patch.object(setup, 'DEFAULT_HOME', str(old)):
            self.assertEqual(setup.resolve_data(), str(old))
        self.assertEqual((old/'waits.log').read_text(), 'history')

    def request(self, payload=None, headers=None, method='POST'):
        handler = server.Handler.__new__(server.Handler)
        body = json.dumps(payload).encode()
        handler.server = SimpleNamespace(server_port=8787)
        handler.path = '/settings'
        handler.headers = {'Host': '127.0.0.1:8787', 'Origin': 'http://127.0.0.1:8787',
                           'X-Stay-Awhile': '1', 'Content-Type': 'application/json',
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
                        {'X-Stay-Awhile': ''}, {'Sec-Fetch-Site': 'cross-site'}]:
            self.assertEqual(self.request(payload, headers)[0], 403)
        for invalid in [{'track': 'none'}, [], {'track': 'none', 'expected': None}]:
            self.assertEqual(self.request(invalid)[0], 400)
        self.assertEqual(self.request(payload, {'Content-Length': '99999'})[0], 400)
        self.assertEqual(setup.music_settings()['track'], 'none')

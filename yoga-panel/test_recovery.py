import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

path=Path(__file__).resolve().parent.parent/'bin/yoga-recovery'
loader=importlib.machinery.SourceFileLoader('yoga_recovery',str(path))
spec=importlib.util.spec_from_loader(loader.name,loader)
recovery=importlib.util.module_from_spec(spec);loader.exec_module(recovery)

class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        home=Path(self.temp.name)
        self.addCleanup(patch.stopall)
        patch.object(recovery,'HOME',home).start()
        patch.object(recovery,'BACKUPS',home/'.local/state/yoga-book/backups').start()
        self.commands=[]
        def run(args,**kwargs):
            self.commands.append(args)
            stdout='yoga-panel.service enabled enabled\n' if 'list-unit-files' in args else ''
            return SimpleNamespace(returncode=0,stdout=stdout,stderr='')
        patch.object(recovery.subprocess,'run',side_effect=run).start()
        self.config=home/'.config/yoga-panel/settings.json'
        self.config.parent.mkdir(parents=True)
        self.config.write_text('{"scrollSpeed":0.09}')
        build=home/'.local/share/yoga-panel/build';build.mkdir(parents=True)
        (build/'yoga-keyboard').write_text('old binary')
        (home/'.local/share/yoga-panel/backend.py').write_text('# source')
        unrelated=home/'.config/unrelated';unrelated.mkdir();(unrelated/'secret').write_text('not part of backup')
    def test_snapshot_allowlist_and_hashes(self):
        target=recovery.snapshot();manifest=recovery.validate(target)
        self.assertIn('.config/yoga-panel/settings.json',manifest)
        self.assertIn('.local/share/yoga-panel/backend.py',manifest)
        self.assertFalse(any('/build/' in p or 'unrelated' in p for p in manifest))
        self.assertEqual(target.stat().st_mode & 0o777,0o700)
        (target/'home/.config/yoga-panel/settings.json').write_text('damaged')
        with self.assertRaisesRegex(ValueError,'checksum'):recovery.validate(target)
    def test_restore_preserves_current_state_and_rebuilds(self):
        target=recovery.snapshot();self.config.write_text('new setting')
        recovery.restore(target)
        self.assertEqual(self.config.read_text(),'{"scrollSpeed":0.09}')
        snapshots=sorted(recovery.BACKUPS.iterdir());self.assertEqual(len(snapshots),2)
        before=snapshots[-1]
        self.assertEqual((before/'home/.config/yoga-panel/settings.json').read_text(),'new setting')
        self.assertTrue((before/'native-build/yoga-keyboard').exists())
        self.assertFalse((recovery.HOME/'.local/share/yoga-panel/build').exists())
        self.assertIn(['systemctl','--user','restart','yoga-panel.service'],self.commands)
    def test_snapshot_carries_desktop_widgets(self):
        widgets=recovery.HOME/'.config/quickshell/yoga-widgets';widgets.mkdir(parents=True)
        (widgets/'shell.qml').write_text('// widgets');(widgets/'material.js').write_text('// material')
        manifest=recovery.validate(recovery.snapshot())
        self.assertIn('.config/quickshell/yoga-widgets/shell.qml',manifest)
        self.assertIn('.config/quickshell/yoga-widgets/material.js',manifest)
    def widgets(self,enabled=True,active=True,level='1',blur=True):
        bin_dir=recovery.HOME/'.local/bin';bin_dir.mkdir(parents=True,exist_ok=True)
        for name in ('yoga-wallpaper-luma','yoga-ai-limits'):
            helper=bin_dir/name;helper.write_text('#!/bin/sh');helper.chmod(0o755)
        layers={'eDP-1':{'levels':{'0':[{'namespace':'omarchy-background'}],level:[{'namespace':'yoga-widgets'}]}}}
        def run(args,**kwargs):
            code=0;out=''
            if args[-2:]==['is-enabled','yoga-widgets.service']:code=0 if enabled else 1
            elif args[-2:]==['is-active','yoga-widgets.service']:code=0 if active else 3
            elif args[:2]==['hyprctl','layers']:out=json.dumps(layers)
            elif args[:2]==['hyprctl','getoption']:out=json.dumps({'option':'decoration:blur:enabled','bool':blur})
            return SimpleNamespace(returncode=code,stdout=out,stderr='')
        with patch.object(recovery.subprocess,'run',side_effect=run):return recovery.widget_failures()
    def test_widget_check(self):
        self.assertEqual(self.widgets(),[])
        # Switched off with `yoga-widgets off`: a choice, not a fault.
        self.assertEqual(self.widgets(enabled=False,active=False,level='0',blur=False),[])
        self.assertTrue(any('not running' in f for f in self.widgets(active=False)))
        # Background level: the wallpaper, created after them on boot, covers them.
        self.assertTrue(any('under the wallpaper' in f for f in self.widgets(level='0')))
        self.assertTrue(any('blur is off' in f for f in self.widgets(blur=False)))
    def test_traversal_rejected_before_mutation(self):
        target=recovery.snapshot()
        (target/'manifest.json').write_text(json.dumps({'../outside':'x'}))
        with self.assertRaisesRegex(ValueError,'Invalid snapshot path'):recovery.restore(target)
        self.assertFalse(any('stop' in c for c in self.commands))
if __name__=='__main__':unittest.main()

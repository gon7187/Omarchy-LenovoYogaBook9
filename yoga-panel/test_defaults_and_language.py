import json
from pathlib import Path
import re
import unittest
from unittest.mock import patch
import backend

class DefaultsAndLanguage(unittest.TestCase):
    def test_defaults_match_qml(self):
        base=Path(__file__).parent
        defaults=json.loads((base/'defaults.json').read_text())
        self.assertEqual(backend.valid_settings({}),defaults)
        qml=(base/'shell.qml').read_text()
        for name,value in defaults.items():
            raw=re.search(r'property (?:real|bool|string) '+name+r': ([^\n]+)',qml)[1]
            self.assertEqual(json.loads(raw),value,name)
        reset=(base/'PanelSettings.qml').read_text()
        for name in ['pointerSpeed','pointerAccel','scrollSpeed','inertiaStrength','inertiaDuration']:
            self.assertEqual(float(re.search(r'settings\.'+name+r'=([.\d]+)',reset)[1]),defaults[name])
    def test_saved_preferences_are_preserved(self):
        custom=dict(backend.DEFAULTS,pointerSpeed=1.3,scrollSpeed=.04,predictionEnabled=True)
        self.assertEqual(backend.valid_settings(custom),custom)
    def test_auxiliary_layout_does_not_override_active_keyboard(self):
        devices={'keyboards':[{'name':'video-bus','main':False,'active_keymap':'English (US)'},
                              {'name':'fcitx5','main':True,'active_keymap':'Russian'}]}
        with patch('backend.subprocess.check_output',return_value=json.dumps(devices)):
            self.assertEqual(backend.active_language(),'ru')
        devices['keyboards'][1]['active_keymap']='English (US)'
        with patch('backend.subprocess.check_output',return_value=json.dumps(devices)):
            self.assertEqual(backend.active_language(),'en')
    def test_virtual_keyboards_do_not_decide_language(self):
        devices={'keyboards':[{'name':'video-bus','main':False,'active_keymap':'Russian'},
                              {'name':'at-translated-set-2-keyboard','main':False,'active_keymap':'Russian'},
                              {'name':'ingenic-gadget-serial-and-keyboard-keyboard','main':False,'active_keymap':'English (US)'},
                              {'name':'hl-virtual-keyboard-fcitx5','main':True,'active_keymap':'English (US)'}]}
        with patch('backend.subprocess.check_output',return_value=json.dumps(devices)):
            self.assertEqual(backend.active_language(),'ru')
        devices['keyboards'][2]['main']=True
        with patch('backend.subprocess.check_output',return_value=json.dumps(devices)):
            self.assertEqual(backend.active_language(),'en')
    def test_haptic_device_is_matched_by_descriptor(self):
        import tempfile
        with tempfile.TemporaryDirectory() as root:
            for name,hid,descriptor in [('hidraw1',backend.HAPTIC_ID,b'\x05\x0d\x09\x04'),('hidraw3','HID_ID=0003:00001234:00006161',backend.HAPTIC_DESCRIPTOR),('hidraw7',backend.HAPTIC_ID,backend.HAPTIC_DESCRIPTOR+b'\xa1\x02')]:
                device=Path(root)/name/'device'; device.mkdir(parents=True)
                (device/'uevent').write_text(hid+'\n'); (device/'report_descriptor').write_bytes(descriptor)
            self.assertEqual(backend.haptic_device(Path(root)),'/dev/hidraw7')
            (Path(root)/'hidraw7/device/report_descriptor').write_bytes(b'\x05\x0d\x09\x04')
            with self.assertRaises(FileNotFoundError): backend.haptic_device(Path(root))
    def test_missing_active_keyboard_does_not_guess_english(self):
        with patch('backend.subprocess.check_output',return_value='{"keyboards":[]}'):
            self.assertIsNone(backend.active_language())

if __name__=='__main__': unittest.main()

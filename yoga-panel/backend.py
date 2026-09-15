#!/usr/bin/env python3
"""Private stdin transport. No listener socket, root access, or input logging."""
import json
from pathlib import Path
import subprocess
import sys
import threading
import os
import math

SETTINGS_PATH = Path.home()/'.config/yoga-panel/settings.json'
DEFAULTS = {'pointerSpeed':2.4, 'pointerAccel':0.6, 'scrollSpeed':0.18}
LIMITS = {'pointerSpeed':(0.5,5.0), 'pointerAccel':(0.0,2.0), 'scrollSpeed':(0.03,1.0)}

def valid_settings(data):
    result = {}
    for key, default in DEFAULTS.items():
        value = float(data.get(key, default))
        if not math.isfinite(value):
            raise ValueError('Nonfinite setting')
        low, high = LIMITS[key]
        result[key] = max(low,min(high,value))
    return result

def load_settings():
    try:
        return valid_settings(json.loads(SETTINGS_PATH.read_text()))
    except (OSError, ValueError, TypeError, AttributeError):
        return DEFAULTS.copy()

def save_settings(data):
    settings = valid_settings(data)
    SETTINGS_PATH.parent.mkdir(parents=True,exist_ok=True)
    temporary = SETTINGS_PATH.with_suffix('.tmp')
    temporary.write_text(json.dumps(settings)+'\n')
    os.replace(temporary,SETTINGS_PATH)

KEYS = {'Escape', 'Tab', 'BackSpace', 'Return', 'Left', 'Right', 'Up', 'Down', 'Delete', 'Home', 'End'}

def workspace_command(direction):
    # Same workspace selectors as Omarchy's Super+Tab / Super+Shift+Tab.
    selectors = {'next':'e+1', 'previous':'e-1'}
    if direction not in selectors:
        raise ValueError('Invalid workspace direction')
    return ['hyprctl','dispatch','hl.dsp.focus({ workspace = "'+selectors[direction]+'" })']

def keyboard_args(event):
    args = ['wtype']
    for mod in event.get('mods', []):
        if mod not in ('ctrl', 'alt', 'logo', 'shift'):
            raise ValueError('Invalid modifier')
        args += ['-M', mod]
    if event['type'] == 'key':
        if event.get('key') not in KEYS:
            raise ValueError('Invalid named key')
        args += ['-k', event['key']]
    else:
        text = event.get('text', '')
        if not isinstance(text, str) or len(text) != 1 or not text.isprintable():
            raise ValueError('Expected one printable character')
        args += ['--', text]
    return args

def main():
    pointer = subprocess.Popen([str(Path(__file__).parent/'build/yoga-pointer')], stdin=subprocess.PIPE, text=True)
    keyboard = subprocess.Popen([str(Path(__file__).parent/'build/yoga-keyboard')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    def keyboard_status():
        for status in keyboard.stdout:
            print(status.strip(), flush=True)
    threading.Thread(target=keyboard_status, daemon=True).start()
    print('ready', flush=True)
    print(json.dumps({'settings':load_settings()}), flush=True)
    try:
        for line in sys.stdin:
            try:
                e = json.loads(line)
                kind = e.get('type')
                if kind == 'settings':
                    save_settings(e['values'])
                elif kind == 'workspace':
                    result = subprocess.run(workspace_command(e['direction']),capture_output=True,text=True,timeout=3,check=True)
                    if result.stdout.strip() != 'ok':
                        raise ValueError('Workspace dispatch failed')
                elif kind in ('key', 'text'):
                    keyboard_args(e)  # Validate before serializing into private transport.
                    mod = sum({'ctrl':1,'alt':2,'logo':4,'shift':8}[m] for m in set(e.get('mods', [])))
                    command = f"k {e['key']} {mod}" if kind == 'key' else f"t {ord(e['text'])} {mod}"
                    keyboard.stdin.write(command+'\n'); keyboard.stdin.flush()
                elif kind in ('move', 'scroll'):
                    x, y = float(e['x']), float(e['y'])
                    pointer.stdin.write(f"{'m' if kind == 'move' else 's'} {x} {y}\n")
                    pointer.stdin.flush()
                elif kind == 'button':
                    if e['button'] not in (272, 273) or e['state'] not in (0, 1):
                        raise ValueError('Invalid button')
                    pointer.stdin.write(f"b {e['button']} {e['state']}\n"); pointer.stdin.flush()
                elif kind == 'release':
                    pointer.stdin.write('r\n'); pointer.stdin.flush()
            except (ValueError, KeyError, TypeError, subprocess.SubprocessError, OSError):
                print('input-error', flush=True)
    finally:
        try:
            keyboard.stdin.close()
            keyboard.wait(timeout=2)
        except (OSError, subprocess.TimeoutExpired):
            keyboard.terminate()
        try:
            pointer.stdin.close()
            pointer.wait(timeout=2)
        except (OSError, subprocess.TimeoutExpired):
            pointer.terminate()

if __name__ == '__main__':
    main()

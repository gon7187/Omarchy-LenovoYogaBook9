#!/usr/bin/env python3
"""Private stdin transport. No listener socket, root access, or input logging."""
import json
from pathlib import Path
import subprocess
import sys
import threading
import os
import math
import socket
import time
import signal
from prediction import Predictor
from autocorrect import Autocorrect
from voice import Voice

OUTPUT_LOCK = threading.Lock()
def emit(value):
    with OUTPUT_LOCK:
        print(json.dumps(value) if isinstance(value,dict) else value,flush=True)

def layout_monitor():
    """Observe layout/focus notifications only; never forward window titles."""
    path=Path(os.environ.get('XDG_RUNTIME_DIR',f'/run/user/{os.getuid()}'))/'hypr'/os.environ.get('HYPRLAND_INSTANCE_SIGNATURE','')/'.socket2.sock'
    while True:
        try:
            with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as stream:
                stream.connect(str(path))
                last_focus=None
                try:
                    devices=json.loads(subprocess.check_output(['hyprctl','devices','-j'],text=True,timeout=2))['keyboards']
                    keyboard=next((k for k in devices if k.get('main')),None)
                    if keyboard:
                        layout=keyboard.get('active_keymap','')
                        if 'Russian' in layout: emit({'language':'ru'})
                        elif 'English' in layout: emit({'language':'en'})
                except (OSError,ValueError,KeyError,subprocess.SubprocessError):
                    pass
                with stream.makefile() as events:
                    for event in events:
                        if event.startswith('activewindowv2>>'):
                            focus=event.strip().partition('>>')[2]
                            if focus != last_focus:
                                emit({'focusChanged':True})
                                last_focus=focus
                        elif event.startswith('activelayout>>'):
                            device,_,layout=event.strip().partition('>>')[2].partition(',')
                            if 'yoga-keyboard' in device: continue
                            if 'Russian' in layout: emit({'language':'ru'})
                            elif 'English' in layout: emit({'language':'en'})
        except OSError:
            time.sleep(2)

SETTINGS_PATH = Path.home()/'.config/yoga-panel/settings.json'
DEFAULTS = {'pointerSpeed':2.4, 'pointerAccel':0.6, 'scrollSpeed':0.18, 'predictionEnabled':True, 'autocorrectEnabled':True, 'inertiaEnabled':True}
LIMITS = {'pointerSpeed':(0.5,5.0), 'pointerAccel':(0.0,2.0), 'scrollSpeed':(0.03,1.0)}

def valid_settings(data):
    result = {}
    for key in LIMITS:
        default=DEFAULTS[key]
        value = float(data.get(key, default))
        if not math.isfinite(value):
            raise ValueError('Nonfinite setting')
        low, high = LIMITS[key]
        result[key] = max(low,min(high,value))
    prediction=data.get('predictionEnabled',True)
    if type(prediction) is not bool: raise ValueError('Invalid prediction setting')
    result['predictionEnabled']=prediction
    correction=data.get('autocorrectEnabled',True)
    if type(correction) is not bool: raise ValueError('Invalid autocorrect setting')
    result['autocorrectEnabled']=correction
    inertia=data.get('inertiaEnabled',True)
    if type(inertia) is not bool: raise ValueError('Invalid inertia setting')
    result['inertiaEnabled']=inertia
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

def stop_on_signal(signum, frame):
    # Quickshell/systemd terminate us with SIGTERM during reload or shutdown.
    # Raising exits through finally so a held microphone cannot be abandoned.
    raise SystemExit(0)

def main():
    signal.signal(signal.SIGTERM,stop_on_signal)
    signal.signal(signal.SIGINT,stop_on_signal)
    predictor=Predictor()
    corrector=Autocorrect(predictor)
    voice=Voice()
    pointer = subprocess.Popen([str(Path(__file__).parent/'build/yoga-pointer')], stdin=subprocess.PIPE, text=True)
    keyboard = subprocess.Popen([str(Path(__file__).parent/'build/yoga-keyboard')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    def keyboard_status():
        for status in keyboard.stdout:
            emit(status.strip())
    threading.Thread(target=keyboard_status, daemon=True).start()
    emit('ready')
    emit({'settings':load_settings()})
    threading.Thread(target=layout_monitor,daemon=True).start()
    try:
        for line in sys.stdin:
            try:
                e = json.loads(line)
                kind = e.get('type')
                if kind == 'voice':
                    corrector.reset()
                    try:
                        action=e.get('action')
                        if action not in ('start','stop','cancel'): raise ValueError('Invalid voice action')
                        getattr(voice,action)()
                        emit({'voice':'recording' if voice.owned else 'processing' if action=='stop' else 'idle'})
                    except (OSError,ValueError,subprocess.SubprocessError):
                        try: voice.cancel()
                        except (OSError,subprocess.SubprocessError): pass
                        emit({'voice':'error'})
                elif kind == 'resetWord':
                    corrector.reset()
                elif kind == 'settings':
                    save_settings(e['values'])
                elif kind == 'suggest':
                    prefix=e.get('prefix','')
                    suggestions=[]
                    if isinstance(prefix,str) and len(prefix)<=64:
                        try:
                            suggestions=predictor.corrections(prefix,e.get('language'),3)+predictor.suggest(prefix,e.get('language'),3)
                            suggestions=list(dict.fromkeys(suggestions))[:3]
                        except OSError: pass
                    emit({'suggestions':suggestions,'prefix':prefix,'requestId':e.get('requestId')})
                elif kind in ('language','keyboardGroup'):
                    index={'en':'0','ru':'1'}.get(e.get('language'))
                    if index is None: raise ValueError('Invalid language')
                    keyboard.stdin.write('g '+index+'\n'); keyboard.stdin.flush()
                    if kind == 'language':
                        result=subprocess.run(['hyprctl','switchxkblayout','all',index],capture_output=True,text=True,timeout=3,check=True)
                        if result.stdout.strip()!='ok': raise ValueError('Layout switch failed')
                        emit({'languageAck':True,'requestId':e.get('requestId')})
                elif kind == 'workspace':
                    result = subprocess.run(workspace_command(e['direction']),capture_output=True,text=True,timeout=3,check=True)
                    if result.stdout.strip() != 'ok':
                        raise ValueError('Workspace dispatch failed')
                elif kind in ('key', 'text'):
                    keyboard_args(e)  # Validate before serializing into private transport.
                    mod = sum({'ctrl':1,'alt':2,'logo':4,'shift':8}[m] for m in set(e.get('mods', [])))
                    command = f"k {e['key']} {mod}" if kind == 'key' else f"t {ord(e['text'])} {mod}"
                    commands=corrector.process(e)
                    keyboard.stdin.write('\n'.join(commands if commands is not None else [command])+'\n'); keyboard.stdin.flush()
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
                elif kind == 'scrollEnd':
                    pointer.stdin.write('e\n'); pointer.stdin.flush()
            except (ValueError, KeyError, TypeError, subprocess.SubprocessError, OSError):
                print('input-error', flush=True)
    finally:
        try: voice.cancel()
        except (OSError,subprocess.SubprocessError): pass
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

#!/usr/bin/env python3
"""Verify the touch router is loaded; rebuild once after an ABI update."""
import fcntl
import json
from pathlib import Path
import subprocess
import sys

BASE = Path(__file__).resolve().parent

def loaded():
    result = subprocess.run(['hyprctl','plugin','list','-j'], capture_output=True, text=True, check=True)
    return any(p.get('name') == 'yoga-panel-gesture' for p in json.loads(result.stdout))

def try_load():
    result = subprocess.run(['hyprctl','plugin','load',str(BASE/'build/yoga-panel-gesture.so')], capture_output=True, text=True)
    # Some hyprctl versions exit zero even when loading failed.
    print(result.stdout.strip() or result.stderr.strip(), flush=True)
    return loaded()

def main():
    (BASE/'build').mkdir(exist_ok=True)
    with (BASE/'build/plugin-load.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if loaded() or try_load():
            return
        print('Yoga touch router unavailable; rebuilding against installed Hyprland headers', flush=True)
        subprocess.run(['bash',str(BASE/'build-gesture.sh')], cwd=BASE, check=True)
        if not try_load():
            raise RuntimeError('Touch router could not load after rebuilding; check whether Hyprland needs a session restart after updates')

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'Yoga panel startup: {error}', file=sys.stderr)
        sys.exit(1)

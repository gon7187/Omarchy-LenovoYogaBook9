#!/usr/bin/env python3
"""Build before replacing the user installation. No root or package changes."""
import argparse
from datetime import datetime
from pathlib import Path
import shutil
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parent
HOME = Path.home()
TARGET = HOME/'.local/share/yoga-panel'

def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run',action='store_true')
    parser.add_argument('--no-start',action='store_true')
    args=parser.parse_args()
    destinations={
        SOURCE/'bin/yoga-panel':HOME/'.local/bin/yoga-panel',
        SOURCE/'systemd/yoga-panel.service':HOME/'.config/systemd/user/yoga-panel.service',
        SOURCE.parent/'bin/yoga-brightness-sync':HOME/'.local/bin/yoga-brightness-sync',
        SOURCE.parent/'config/systemd/user/yoga-brightness-sync.service':HOME/'.config/systemd/user/yoga-brightness-sync.service',
    }
    if args.dry_run:
        print('Build and install application:',TARGET)
        for destination in destinations.values(): print('Install:',destination)
        print('Back up existing files; enable panel and brightness synchronization services.')
        return
    for command in ['g++','gcc','pkg-config','wayland-scanner','quickshell','hyprctl','brightnessctl']:
        if not shutil.which(command): raise SystemExit('Missing dependency: '+command)
    TARGET.parent.mkdir(parents=True,exist_ok=True)
    backup=HOME/'.local/state/yoga-panel/backups'/datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    with tempfile.TemporaryDirectory(prefix='.yoga-panel-',dir=TARGET.parent) as staging:
        app=Path(staging)/'app'
        shutil.copytree(SOURCE,app,ignore=shutil.ignore_patterns('build','__pycache__','*.pyc'))
        run('bash','build.sh',cwd=app)
        run('bash','build-gesture.sh',cwd=app)
        subprocess.run(['systemctl','--user','stop','yoga-panel.service'],check=False)
        subprocess.run(['hyprctl','plugin','unload',str(TARGET/'build/yoga-panel-gesture.so')],check=False)
        backup.mkdir(parents=True)
        if TARGET.exists(): shutil.move(str(TARGET),str(backup/'app'))
        shutil.move(str(app),str(TARGET))
        for source,destination in destinations.items():
            destination.parent.mkdir(parents=True,exist_ok=True)
            if destination.exists(): shutil.copy2(destination,backup/destination.name)
            shutil.copy2(source,destination)
            if destination.parent.name=='bin': destination.chmod(0o755)
    run('systemctl','--user','daemon-reload')
    run('systemctl','--user','enable','yoga-panel.service','yoga-brightness-sync.service')
    if not args.no_start:
        run('systemctl','--user','restart','yoga-brightness-sync.service','yoga-panel.service')
    print('Installed. Previous files:',backup)
    print('Open with ~/.local/bin/yoga-panel show')

if __name__=='__main__': main()

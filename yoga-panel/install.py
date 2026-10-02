#!/usr/bin/env python3
"""Build before replacing the user installation. No root or package changes."""
import argparse
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
HOME = Path.home()
TARGET = HOME/'.local/share/yoga-panel'

def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run',action='store_true')
    parser.add_argument('--no-start',action='store_true')
    parser.add_argument('--previous-app',type=Path,help='Previous application directory when migrating a development installation')
    args=parser.parse_args()
    destinations={
        SOURCE/'bin/yoga-panel':HOME/'.local/bin/yoga-panel',
        SOURCE/'systemd/yoga-panel.service':HOME/'.config/systemd/user/yoga-panel.service',
        SOURCE.parent/'bin/yoga-recovery':HOME/'.local/bin/yoga-recovery',
        SOURCE.parent/'bin/yoga-brightness-sync':HOME/'.local/bin/yoga-brightness-sync',
        SOURCE.parent/'config/systemd/user/yoga-brightness-sync.service':HOME/'.config/systemd/user/yoga-brightness-sync.service',
        SOURCE.parent/'bin/yoga-mode':HOME/'.local/bin/yoga-mode',
        SOURCE.parent/'bin/yoga-speedtest-reaper':HOME/'.local/bin/yoga-speedtest-reaper',
        SOURCE.parent/'config/systemd/user/yoga-speedtest-reaper.service':HOME/'.config/systemd/user/yoga-speedtest-reaper.service',
        # Credentials stay out of the repository: the unit fails until ~/.config/smb-a24/credentials exists.
        SOURCE.parent/'bin/smb-a24-mount':HOME/'.local/bin/smb-a24-mount',
        SOURCE.parent/'config/systemd/user/smb-a24.service':HOME/'.config/systemd/user/smb-a24.service',
        SOURCE.parent/'config/systemd/user/smb-a24.timer':HOME/'.config/systemd/user/smb-a24.timer',
        # The speaker sink closes after 30 s of silence only because yoga-amp-arm makes
        # every reopen reload the amp calibration; the two ship together. WirePlumber
        # reads the rule on its next start.
        SOURCE.parent/'bin/yoga-amp-arm':HOME/'.local/bin/yoga-amp-arm',
        SOURCE.parent/'config/systemd/user/yoga-amp-arm.service':HOME/'.config/systemd/user/yoga-amp-arm.service',
        SOURCE.parent/'config/wireplumber/52-yoga-speakers-keep-open.conf':HOME/'.config/wireplumber/wireplumber.conf.d/52-yoga-speakers-keep-open.conf',
        SOURCE.parent/'config/vivaldi/vivaldi-stable.conf':HOME/'.config/vivaldi-stable.conf',
        SOURCE.parent/'config/hypr/minimize.lua':HOME/'.config/hypr/minimize.lua',
        SOURCE.parent/'config/hypr/yoga-windows.lua':HOME/'.config/hypr/yoga-windows.lua',
        SOURCE.parent/'config/hypr/yoga-titlebars.lua':HOME/'.config/hypr/yoga-titlebars.lua',
        # Omarchy reads menu extensions only from extensions/; the bar's auto-brightness
        # switch and the menu's recovery entry call the two helpers.
        SOURCE.parent/'config/omarchy/omarchy-menu.jsonc':HOME/'.config/omarchy/extensions/omarchy-menu.jsonc',
        SOURCE.parent/'bin/yoga-autobrightness-toggle':HOME/'.local/bin/yoga-autobrightness-toggle',
        SOURCE.parent/'bin/yoga-reset-layout':HOME/'.local/bin/yoga-reset-layout',
        # Desktop widgets: the Quickshell config, its unit and the blur rule.
        # Turn them on from the Omarchy menu (Yoga Book — экраны -> Виджеты верхнего экрана).
        SOURCE.parent/'bin/yoga-widgets':HOME/'.local/bin/yoga-widgets',
        SOURCE.parent/'config/systemd/user/yoga-widgets.service':HOME/'.config/systemd/user/yoga-widgets.service',
        SOURCE.parent/'config/hypr/yoga-widgets.lua':HOME/'.config/hypr/yoga-widgets.lua',
        SOURCE.parent/'bin/yoga-ai-limits':HOME/'.local/bin/yoga-ai-limits',
        SOURCE.parent/'bin/yoga-wallpaper-luma':HOME/'.local/bin/yoga-wallpaper-luma',
        SOURCE.parent/'config/quickshell/yoga-widgets/shell.qml':HOME/'.config/quickshell/yoga-widgets/shell.qml',
        # The card material, shared by the widgets and test_widget_material.cjs.
        SOURCE.parent/'config/quickshell/yoga-widgets/material.js':HOME/'.config/quickshell/yoga-widgets/material.js',
        SOURCE.parent/'config/omarchy/shell.toml':HOME/'.config/omarchy/shell.toml',
        SOURCE.parent/'config/foot/foot.ini':HOME/'.config/foot/foot.ini',
        **{path:HOME/'.config/omarchy/plugins'/path.relative_to(SOURCE.parent/'config/omarchy/plugins')
           for path in (SOURCE.parent/'config/omarchy/plugins').glob('*/*') if path.is_file()},
    }
    if args.dry_run:
        print('Build and install application:',TARGET)
        for destination in destinations.values(): print('Install:',destination)
        print('Back up existing files; enable panel, brightness synchronization, speed test reaper and speaker amp arming services; install Omarchy post-update check.')
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
        # Title bars are optional: no network for the pinned source must not block an install.
        if subprocess.run(['bash','build-hyprbars.sh'],cwd=app).returncode: print('hyprbars not built; windows keep no title bars')
        subprocess.run(['systemctl','--user','stop','yoga-panel.service'],check=False)
        for old_app in {TARGET,args.previous_app} - {None}:
            for library in ('yoga-panel-gesture.so','hyprbars.so'):
                subprocess.run(['hyprctl','plugin','unload',str(old_app/'build'/library)],check=False)
        backup.mkdir(parents=True)
        if TARGET.exists(): shutil.move(str(TARGET),str(backup/'app'))
        shutil.move(str(app),str(TARGET))
        for source,destination in destinations.items():
            destination.parent.mkdir(parents=True,exist_ok=True)
            if destination.exists():
                saved=backup/destination.relative_to(HOME)
                saved.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(destination,saved)
            shutil.copy2(source,destination)
            if destination.parent.name=='bin': destination.chmod(0o755)
    hyprland=HOME/'.config/hypr/hyprland.lua'
    for module,comment in (('hypr.minimize','Three-finger swipe down/up: minimize/restore all windows on the workspace.'),
                           ('hypr.yoga-windows','Windows opened while the lower-screen keyboard is up go to the upper screen.'),
                           ('hypr.yoga-titlebars','Compact touch title bars: drag to move, close button.'),
                           ('hypr.yoga-widgets','Blur rule for the desktop widget layer.')):
        if hyprland.exists() and 'require("'+module+'")' not in hyprland.read_text():
            with hyprland.open('a') as config:
                config.write('\n-- '+comment+'\nrequire("'+module+'")\n')
    run('systemctl','--user','daemon-reload')
    run('systemctl','--user','enable','yoga-panel.service','yoga-brightness-sync.service','yoga-speedtest-reaper.service','yoga-amp-arm.service','smb-a24.timer')
    if not args.no_start:
        run('systemctl','--user','restart','yoga-brightness-sync.service','yoga-speedtest-reaper.service','yoga-panel.service')
        # Not via run(): the oneshot may wait 30 s for its control and fail, which must not abort the install.
        subprocess.run(['systemctl','--user','restart','--no-block','yoga-amp-arm.service'],check=False)
    if shutil.which('omarchy'):
        run('omarchy','hook','install','post-update',str(SOURCE.parent/'config/omarchy/hooks/90-yoga-check'))
        subprocess.run(['omarchy-shell','shell','rescanPlugins'],check=False)
        subprocess.run(['omarchy','plugin','enable','gon7187.sysstats'],check=False)
        # The clone hides the raw speaker sink behind yoga_dolby; enabling it replaces omarchy.audio.
        subprocess.run(['omarchy','plugin','enable','gon7187.audio'],check=False)
        subprocess.run(['omarchy','bar','put','gon7187.sysstats','--after','omarchy.weather'],check=False)
    print('Installed. Previous files:',backup)
    print('Open with ~/.local/bin/yoga-panel show')

if __name__=='__main__': main()

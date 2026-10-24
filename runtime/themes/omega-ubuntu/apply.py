#!/usr/bin/env python3
"""Darkstar Robotics appearance preset for the Omega-Ubuntu GNOME VM."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

def gs(*args):
    return subprocess.check_output(['gsettings', *args], text=True).strip()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--restore', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if os.geteuid() == 0 or not shutil.which('gsettings'):
        sys.exit('Run as your GNOME desktop user, without sudo; gsettings is required.')
    state = Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))/'darkstar-omega'
    asset = Path(os.environ.get('XDG_DATA_HOME', Path.home()/'.local/share'))/'darkstar-omega/wallpaper.svg'
    backup = state/'appearance-backup.json'
    if args.restore:
        if not backup.exists():
            sys.exit('No saved appearance backup found.')
        settings = json.loads(backup.read_text())
    else:
        settings = [
            ['org.gnome.desktop.interface', 'color-scheme', "'prefer-dark'"],
            ['org.gnome.desktop.interface', 'gtk-theme', "'Yaru-dark'"],
            ['org.gnome.desktop.interface', 'icon-theme', "'Yaru'"],
            ['org.gnome.desktop.interface', 'accent-color', "'orange'"],
            ['org.gnome.desktop.background', 'picture-uri', repr(asset.as_uri())],
            ['org.gnome.desktop.background', 'picture-uri-dark', repr(asset.as_uri())],
            ['org.gnome.desktop.background', 'picture-options', "'zoom'"],
            ['org.gnome.shell.extensions.dash-to-dock', 'dock-position', "'BOTTOM'"],
            ['org.gnome.shell.extensions.dash-to-dock', 'dash-max-icon-size', '40'],
        ]
    schemas = gs('list-schemas').splitlines()
    supported = []
    for schema, key, value in settings:
        if schema not in schemas or key not in gs('list-keys', schema).splitlines():
            print(f'SKIP unsupported: {schema} {key}')
            continue
        if gs('writable', schema, key) != 'true':
            sys.exit(f'Locked setting: {schema} {key}; no settings changed.')
        supported.append([schema, key, value])
        print(f'{schema} {key} = {value}')
    if args.dry_run:
        return
    if not args.restore:
        state.mkdir(parents=True, exist_ok=True)
        original = json.loads(backup.read_text()) if backup.exists() else []
        saved = {(s, k) for s, k, _ in original}
        for schema, key, _ in supported:
            if (schema, key) not in saved:
                original.append([schema, key, gs('get', schema, key)])
        temp = backup.with_suffix('.tmp')
        temp.write_text(json.dumps(original, indent=2)+'\n')
        temp.replace(backup)
        asset.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(Path(__file__).with_name('wallpaper.svg'), asset)
    for schema, key, value in supported:
        subprocess.run(['gsettings', 'set', schema, key, value], check=True)
    print('Appearance restored.' if args.restore else 'Omega-Ubuntu appearance applied.')

if __name__ == '__main__':
    main()

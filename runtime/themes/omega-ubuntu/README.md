# Omega-Ubuntu VM — Darkstar appearance

Optional GNOME desktop preset matching the Darkstar Robotics palette in
Sources/RoboticsControlCenter/Theme.swift: charcoal, Starfire orange,
Signal Cyan and Ice White. Includes an original 3840×2160 SVG wallpaper
with a geometric star/orbit emblem, native Yaru dark apps and a bottom dock.

## Apply inside the VM

From the repository root in your logged-in GNOME desktop terminal:

```bash
python3 runtime/themes/omega-ubuntu/apply.py --dry-run
python3 runtime/themes/omega-ubuntu/apply.py
```

Run without sudo. Requires Python 3, GNOME gsettings and standard Ubuntu
Yaru assets; no downloads or package installs. Intended for Ubuntu
22.04/24.04 GNOME. Unsupported accent/dock settings are skipped.
Libadwaita apps follow the native dark preference; this does not replace
GNOME Shell CSS or provide custom widget colors. XFCE/KDE are unsupported.

## Restore

```bash
python3 runtime/themes/omega-ubuntu/apply.py --restore --dry-run
python3 runtime/themes/omega-ubuntu/apply.py --restore
```

Original settings are saved before changes in
~/.local/state/darkstar-omega/appearance-backup.json (or XDG_STATE_HOME).
Repeated applications preserve that original backup. Wallpaper is copied
to ~/.local/share/darkstar-omega (or XDG_DATA_HOME) so moving the repo
does not break it. Restore retains the backup and asset for reuse.
Application is not transactional; run restore after an interrupted apply.

This is a manual appearance preset, not automatically invoked by the
macOS app or installer. It does not rename the VM or alter ROS, boot,
login, or system configuration. Not yet visually verified in the actual VM.

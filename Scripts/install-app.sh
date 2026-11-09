#!/bin/bash
# Builds the app and puts it in /Applications, keeping the old copy until
# the new one is verified. Points the Desktop shortcut at it and opens it.
#   NO_OPEN=1  don't launch afterwards
set -euo pipefail
source "$(dirname "$0")/_env.sh"

APP_ONLY=1 bash "$DARKSTAR_SRC/Scripts/package.sh"
NEW="$DARKSTAR_DIST/$DARKSTAR_APP_NAME.app"
DEST="/Applications/Darkstar Robotics.app"

c_step "Installing to $DEST"
osascript -e "quit app \"$DARKSTAR_APP_NAME\"" 2>/dev/null || true
BACKUP_DIR="$(mktemp -d)"
HAD_OLD=0
if [[ -d "$DEST" ]]; then
  mv "$DEST" "$BACKUP_DIR/"
  HAD_OLD=1
fi
if ditto "$NEW" "$DEST" && codesign --verify --deep --strict "$DEST"; then
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  c_ok "Installed $DARKSTAR_APP_NAME $DARKSTAR_VERSION"
  c_ok "Previous copy (if any) kept at $BACKUP_DIR until macOS clears temp files"
else
  [[ -d "$DEST" ]] && mv "$DEST" "$BACKUP_DIR/failed-install.app"
  (( HAD_OLD == 1 )) && mv "$BACKUP_DIR/Darkstar Robotics.app" "$DEST"
  c_fail "Install failed; the previous app was put back."; exit 1
fi

# Desktop shortcut: only replace it if it is missing or already a link.
LINK="$HOME/Desktop/Darkstar Robotics.app"
if [[ -L "$LINK" || ! -e "$LINK" ]]; then
  ln -sfn "$DEST" "$LINK" && c_ok "Desktop shortcut → $DEST"
else
  c_warn "$LINK is a real app copy, not a shortcut; left it alone."
fi

[[ "${NO_OPEN:-0}" == "1" ]] || open "$DEST"

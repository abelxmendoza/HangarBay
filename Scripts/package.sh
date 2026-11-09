#!/bin/bash
# Builds Darkstar Robotics.app (+ the installer app and zips) into
# ../DarkstarRobotics-Dist. Same steps as ~/Desktop/projects/package-0.4.0.sh,
# but the version comes from ./VERSION and paths from this checkout.
#   APP_ONLY=1  skip the installer + zips (what `dev.sh install` uses)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

VERSION="$DARKSTAR_VERSION"
BUILD="${DARKSTAR_BUILD:-$(echo "$VERSION" | cut -d. -f2)}"
APP_ID="com.abelxmendoza.darkstarrobotics"
INST_NAME="Darkstar Robotics Installer"
INST_ID="com.abelxmendoza.darkstarrobotics.installer"
mkdir -p "$DARKSTAR_DIST"

make_icon() { # $1 = source png, $2 = output .icns
  local iconset s
  iconset="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$1" --out "$iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$1" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$2"
}

write_plist() { # $1 path, $2 executable, $3 bundle id, $4 display name
  cat > "$1" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$4</string>
    <key>CFBundleDisplayName</key><string>$4</string>
    <key>CFBundleExecutable</key><string>$2</string>
    <key>CFBundleIdentifier</key><string>$3</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>$4 controls the UTM runtime VM (status, start, stop) through UTM's utmctl.</string>
</dict>
</plist>
PLIST
}

assemble() { # $1 bin dir, $2 exe, $3 bundle path (.app), $4 bundle id, $5 display name, $6 icon png
  local bundle="${3:?bundle path required}"
  [[ "$bundle" == *.app ]] || { c_fail "refusing to replace non-.app path: $bundle"; exit 1; }
  rm -rf "$bundle"
  mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
  cp "$1/$2" "$bundle/Contents/MacOS/$2"
  local b
  for b in "$1"/*.bundle; do [[ -e "$b" ]] && cp -R "$b" "$bundle/Contents/Resources/"; done
  make_icon "$6" "$bundle/Contents/Resources/AppIcon.icns"
  write_plist "$bundle/Contents/Info.plist" "$2" "$4" "$5"
  codesign --force --deep -s - "$bundle"
  c_ok "assembled + signed: $bundle"
}

c_step "Building $DARKSTAR_APP_NAME $VERSION (release)"
cd "$DARKSTAR_SRC"
swift build -c release --product RoboticsControlCenter
APP_BUNDLE="$DARKSTAR_DIST/$DARKSTAR_APP_NAME.app"
assemble "$(swift build -c release --show-bin-path)" RoboticsControlCenter "$APP_BUNDLE" "$APP_ID" "$DARKSTAR_APP_NAME" \
  "$DARKSTAR_SRC/Sources/RoboticsControlCenter/hangar-bay-logo.png"

[[ "${APP_ONLY:-0}" == "1" ]] && exit 0

c_step "Building installer"
if ! grep -q "newVersion = \"$VERSION\"" "$DARKSTAR_INSTALLER_SRC/Sources/DarkstarInstaller/DarkstarInstallerApp.swift"; then
  c_fail "DarkstarInstallerApp.swift newVersion does not match VERSION ($VERSION). Update it first."; exit 1
fi
PAYLOAD_DIR="$DARKSTAR_INSTALLER_SRC/Sources/DarkstarInstaller/Payload"
mkdir -p "$PAYLOAD_DIR"
rm -rf "${PAYLOAD_DIR:?}/${DARKSTAR_APP_NAME:?}.app"
cp -R "$APP_BUNDLE" "$PAYLOAD_DIR/$DARKSTAR_APP_NAME.app"
cd "$DARKSTAR_INSTALLER_SRC"
swift build -c release --product DarkstarInstaller
INST_BUNDLE="$DARKSTAR_DIST/$INST_NAME.app"
ICON_SRC="$DARKSTAR_INSTALLER_SRC/Sources/DarkstarInstaller/installer-logo.png"
[[ -f "$ICON_SRC" ]] || ICON_SRC="$DARKSTAR_SRC/Sources/RoboticsControlCenter/hangar-bay-logo.png"
assemble "$(swift build -c release --show-bin-path)" DarkstarInstaller "$INST_BUNDLE" "$INST_ID" "$INST_NAME" "$ICON_SRC"

c_step "Zipping"
rm -f "$DARKSTAR_DIST/DarkstarRobotics-v$VERSION.zip" "$DARKSTAR_DIST/DarkstarRobotics-Installer-v$VERSION.zip"
ditto -c -k --keepParent "$APP_BUNDLE"  "$DARKSTAR_DIST/DarkstarRobotics-v$VERSION.zip"
ditto -c -k --keepParent "$INST_BUNDLE" "$DARKSTAR_DIST/DarkstarRobotics-Installer-v$VERSION.zip"
codesign --verify --deep --strict "$APP_BUNDLE" && c_ok "app codesign OK"
codesign --verify --deep --strict "$INST_BUNDLE" && c_ok "installer codesign OK"

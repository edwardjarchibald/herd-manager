#!/usr/bin/env bash
# Compile the AppleScript sources in apps/ into ~/Applications/*.app (Terminal icon).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="${HERD_APPS_DIR:-$HOME/Applications}"
icon="/System/Applications/Utilities/Terminal.app/Contents/Resources/Terminal.icns"
mkdir -p "$dest"

build() { # <source.applescript> <App Name> <bundle id>
  local src="$1" bid="$3" app="$dest/$2.app"
  osacompile -o "$app" "$src"
  if [[ -f "$icon" ]]; then
    cp "$icon" "$app/Contents/Resources/applet.icns"
    rm -f "$app/Contents/Resources/Assets.car"
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$app/Contents/Info.plist" 2>/dev/null || true
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bid" "$app/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $bid" "$app/Contents/Info.plist"
  codesign -f -s - "$app" >/dev/null 2>&1 || true
  touch "$app"
  echo "built $app"
}

build "$here/apps/herd-terminal.applescript" "Herd Terminal" "dev.herd-manager.terminal"
build "$here/apps/herd-manager.applescript"  "Herd Manager"  "dev.herd-manager.manager"
echo "Drag the apps from $dest to the Dock. The first click asks to allow controlling Terminal."

#!/usr/bin/env bash
# Remove the herd symlink and the Dock apps. herdr sessions and config are left untouched.
set -euo pipefail
bindir="${HERD_BIN_DIR:-$HOME/.local/bin}"
dest="${HERD_APPS_DIR:-$HOME/Applications}"
if [[ -L "$bindir/herd" ]]; then rm "$bindir/herd"; echo "removed $bindir/herd"; fi
for app in "Herd Terminal" "Herd Manager"; do
  if [[ -d "$dest/$app.app" ]]; then rm -rf "${dest:?}/$app.app"; echo "removed $dest/$app.app"; fi
done
echo "Left in place: ~/.config/herd (window records) and your herdr sessions/config."

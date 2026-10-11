#!/usr/bin/env bash
# Install herd: symlink bin/herd into ~/.local/bin, build the Dock apps, optionally tune herdr.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bindir="${HERD_BIN_DIR:-$HOME/.local/bin}"
herdr_cfg="${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}"

[[ "$(uname -s)" == "Darwin" ]] || { echo "herd needs macOS (Terminal.app)." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found. Install Xcode Command Line Tools or Homebrew python." >&2; exit 1; }
if ! command -v herdr >/dev/null && [[ ! -x /opt/homebrew/bin/herdr ]]; then
  echo "herdr not found. Install it first: see https://herdr.dev (e.g. 'brew install herdr' if available), then re-run." >&2
  exit 1
fi

mkdir -p "$bindir"
if [[ -e "$bindir/herd" && ! -L "$bindir/herd" ]]; then
  mv "$bindir/herd" "$bindir/herd.bak-$(date +%Y%m%d%H%M%S)"
  echo "backed up existing $bindir/herd"
fi
ln -sfn "$here/bin/herd" "$bindir/herd"
echo "linked $bindir/herd -> $here/bin/herd"
case ":$PATH:" in *":$bindir:"*) ;; *) echo "WARNING: $bindir is not on your PATH. Add: export PATH=\"$bindir:\$PATH\"";; esac

"$here/scripts/build-apps.sh"

echo
echo "Optional: herdr's direct attach enables mouse reporting by default, which blocks"
echo "Terminal.app's normal drag-select/copy. Setting [ui] mouse_capture = false fixes that"
echo "(herdr's own mouse UI is then off; scroll via herdr pane read / 'herd copy')."
read -r -p "Set mouse_capture = false in $herdr_cfg now? [y/N] " ans || ans=""
if [[ "$ans" =~ ^[Yy]$ ]]; then
  mkdir -p "$(dirname "$herdr_cfg")"; touch "$herdr_cfg"
  if grep -q '^[[:space:]]*mouse_capture' "$herdr_cfg"; then
    echo "mouse_capture already set in $herdr_cfg; leaving it alone."
  else
    cp "$herdr_cfg" "$herdr_cfg.bak-$(date +%Y%m%d%H%M%S)"
    if grep -q '^\[ui\]' "$herdr_cfg"; then
      sed -i '' '/^\[ui\]/a\
mouse_capture = false
' "$herdr_cfg"
    else
      printf '\n[ui]\nmouse_capture = false\n' >> "$herdr_cfg"
    fi
    herdr server reload-config >/dev/null 2>&1 || true
    echo "set; applies to newly attached windows."
  fi
fi
echo "Done. Try: herd new && herd ls   (or click Herd Terminal in ~/Applications)"

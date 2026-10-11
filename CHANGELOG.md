# Changelog

## 0.2.1 (2026-10-11)

- Default session name is now a stable `dev-<N>` (lowest free number, never renumbered); only
  issue worktrees get `<prefix>-<issue>`. The detail line still shows `<repo>/<branch>` or the cwd.
- Removed Shift-Enter handling.
- Window outline: 9px ring in the highlight bar's cyan (Terminal ANSI cyan 51/187/200) with corners
  concentric to the window's (16pt radius on macOS 26, 10pt before); configurable via env vars.

## 0.2.0 (2026-10-11)

- Security: `herd ls` and the manager no longer show full command lines (they can contain
  secrets passed as arguments). Only the agent name or the program's basename is shown.
- Automatic session names: `<prefix>-<issue>` in linked worktrees with an issue number (prefix =
  2-4 letter repo abbreviation, overridable in `~/.config/herd/prefixes.json`), otherwise the cwd
  folder name (`~` for home); duplicates get `-2`. Names follow cwd/branch changes, manual names
  stick (`herd rename --auto` to undo). New `herd names [--dry-run]`.
- Detail line / `herd ls` CWD column: `<repo>/<branch>` inside git, else the cwd with `~`.
- Names may contain `/`, `~`, spaces and parentheses; commands accept unique name prefixes; window
  commands are shell-quoted and windows attach by workspace id.
- Manager: Shift-Enter (CSI 13;2u, CSI 27;2;13~, ESC CR) creates a session like `N`.
- The selected session's Terminal window gets a green outline from a small click-through,
  non-activating Swift overlay helper (`helper/herd-outline.swift`); `HERD_NO_OUTLINE=1` disables it.

## 0.1.1 (2026-10-11)

- Fix: Herd Terminal failed right after login when Terminal.app wasn't running
  (`launch` creates no window, so `do script ... in window 1` errored). Terminal is now
  launched and awaited; a default window is reused if one appears, otherwise `do script`
  creates one. The window-id lookup is retried, and `activate` runs only after it.
- `herd` starts a background `herdr server` on demand if none is running (no duplicates).
- AppleScript failures now surface the real osascript error (with an Automation hint)
  instead of a Python traceback; the Dock apps show it in an alert.

## 0.1.0 (2026-10-11)

First public release.

- `herd` CLI: named herdr-backed sessions, one plain Terminal.app window each.
- Even-grid auto-tiling of herd-created windows only, with a fixed-width manager column.
- `herd manager`: curses session manager with mouse support, auto-reload, and
  csshx-style live broadcast to all attached sessions.
- `killall` with glob patterns, `detach`, `broadcast`, `cleanclip`, `copy`, `paste`.
- Dock apps (Herd Terminal, Herd Manager) built from AppleScript sources.

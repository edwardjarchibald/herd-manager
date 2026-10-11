# Changelog

## 0.4.2 - 2026-10-11

### Changed
- New dock-on layout: a fixed 5x3 grid of equal cells over the whole tiled area.
  - (r1,c1) is the manager, the same size as a terminal cell. At 2560x1440 that is about 48x19 characters; the hints wrap to three lines.
  - The dock is the 2x2 block c1-c2 x r2-r3, including the gaps.
  - Terminals fill r1 c2-c5 first, then c3-c5 x r2-r3: 10 slots. With fewer terminals the remaining cells stay empty, and the grid never stretches.
  - More than 10: an even grid over c3-c5 at full height. r1 c2 stays empty and the manager and dock are unchanged.
- Z zooms to 80% of the c3-c5 area (full height), centered, off the manager and dock. Dock-off mode is unchanged.

## 0.4.1 - 2026-10-11

### Fixed
- herd-dock crashed (integer conversion trap) on the first mouse-down while the dock was empty, so the outline and docking never ran.

## 0.4.0 - 2026-10-11

### Added
- **Dock area** in the lower left, directly under the manager. With the dock on, the left column is the manager (MGR_W = 520 px wide, upper ~40%) above the dock (lower ~60%, max(520, 30% of the display width) wide; 768x800 on a 2560x1440 display). Up to 8 terminals tile in the even grid to the right and never under the dock. Z zooms within that terminal area.
- New helper `helper/herd-dock.swift`, compiled on first use into `~/.cache/herd/herd-dock` and started by the manager. It is click-through and never takes focus, and it exits with the manager.
  - It shows a faint dashed outline while the dock is empty and Terminal is active.
  - Every 0.1 s it reads window bounds from CGWindowList (bounds only).
  - A non-Terminal window whose frame changes while the mouse button is down, with its center inside the area, turns the outline bright with "docking activated".
  - On release, once the frame has been stable for 0.35 s, it moves/resizes that one window to fill the area (Accessibility AXPosition/AXSize) and records it in `~/.config/herd/dock.json` (pid, bundle, window id).
  - Dragging it out (center leaves the area), closing it, or quitting the app undocks it.
- The docked app is kept above the group: after a retile and after F-on, herd activates the docked app, then re-activates Terminal for the manager only, so the manager keeps keyboard focus. F excludes the docked app: F-on leaves it visible, and F-behind restores the other apps, with the docked app just under the original top app.
- `~/.config/herd/config.json`: `{"dock": false}` turns the dock off (manager full column height, tiling as before). The default is on.

## 0.3.0 - 2026-10-11

### Changed
- F now restores the whole stack of apps that were in front of the group, not just one. While another app is in front, the manager keeps a snapshot of every regular app above Terminal, in front-to-back order (`lsappinfo visibleProcessList`, with accessory/background apps dropped). On "behind" they are re-activated bottom-most first and the original top app last, and the top app is checked to be frontmost (with a retry via `open -b`).
- Focus events (manager start, on, behind, result) are always logged to `~/.cache/herd/focus.log`, rotated at 200 KB.

### Fixed
- 0.2.9 kept only one "previous app" pid, sampled once a second. Any regular app that was briefly frontmost (e.g. Wispr Flow while dictating) could replace the app you were really using. The fallback also had no ordering beyond the first match.

## 0.2.9 - 2026-10-11

### Fixed
- F "behind" didn't return to the app you were using (e.g. an Electron app such as Grok Bot). The app was only captured at the moment F was pressed, so after clicking the manager first it was Terminal and nothing was stored. The fallback (a JXA CGWindowList scan) always returned empty because CoreGraphics isn't reachable from JXA. Now the manager poll loop records the last non-Terminal frontmost app about once a second. The fallback uses `lsappinfo visibleProcessList` (front-to-back app order). Activation is verified, with a retry via `open -b <bundle id>`. Set `HERD_DEBUG=1` to log to `~/.cache/herd/focus.log`.

## 0.2.8 - 2026-10-11

### Added
- Manager key `F` (toggle focus) for the whole herd group: the manager plus every herd-tracked Terminal window in windows.json. Other Terminal windows are never touched. On: it remembers the frontmost app, raises each herd window (the zoomed one above the tiles), and activates Terminal with the manager frontmost so it keeps keyboard focus. Behind: it re-activates the remembered app with all its windows (or, if none is known, the frontmost non-Terminal app), so whatever sits under the group shows on top. Nothing is minimized or hidden. The outline hides while the group is behind and comes back once Terminal is frontmost again.

### Changed
- Bottom hint line is now `(K) kill  (A) killall  (Q) quit  (H) toggle hints  (F) toggle focus`.

## 0.2.7 - 2026-10-11

### Changed
- Hints cleaned up to exactly two lines: `(N) new  (O) open  (X) detach  (Z) toggle zoom` / `(Q) quit  (K) kill  (A) killall  (H) toggle hints`. They wrap only when the window is too narrow.
- Broadcast area: a dim `> click for broadcast` when idle. When live it shows a bright `> ` and a yellow `click list to end broadcast` below.
- `O` opens the selected session (non-activating). It replaces Enter, which does nothing in list mode (live broadcast still forwards Enter).

## 0.2.6 - 2026-10-11

### Fixed
- Manager keys Z, K, X, A and N pulled Terminal in front of the frontmost app. `refocus_manager()` called `focus_window()`, which runs `activate`. It now only re-orders the manager to the top of Terminal's own windows, never activates Terminal, and is wrapped in a `keep_front()` safety net that hands the front back to the previous app if it changed. The same net wraps the non-activating raise used by selection and Enter. The Z handler moved into `mgr_zoom()`.

## 0.2.5 - 2026-10-11

### Added
- Manager key `Z` (and `herd zoom <name>`): toggles zoom on the selected session's window. It is raised without activating Terminal and sized to ~80% of the grid area, centered. The state is stored in windows.json. Retiles keep the zoomed window on top and tile the others underneath. Z again, or Z on another session, unzooms. The outline follows it, and a session without a window shows "not attached".

## 0.2.4 - 2026-10-11

### Fixed
- Enter on a session whose herd window had lost its record (e.g. `dev-4`, renamed from `git`) only retiled and showed nothing. Records were keyed by session name, and an old window's exit cleanup removed the record under a name that by then belonged to another session. The new window's attach then lost to the still-attached orphan window and closed at once.
- `windows.json` is now keyed by herdr terminal id, so renames never break records. Old files migrate automatically.
- Opening a session whose orphaned herd window still exists adopts that window and brings it forward instead of opening a duplicate.
- New windows attach with `--takeover`. A window that closes right after opening now shows an error in the manager status line.

## 0.2.3 (2026-10-11)

- Removed double-click-to-open; a single click selects.
- Manager Enter and N never activate Terminal: a new window opens without `activate` and is tiled,
  an existing one is raised within Terminal behind the manager, the manager keeps keyboard focus and
  the outline follows. If macOS activates Terminal anyway, the previously frontmost app is re-fronted
  (NSRunningApplication via JXA; no Accessibility). The Dock app still activates Terminal.

## 0.2.2 (2026-10-11)

- Outline overlay now lives at the normal window level, ordered directly above the selected
  Terminal window (found by Terminal's PID + bounds via CGWindowList), so other apps in front cover
  it. Ordering is re-asserted every 0.5 s and on app switches.
- Selecting a session raises its window to the top of Terminal's own stack (just behind the
  manager) without activating Terminal; the manager keeps keyboard focus.

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

# herd-manager

**Named [herdr](https://herdr.dev)-backed Terminal.app sessions with auto-tiling, a session manager and csshx-style live broadcast, for macOS.**

Each session is a persistent herdr terminal with a readable name (`dev-1`, `dev-2`, or `mr-42` for an issue worktree) shown in its own
plain Terminal.app window. Windows tile into an even grid; a narrow manager column lists every session.
Because sessions live in the background herdr server, you (or a script or AI agent) can read and type
into any session by name, and closing a window never kills the session.

> Screenshot: _coming soon_ (manager column on the left, session windows in a 3×2 grid).

## Requirements

- macOS with Terminal.app
- [herdr](https://herdr.dev) (0.9.x) with its background server
- python3 (the Xcode Command Line Tools one is fine; stdlib only)
- optional: `swiftc` (Xcode Command Line Tools) for the green window outline

No window manager and no Accessibility permission are needed. herd talks to Terminal through its
AppleScript dictionary, so macOS asks once for permission to control Terminal.

## Install

```sh
git clone https://github.com/edwardjarchibald/herd-manager.git
cd herd-manager
./install.sh
```

The installer symlinks `bin/herd` into `~/.local/bin` (it warns if that isn't on your `PATH`), builds
**Herd Terminal.app** and **Herd Manager.app** into `~/Applications`, and offers to set herdr's
`[ui] mouse_capture = false` (see [Copy and paste](#copy-and-paste)). Drag the apps to the Dock.
`./uninstall.sh` removes the symlink and the apps; sessions and config are left alone.

## Usage

### Dock apps

- **Herd Terminal**: opens the manager if it isn't open, then a new session window, and retiles.
- **Herd Manager**: opens the manager window, or brings it to the front.

### Commands

| Command | What it does |
|---|---|
| `herd new [DIR\|NAME] [-C DIR]` | Create a session with cwd DIR (`~` expanded, relative to your cwd; default `~`) and an automatic name (ee-<issue> in a worktree, otherwise dev-N). A non-path argument is a manual NAME. Prints name, terminal id, pane id |
| `herd ls` | List sessions: name, terminal id, pane id, cwd, program (agent name or program basename; never the full command line) |
| `herd open <name>` | Open (or focus) a tiled Terminal window attached to the session |
| `herd attach <name>` | What each window runs: attach, then clean up and retile on exit |
| `herd detach <name>` | Close the session's window but keep the session running |
| `herd zoom <name>` | Toggle zoom on the session's window |
| `herd kill <name>` | Kill a session and close its window |
| `herd killall [GLOB…]` | Kill **all** herdr sessions, or only names matching any glob (`'dev*'`). No confirmation |
| `herd tile` | Retile herd windows now |
| `herd manager [--window]` | Run the manager TUI (`--window`: open/focus its window) |
| `herd broadcast '<text>'` | Run text + Enter in every session that has an open window |
| `herd cleanclip` | Strip trailing padding spaces from the clipboard |
| `herd copy <name>` / `herd paste <name>` | Copy a session's whole output to the clipboard / paste the clipboard into it (no Enter) |
| `herd id <name>` | Print the herdr pane id |
| `herd rename <old> <new>` | Rename a session manually (the name sticks) |
| `herd rename --auto <name>` | Return a session to automatic naming |
| `herd names [--dry-run]` | Run one automatic-naming pass now |
| `herd app` | What Herd Terminal runs: manager (if needed) + new session |

### Dock area

With the dock on (the default), the left panel is max(30% of the tiled width, `dock_min_width`): the manager on top (exactly one
row of a 3-row grid) and the dock below it. Terminals tile adaptively in the area to the right:

```
+---------+------+------+------+
| manager |  t1  |  t4  |  t7  |      terminals (rows of cells):
+---------+------+------+------+        1 = full    2 = 2 columns   3 = 2 + 1 (full width)
|         |  t2  |  t5  |  t8  |        4 = 2x2     5 = 2 + 2 + 1   6 = 3 rows x 2
|  dock   +------+------+------+        7+ = 3 rows, a new column per 3 terminals, filled top to
|         |  t3  |  t6  |  t9  |        bottom; a partly filled last column's cells share its height
+---------+------+------+------+        (9 shown; 10+ = 4 columns, ...)
```

Z zooms to 80% of the terminal area, centered. The manager lists one line per session and picks the
largest font (Monaco, up to 16) that fits all of them plus the divider and broadcast line.

- The empty dock shows a faint dashed outline while Terminal is active.
- Drag any app window (e.g. Grok Bot) so its center is over the dock. The outline turns bright with
  "docking activated". Let go, and that window is moved and resized to fill the dock.
- Drag it out again (center leaves the dock) to undock it.
- The docked window stays above the herd group, including after retiles and F. F never pushes it behind.
- Only the one window you drop in is ever moved. Herd reads other windows' bounds only to notice a drag.
- Resizing needs Accessibility for Terminal (System Settings > Privacy & Security > Accessibility).
- State is kept in `~/.config/herd/dock.json` and the area in `~/.config/herd/dock-area.json` (written by `herd tile`).

Config file `~/.config/herd/config.json` (JSON):

```json
{"dock": true, "dock_min_width": 920}
```

- `dock`: `false` turns the dock off. The manager gets its full column height and tiling works as before.
- `dock_min_width`: the minimum width of the left panel (manager and dock) in px. The default is 920, wide
  enough for Grok Bot's window so bot names show.

### Manager keys

Commands are uppercase on purpose; lowercase letters do nothing except `j`/`k`, plus `?` for the hints. The manager has no header or permanent hints: just the session list, a divider and one broadcast/status line. In dock mode its window gets the largest font up to 16 that fits every session on one line.

| Key | Action |
|---|---|
| `↑`/`↓`, `j`/`k`, wheel | Move the selection |
| click | Select a session |
| `O` | Toggle: open the session's window (tiled, without activating Terminal; the manager keeps focus), or, if it has one, detach and close it (the session keeps running) |
| `N` | New session and window (also without activating Terminal) |
| `Z` | Zoom toggle: raise the selected window (without activating Terminal) and size it to ~80% of the grid area, centered. Retiles keep it zoomed; Z again, or Z on another session, unzooms |
| `K` | Kill the selected session (no prompt) |
| `A` | Kill **all** sessions (asks y/N) |
| `?` / `H` | Toggle the hints overlay (Esc also closes it) |
| `F` | Focus toggle for the whole herd group (manager + every herd-tracked Terminal window, never other Terminal windows). First press: raises them all above other apps, manager frontmost with keyboard focus. Second press: re-activates every app that was in front of the group, in their original order, so the original top app is on top again and their windows cover the group (log: `~/.cache/herd/focus.log`). Nothing is minimized or hidden; click the manager to get it back. The outline hides while the group is behind |
| `Q` | Quit the manager (sessions keep running) |
| click `> click for broadcast` (bottom line) | Live broadcast: every keystroke goes to all sessions with an open window (drive vi in all of them at once); nothing is echoed |
| click the list | End live broadcast (`(click list to end)` in yellow at the right of the bottom line) |

The manager reloads itself when `bin/herd` changes, keeping the selection.

The selected session's own Terminal window gets a 6px outline in the selection colour (slate blue
#005faf, the same as the selected row), hugging the window's rounded corners (16pt on macOS 26, 10pt before;
override with `HERD_OUTLINE_PX`, `HERD_OUTLINE_RADIUS`, `HERD_OUTLINE_RGB`), drawn by a tiny helper
(`helper/herd-outline.swift`, compiled with `swiftc` into `~/.cache/herd` on first use; skipped if
swiftc isn't available). It's a borderless, click-through, non-activating overlay at the normal window level, kept directly
above the selected Terminal window (apps in front of that window also cover the outline). Selecting a
session also raises its window within Terminal (behind the manager) without stealing focus. It needs
no Accessibility permission. It follows the window's bounds about once a second, hides
when that window isn't on screen (another Space, minimized, under a fullscreen app), and exits with the
manager. Set `HERD_NO_OUTLINE=1` to disable it.

## Session names

Names follow each session's working directory automatically (the manager rechecks every 2 s):

- In a linked git worktree whose branch (or folder) carries an issue number: `<prefix>-<issue>`,
  e.g. `bh-6` for BlackHole issue 6. The prefix is a 2-4 letter abbreviation of the repo name
  (origin remote name, else the main worktree folder); override it in `~/.config/herd/prefixes.json`
  (`{"MyRepo": "mr"}`).
- Everything else: `dev-<N>` (lowest free number). A dev-N name stays stable; it isn't renumbered.
- Manual names (`herd new <name>`, `herd rename`) stick until `herd rename --auto <name>`.

The detail line in the manager (and the CWD column of `herd ls`) shows `<repo>/<branch>` inside git
(main repo folder name, also for worktrees; short hash when detached), else the cwd with `~`.
Commands that take a name also accept a unique prefix; quote names with spaces.

## Tiling

- The manager is a 520px column at the left of the display; session windows share the rest in an even
  grid (1 full, 2–3 columns, 2×2, then 3 columns; a partial last row widens to fill).
- **Only windows herd created are ever moved or closed.** They're tracked by Terminal window id in
  `~/.config/herd/windows.json`; other Terminal windows are never touched.
- Spaces: herd sets window bounds only and can't move windows between Spaces. A herd window on another
  Space but the same display still takes a grid slot. Using herd on its own Space works best.
- Tip: disable *System Settings → Desktop & Dock → "When switching to an application, switch to a Space
  with open windows for the application"* if clicking herd windows keeps jumping Spaces.

## Copy and paste

- Each window runs `herdr terminal attach`, which by default turns on mouse reporting, so Terminal's
  drag-select doesn't work. Set `[ui] mouse_capture = false` in `~/.config/herdr/config.toml` (the
  installer offers this), then reopen windows. Option-drag (rectangular selection) works either way.
- herdr's renderer pads every row with spaces, so a normal drag-select copy has full-width lines (extra
  blank lines when pasted into a terminal). Run `herd cleanclip` after ⌘C, or use Option-drag.
- `herd copy <name>` copies a session's whole retained scrollback cleanly.

## Scripting and agents

Sessions are addressable by name through herdr:

```sh
P=$(herd id mr-42)
herdr pane read "$P" --source recent --lines 50   # read output
herdr pane run "$P" 'make test'                   # type a command + Enter
herdr pane send-text "$P" 'partial'               # type without Enter
herdr pane send-keys "$P" ctrl+c                  # send keys
```

## Troubleshooting

- **Nothing happens on click / "not allowed to send keystrokes"**: allow the app under *System Settings →
  Privacy & Security → Automation → Terminal*.
- **Keys go to a session instead of the manager**: the session window has focus (after O or a
  Dock click). Click the manager window.
- **Windows didn't re-fit**: run `herd tile`.
- **Closed window left a stale slot**: `herd tile` prunes ids of windows that no longer exist.
- **herdr errors**: check `herdr status` and that the herdr server is running.

## Contributing

Issues and pull requests are welcome. `bin/herd` is a single stdlib-only Python file. The manager has
headless test hooks (`HERD_TEST_SANDBOX` and friends, documented at the top of `bin/herd`) so you can
drive it in a pty without touching real sessions or windows. Please run `shellcheck` on the scripts
and `python3 -m py_compile bin/herd` before sending changes.

## License

MIT © 2026 Edward Archibald

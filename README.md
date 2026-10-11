# herd-manager

**Named [herdr](https://herdr.dev)-backed Terminal.app sessions with auto-tiling, a session manager and csshx-style live broadcast, for macOS.**

Each session is a persistent herdr terminal with a readable name (`myrepo`, `mr-42` for an issue worktree, `Downloads`) shown in its own
plain Terminal.app window. Windows tile into an even grid; a narrow manager column lists every session.
Because sessions live in the background herdr server, you (or a script or AI agent) can read and type
into any session by name, and closing a window never kills the session.

> Screenshot: _coming soon_ (manager column on the left, session windows in a 3×2 grid).

## Requirements

- macOS with Terminal.app
- [herdr](https://herdr.dev) (0.9.x) with its background server
- python3 (the Xcode Command Line Tools one is fine; stdlib only)

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
| `herd new [name]` | Create a session (default: automatic name, see below); prints name, terminal id, pane id |
| `herd ls` | List sessions: name, terminal id, pane id, cwd, program (agent name or program basename; never the full command line) |
| `herd open <name>` | Open (or focus) a tiled Terminal window attached to the session |
| `herd attach <name>` | What each window runs: attach, then clean up and retile on exit |
| `herd detach <name>` | Close the session's window but keep the session running |
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

### Manager keys

Commands are uppercase on purpose; lowercase letters do nothing except `j`/`k`.

| Key | Action |
|---|---|
| `↑`/`↓`, `j`/`k`, wheel | Move the selection |
| click | Select a session |
| `Enter` / double-click | Open the session, or bring its window to the front |
| `N` / `Shift-Enter` | New session and window (Shift-Enter needs a Terminal key mapping, see below) |
| `X` | Detach: close the window, keep the session |
| `K` | Kill the selected session (no prompt) |
| `A` | Kill **all** sessions (asks y/N) |
| `H` | Hide/show the key reminder |
| `Q` | Quit the manager (sessions keep running) |
| click `>` | Live broadcast: every keystroke goes to all sessions with an open window (drive vi in all of them at once) |
| click the list | Leave live broadcast |

The manager reloads itself when `bin/herd` changes, keeping the selection.

## Session names

Names follow each session's working directory automatically (the manager rechecks every 2 s):

- In a linked git worktree whose branch (or folder) carries an issue number: `<prefix>-<issue>`,
  e.g. `bh-6` for BlackHole issue 6. The prefix is a 2-4 letter abbreviation of the repo name
  (origin remote name, else the main worktree folder); override it in `~/.config/herd/prefixes.json`
  (`{"MyRepo": "mr"}`).
- Otherwise: the cwd folder name (`~` for home). Duplicates get `-2`, `-3`, …
- Manual names (`herd new <name>`, `herd rename`) stick until `herd rename --auto <name>`.

The detail line in the manager (and the CWD column of `herd ls`) shows `<repo>/<branch>` inside git
(main repo folder name, also for worktrees; short hash when detached), else the cwd with `~`.
Commands that take a name also accept a unique prefix; quote names with spaces.

## Shift-Enter

Terminal.app sends a plain Return for Shift-Return by default, so herd can't tell it apart from Enter.
To use Shift-Enter for "new session", add a key mapping in *Terminal → Settings → Profiles → (your
profile) → Keyboard → +*: Key **Return**, Modifier **Shift**, Action **Send Text**, text `\033[13;2u`.
herd also understands `ESC [27;2;13~` and `ESC CR`. `N` always works.

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
- **Keys go to a session instead of the manager**: the session window has focus (after Enter or a
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

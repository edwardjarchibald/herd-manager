# Changelog

## 0.6.28 - 2026-10-16

### Fixed
- The zoomed (blue) outline, the yellow attention outlines, the zoom scrim and the dock overlay showed up on ALL macOS Spaces (e.g. a blue ring floating over an empty desktop on another Space). Root cause: every overlay NSPanel was created with `collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]` (herd-outline.swift, herd-scrim.swift, herd-dock.swift). All three now use `[.managed, .ignoresCycle]` (one Space, no all-Spaces/stationary/moveToActiveSpace).
- Overlays are only ordered in while their target window is on screen on the active Space (single-window CGWindowListCopyWindowInfo by id): outline rings per ring wid, scrim for the zoomed wid, dock for the manager's wid from windows.json. Otherwise they are `orderOut`. herd-outline now also listens to NSWorkspace.activeSpaceDidChange (and wake), with one 0.15 s follow-up, to hide on other Spaces and re-show when the herd Space is active again; the scrim gets the same follow-up. The dock also stops drop detection while the manager's Space is not active. Event-driven, no new timers.

## 0.6.27 - 2026-10-14

### Changed
- Selection never focuses: a single click on a session row or moving the selection with Up/Down (j/k) only zooms (after the 0.4 s / 0.25 s debounce); the manager stays/returns as Terminal's key window (normal raise-manager path, no focus verify/refocus).
- Double click on a session row zooms AND focuses the zoomed terminal (BUTTON1_DOUBLE_CLICKED, or two clicks on the same row within 0.4 s). It cancels the pending single-click zoom; on an already zoomed session it just focuses it.
- N (new), O (open) and Z (zoom on) still zoom + focus. `focus_on_zoom` now applies only to these explicit zooms; `_doc` updated.
## 0.6.26 - 2026-10-14

### Fixed
- focus_on_zoom lost focus to the manager window ~0.35 s after every select-zoom/open (verify always logged `lost focus (front=Terminal/655)`). Root cause: post_zoom called focus_zoomed and THEN outline.follow(force=True), which ran raise_behind_manager -> `set index of window id <manager> to 1`, making the manager Terminal's front/key window again. With focus_on_zoom on, post_zoom now tells the outline not to raise the manager (logged `outline follow <name>: skip manager raise`); the zoomed window keeps key on the first try. _focus_verify stays as a safety net.

## 0.6.25 - 2026-10-14

### Fixed
- focus_on_zoom verify logged `still front=pid695/<wid> MISMATCH` after a successful refocus: it decided "Terminal is frontmost" by comparing the frontmost pid with a separate `pgrep -x Terminal` lookup, which did not match inside the manager even though pid 695 is Terminal. It now reads the frontmost app's bundle id and pid in one sample (com.apple.Terminal = Terminal) and still requires Terminal's front window id to equal the recorded zoomed wid, so the manager window (also a Terminal window) in front still counts as lost focus. Refocus remains at most once per verify.

## 0.6.24 - 2026-10-14

### Fixed
- O on a closed (detached) session opened its window but never zoomed or focused it: the select-zoom for that row had already run (no window then) and nothing re-armed when the window appeared. O now uses the same flow as N: wait for the window in windows.json (kqueue-woken, 15 s give-up), settle 0.5 s, then zoom_to + focus_on_zoom. Open/settle/give-up are logged to focus.log.

### Added
- `zoom_on_open` setting (default true).

## 0.6.23 - 2026-10-14

### Fixed
- Selecting a session (keyboard select-zoom or mouse click) now always ends with its zoomed window focused:
  - Re-selecting an already-zoomed session (or one zoomed via Z/N earlier) used to hit `zoom_to()`'s already-zoomed guard and return before `post_zoom()`, so no focus happened (no focus.log line). It now runs `post_zoom()` with `reason=<reason>-already-zoomed`.
  - Clicking the row that was already selected didn't re-arm the select-zoom (selection unchanged). A click now re-arms it, and the click debounce is 0.4 s so the manager's own click activation settles first.
  - The immediate `front_wid` check could pass and the manager window could still take key back right after. A background verify (0.35 s later) checks that Terminal is frontmost with the zoomed wid in front, refocuses once if not, and logs `focus_on_zoom verify ...`.

## 0.6.22 - 2026-10-14

### Added
- `focus_on_zoom` (config.json, default true): after every zoom, a single post-zoom step (`post_zoom`, used by `zoom_to` and Z) raises the zoomed herd window (recorded wid only) to index 1, activates Terminal and makes that window frontmost, so the session prompt is key and takes keystrokes. Nothing is typed. Order: zoom -> focus -> blue outline; the scrim re-orders below the zoomed window on the resulting app activation.
- Paths: N (`reason=new`, after the 0.5 s settle), select-zoom (`reason=select-debounced`, only after the 250 ms debounce settles, never on intermediate arrow steps), Z when it turns zoom on (`reason=Z`; Z off still keeps the front app and the manager on top).
- focus.log: `focus_on_zoom <session> wid=<wid> reason=<reason> front_wid=<id> OK|MISMATCH`.

### Note
- With focus_on_zoom on, a settled select-zoom moves keyboard focus to the zoomed session; click the manager window (or Cmd-` back to it) to continue list navigation. Set `focus_on_zoom: false` for the old behaviour (manager keeps focus).

## 0.6.21 - 2026-10-14

### Changed
- Event-woken manager loop. herdr events, a kqueue file watch and the scrim helper's app-activation lines write one byte to a self-pipe; the loop `select()`s on stdin + that pipe (list mode and live broadcast alike) and has no timer. A timeout is set only while a deadline is pending: select-zoom debounce (0.25 s), new-session zoom settle (0.5 s) / give-up (15 s), status message expiry (4 s), or a 1 s outline/scrim send that was rate-limited (retried once). Keys are read non-blocking after the wake (getch drain; escape sequences unchanged). Terminal resize wakes via SIGWINCH.
- `pane.agent_status_changed` events patch the cached rows in place (agent status, cmd label, attention key from the event's `state_change_seq`, else a local counter bumped on each new done/blocked). A full `sessions()` snapshot (herdr workspace/pane list, api snapshot, auto names) runs only on structural events (pane/workspace/layout), on (re)connect, after local actions, or for an event from a pane not in the rows. The 1.5 s chime quiet window after (re)subscribe is unchanged.
- The screen is redrawn only when the built frame differs from the last one (no erase every 250 ms). manager-state.json is written on redraw instead of every 2 s.
- Self-reload, layout.json and windows.json: kqueue VNODE watch (re-armed when git/editors/os.replace swap the file; content-hash filtered, since `_locked()` rewrites windows.json unchanged) instead of the 2 s self-stat and per-call layout.json stat. windows.json changes by other herd processes update the window dots and let the N zoom find the new window without polling.
- herd-scrim prints `activated <pid>` on each NSWorkspace app activation; the manager's front-app stack tracking, "clicked back into Terminal" (F behind) check and stale-H check run on that line instead of a 1 s osascript poll (old polling only if the helper is unavailable).

### Added
- focus.log: `status applied <hh:mm:ss.ms> <session> <pane>: old -> new att=... (+N ms)` per event-applied status change and `redraw <time> event->refresh N ms` per event-triggered redraw.

## 0.6.20 - 2026-10-14

### Changed
- Zoom scrim is event-driven. The manager now passes the zoomed window's known CGWindowID (windows.json), the pid of its `herdr terminal attach` client, and herd's computed frames. herd-scrim orders itself below that window id only on events: manager commands (zoom/selection/layout change; a new `order` command re-orders when frames are unchanged), NSWorkspace app activation (plus one 0.15 s follow-up, since Terminal raises its windows after posting it), active-Space change, wake, and screen-parameter changes. The 0.5 s timer, the rect-matching window-list search (±4-6 px) and the 0.6.19 4-miss grace are gone.
- Zoomed window closed: closing the Terminal window kills its attach client; the helper watches that pid (DispatchSource process exit) and hides the scrim at once. On every event it also checks that one window id is on screen (minimized/other Space/closed → hide until the next event).
- Helper protocol: `<alpha> <radius> <wid> <attach pid|0> <zoom l t r b> [<tile l t r b>]...`, `order`, or `hide`.

### Removed
- The manager's 1 s background focus watcher (an `osascript` every second for Terminal's front window id). Its only consumer was the attention acknowledgement map, unused since 0.6.12.
- herd-outline's old tracking mode (no `--static`: a 0.5 s CGWindowList rect search). herd has used only `--static` since 0.6.11.

## 0.6.19 - 2026-10-14

### Fixed
- Zoom scrim flicker: the scrim helper re-finds the zoomed Terminal window every 0.5 s (and on every app activation) by matching herd's zoom rect in the window list, and hid the scrim on the FIRST failed lookup; the next tick showed it again, so any transient miss (window-list churn during animations/app switches/Spaces, a few px of drift) made the scrim blink off and on. It now keeps ordering below the last known zoomed window while that window is still on screen and only hides after 4 consecutive misses (~2 s); the remembered window resets when the zoom rect changes.

### Added
- Scrim visibility logging in `~/.cache/herd/outline.log`: manager-side `[scrim] hide/show (reason)` and helper-side `scrim[pid] hide/show ...` lines, so any remaining flicker can be pinned down.

## 0.6.18 - 2026-10-13

### Added
- Blocked chime: one soft, quiet chime when a session transitions INTO herdr's `blocked` state (not done/idle/working). One chime per transition; no repeats while it stays blocked. Sessions already blocked at manager start, reload, or event reconnect/resync stay silent (1.5 s quiet baseline after each (re)subscribe). Blocks within ~1 s share one chime. Played asynchronously via `afplay -v <volume>` (reaped on a daemon thread), so the UI never waits and the system volume is never touched.
- Custom sound `assets/chime.wav`, rendered by `assets/chime.py` (pure stdlib): a two-note glass bell, E6 then B6 (rising fifth), additive sine partials with slightly inharmonic overtones, 6 ms soft attack, ~2 s exponential decay, stereo detune shimmer and a light diffuse tail, click-free fade, peak -18 dBFS.
- New config keys: `chime_on_blocked` (true), `chime_sound` (repo `assets/chime.wav`), `chime_volume` (0.15).

## 0.6.17 - 2026-10-13

### Added
- N selects the new session and zooms its window automatically, once the window exists and has settled (0.5 s), with the same zoom as `zoom_on_select` (one zoomed window, zoom before outline, blue outline, scrim). New config key `zoom_on_new` (default true); with it off, N still selects the new session.

## 0.6.16 - 2026-10-12

### Changed
- Zoom scrim hugs the terminals. Instead of one square rect over the whole terminal area (which covered the gap next to the manager/dock panel), herd-scrim now draws the union of rounded rects, one per tiled non-zoomed terminal, from herd's computed `frames` in layout.json. The panel gap and the gaps between tiles stay clear, so each terminal reads as dimmed. The zoomed window still sits above the scrim.
- New config key `scrim_radius` (env `HERD_SCRIM_RADIUS`), default matches the Terminal window corners: 16 on macOS 26 (Tahoe), 10 before.
- The scrim's per-second `osascript` bounds lookup of the zoomed window is gone. The zoomed window is matched by its computed zoom rect. The helper gets a new line (and redraws) only when the layout changes; between those it only re-orders itself below the zoomed window.
- Helper protocol: `<alpha> <radius> <zoom l t r b> [<tile l t r b>]...` or `hide`.

## 0.6.15 - 2026-10-12

### Changed
- Manager rows: drop the teal done highlight. done rows use the default look again (same as idle). **working** rows get a full-width dark-on-orange highlight instead (new key `working_color_256`, default 208 = #ff8700; clearly distinct from the blocked yellow ~220). Selected beats orange (blue); blocked still beats everything. Window outlines are unchanged: yellow for blocked, blue for selected/zoomed, none for working/done/idle unless they are the blue target.
- Config key `done_color_256` is replaced by `working_color_256`. `attention_highlight` remains the master switch: off = no yellow and no orange, only the blue selection/zoom outline. Config `_doc` texts updated.

## 0.6.14 - 2026-10-12

### Changed
- New colour scheme. Window outlines come in only two kinds: yellow (`attention_outline_rgb`, 255 200 0) for sessions herdr reports **blocked**, and blue (0 95 175) for the selected window (or the zoomed window, shown after zoom as before). Blocked overrides blue, so a blocked selected or zoomed window is yellow. The zoomed window always has exactly one outline, blue or yellow. done, working and idle windows get no outline unless they are the blue target. The yellow outline for **done** is gone.
- Manager rows: blocked = full-width dark-on-yellow highlight, dot included (wins over the selection). Selected = blue. done = full-width dark-on-teal highlight (new key `done_color_256`, default 37 = #00afaf); the selected row wins over teal. Idle and working rows are unchanged.
- `attention_highlight` stays the master switch: off = no yellow and no teal, only the blue selection/zoom outline.
- New `blocked_names()` helper; `desired_outlines()` uses it, and `attention_outline_targets()` now delegates to it. Config `_doc` texts updated.

## 0.6.13 - 2026-10-12

### Changed
- herdr state is pushed to the manager instead of polled. The 2 s `workspace list` / `pane list` / `api snapshot` poll is gone. A background thread holds an `events.subscribe` on herdr's API socket covering `pane.created/closed/exited/updated/agent_detected`, `workspace.created/closed/updated/renamed`, `layout.updated`, and `pane.agent_status_changed` (one per pane, since herdr requires a `pane_id` for that one). Each event wakes the UI loop for one refresh. Pane create/close/exit re-subscribes. A drop reconnects with backoff (1 s doubling to 30 s) and then resyncs once. It never falls back to polling. Log lines: `herdr events: subscribed|down|re-subscribing`, `herdr event: <pane> -> <status>`.
- The auto-reload check (a stat of bin/herd) still runs every 2 s.

## 0.6.12 - 2026-10-12

### Fixed
- The zoomed window's outline (blue or yellow) kept vanishing and coming back. Root cause: not the manager. outline.log shows no hide/show sent at those moments, no self-check lines, and the helper pids (31551/31552) never changed. A CGWindowList watch (window order sampled every 250 ms) showed Terminal window 1618 rising above the ring while Terminal stayed frontmost, with no manager send. At 19:01:09.333 the blue ring was covered until 19:01:26.017, and at 19:02:38.856 the yellow ring was covered until 19:02:48.594. The `--static` helper kept its rings at `.normal` level, ordered above the window id, and re-ordered them only on a new line or on `didActivateApplication`. Clicking or raising a window inside Terminal is not an app switch, so Terminal put the window above the ring and nothing put the ring back.

- ee-1207 stayed latched yellow after Edward had answered it. focus.log: `19:02:28 attention CLEAR ee-1207 (window focused)`, then `19:02:31 attention SET ee-1207 (done:316)` re-latched it while its window was already in front. The latch clears only when the Terminal front window *changes*, and typing into or clicking a window that is already in front is not a change, so nothing could clear it.
- The attention latch is gone. Yellow (row and outline) now follows herdr's current state: it shows while herdr reports the agent as done or blocked and goes away when the agent is working again. Selecting a row or clicking a window no longer acknowledges or clears it.
- The self-check now strips the new `+` prefix before comparing wids.

### Changed
- The manager marks the zoomed window's entry with a `+` prefix on the wid (blue and yellow helpers). While Terminal is frontmost, the static helper keeps that ring at floating level, so a raise inside Terminal can't cover it. When another app is frontmost, it drops back to normal level directly above the window, so other apps' windows still cover it. Tile rings are unchanged. Nothing is polled. The level is checked again 0.3 s after each update, because `frontmostApplication` is stale in a freshly started helper. (Right after the 19:04:14 reload the ring was still at layer 0 with Terminal frontmost. It reached layer 3 after the next event.)

## 0.6.11 - 2026-10-12

### Fixed
- A zoomed window could lose its outline entirely. Root cause (outline.log, 18:32:54-18:33:13): the blue helper ran in tracking mode and hid itself after 3 CGWindowList bounds misses (the live window bounds no longer matched herd's computed zoom rect within 4-6 px). The manager never learned about it, and its de-duplication (same line as last time) never re-sent the frame, so the window stayed without an outline until the next state change (here the next latch, which sent yellow). Yellow/blue hand-off on a window click itself worked (18:34:21, 18:42:30, 18:50:14).

### Changed
- The blue outline helper now also runs in `--static` mode: it is drawn at herd's computed frame above the session's window id and does no lookups, so it can no longer hide itself. (It no longer self-hides on another Space or when minimized.)
- One function, `desired_outlines()`, computes both outlines from current state on every pass. Blue goes on the zoomed window when one is zoomed, even when it is not the selected session; otherwise it goes on the selected session. A latched zoomed window gets yellow instead of blue, and yellow never duplicates the blue target.
- Self-check every pass, using in-memory state only: if a window is zoomed and herd is not behind/hidden, exactly one helper must be showing it. Otherwise both helpers are resynced (logged as `self-check` in outline.log, at most every 2 s).

## 0.6.10 - 2026-10-12

### Changed
- A zoomed window that needs attention gets the yellow outline too: when the zoomed window's session is latched (`att_on`), including when it is the selected session, the yellow attention outline is drawn at its zoom rect instead of the blue one. When the latch clears, the outline goes back to blue.
- Attention clearing is now event-based instead of "selected means clear". The latch clears when you select the session (move the selection onto it, or click its row, also when it is already selected) or click its window to the front. Attention that starts while a session is already selected or zoomed now latches and stays until one of those actions.
- Manager rows: a latched row shows yellow even when it is selected (same as 0.6.7).

## 0.6.9 - 2026-10-12

### Changed
- Outlines no longer track window positions. herd places every window itself, so `tile()` now records the frame it computed for each session (tile rect, or zoom rect when zoomed) in `~/.config/herd/layout.json` (`frames`), and the outlines are drawn at those frames.
- Yellow attention outlines: one `herd-outline` helper in a new `--static` mode draws all of them (one click-through panel per rect, each ordered above its window). It does no polling. The manager sends a new line only when the target set or a computed frame changes (retile, zoom/unzoom, new/killed sessions, H/F, dock changes, latch set/clear). This removes the per-window helpers and their ~1/s `osascript` bounds lookups (~100 ms each) on the manager's UI thread. Panels are re-ordered above their windows on each update and when the frontmost app changes.
- Blue selected outline: the manager sends the computed frame (tile or zoom rect) instead of reading the window's bounds with `osascript` once a second. It falls back to the live bounds only for a window without a computed frame (e.g. on another display). The blue helper keeps its own in-process visibility check (hides on another Space/minimized), unchanged.
- On the first manager start after the upgrade, if `layout.json` has no `frames`, the manager runs one idempotent retile to record them.
- Scrim, colours and window handling are unchanged. Only herd-recorded windows are touched.

## 0.6.8 - 2026-10-12

### Added
- Attention outlines: every herd session window in the latched attention state (the same latch, gated by `attention_highlight`, that makes its manager row yellow) gets a yellow outline with the same thickness and radius as the blue one. It is drawn whether or not anything is zoomed. The selected session never gets one; it keeps the blue outline, which still appears only after zoom.
- Each attention outline is its own `herd-outline` helper instance started with the colour `attention_outline_rgb` (new config key, default `255 200 0`). It follows its window's live bounds about once a second and reuses the existing 3-miss tolerance on both the manager and helper sides. It is stopped when the latch clears (select or click), and all are hidden while H hides the windows or F sends herd behind.
- Under the zoom scrim: while a zoomed window has the scrim up (`zoom_dim` > 0), attention outlines of the windows the scrim covers are hidden. Their manager rows stay yellow. With `zoom_dim` 0 they stay visible. The Swift helpers are unchanged. Only herd-recorded windows are targeted, and no window is moved or raised.
- Attention-outline commands are logged to `~/.cache/herd/outline.log` with an `[att:<session>]` tag.

## 0.6.7 - 2026-10-12

### Changed
- A session needing attention now has its **entire row** (dot, name, cwd, padding to full width) drawn dark-on-yellow, including when it is the selected row. `attention_highlight` / `attention_flash` unchanged.

## 0.6.6 - 2026-10-12

### Changed
- No more flashing. A session needing attention (agent done or blocked) shows its **name** with a steady yellow background and dark text; the dot keeps its normal look. The latch/clear logic is unchanged.
- Config key renamed to `attention_highlight` (default true); the old `attention_flash` is still accepted as an alias.

## 0.6.5 - 2026-10-12

### Fixed
- The attention flash was irregular. It was computed per frame from the current status, so it stopped whenever the agent left done/blocked (e.g. working again) and restarted on the next event. It was also cleared whenever Terminal's front window was the session's. Its phase stalled while the UI thread waited on a System Events/osascript frontmost query (100+ ms, every second).
- Attention is now latched: it is set on a new done/blocked event and kept through status flips. It is cleared only by selecting the session or by its window *becoming* Terminal's front window while Terminal is frontmost (a click). The focus check runs in a background thread. The phase is wall-clock (0.5 s on / 0.5 s off). The dot and the name flash together as a yellow block.
- Attention SET/CLEAR events (with reasons) are logged to `~/.cache/herd/focus.log`.

## 0.6.4 - 2026-10-12

### Added
- Attention flash (`attention_flash`, default true): a session's dot flashes yellow at about 1 Hz when its agent is `done` (finished) or `blocked` (waiting for input or approval). The signal is herdr's agent lifecycle: `agent_status` from `herdr pane list`, plus `state_change_seq` from `herdr api snapshot`, so each new done/blocked event counts once. It stops once you select the session or its Terminal window is frontmost, until the next event. Plain shells (no agent) never flash. The selected row uses yellow on the slate-blue selection.
- The terminal bell is not covered: herdr does not expose a bell flag, and Terminal's AppleScript has none either.

## 0.6.3 - 2026-10-12

### Changed
- No fixed terminal cap. Capacity = the session rows the manager shows at `manager_font_min` (rows minus divider and broadcast line), measured on retile and stored in `~/.config/herd/layout.json`; 30 on a 2560x1440 display. `max_terminals` in config.json overrides it (0/null = automatic). N (and `herd new`) refuses beyond it with a status message.
- Dock-mode tiling for 7+ terminals: 3 rows, adding columns while cells stay at least `min_cell_width` (default 360 px) wide; after that, rows are added instead. The cells of a partly filled last column share its height.

### Fixed
- Outline flicker. herd-outline found the target window in CGWindowList by its bounds, and on a single miss it hid the outline and showed it again on the next refresh. Misses happen transiently, e.g. while Terminal retiles or re-registers a window. The helper now keeps the outline on the last good window for up to 3 consecutive misses (about 1.5 s) and only re-sets its frame when it changes. On the manager side, a failed AppleScript bounds lookup no longer sends "hide" unless it fails 3 times in a row.
- Every outline command (manager) and helper lookup state change is logged with millisecond timestamps to `~/.cache/herd/outline.log`.

## 0.6.2 - 2026-10-12

### Changed
- Zoom on select no longer flashes the outline at the tiled position first. On a selection change that will zoom, the outline is hidden, the window is zoomed, and the outline is shown at the zoomed frame. With `zoom_on_select` off, no window, already zoomed, or unzoomed with Z, the outline behaves as before.

## 0.6.1 - 2026-10-12

### Added
- Zoom on select (`zoom_on_select`, default true): selecting a session with a window, by click or arrow keys after a 250 ms debounce, zooms its window and unzooms the previous one. Z toggles the zoom for the selected session, and an unzoom with Z holds until the selection changes. A session without a window changes nothing. Terminal is never activated, and the scrim and outline follow.

## 0.6.0 - 2026-10-12

### Added
- Every tunable can now be set in `~/.config/herd/config.json`: `dock`, `dock_min_width`, `dock_panel_fraction`, `zoom_dim`, `zoom_scale`, `gap`, `manager_width`, `manager_font_max`, `manager_font_min`, `selection_color_256`, `outline`, `outline_rgb`, `outline_px`, `outline_radius`. Env vars (`HERD_ZOOM_DIM`, `HERD_OUTLINE_*`, `HERD_NO_OUTLINE`) still override. The file lists all keys plus a `_doc` object with one-line descriptions. README has a Configuration table.

## 0.5.9 - 2026-10-12

### Added
- Zoom scrim: while a session is zoomed, a dark overlay covers the terminal area. It is ordered directly below the zoomed Terminal window, so it sits above the other herd terminals and under the zoomed window and its outline. It is click-through, never takes focus, and doesn't cover the manager or the dock.
  - New helper `helper/herd-scrim.swift`, compiled into `~/.cache/herd/herd-scrim`.
  - Opacity: `zoom_dim` in `~/.config/herd/config.json` (default 0.85, 0 disables), overridden by `HERD_ZOOM_DIM`.
  - It is removed on unzoom, H hide, F behind and quit.
  - `herd tile` writes the terminal area to `~/.config/herd/layout.json`.

## 0.5.8 - 2026-10-12

### Fixed
- Outline robustness:
  - The helper is restarted if it died.
  - A stale "behind" flag (from F) is cleared as soon as any key reaches the manager, not only when the once-a-second frontmost check sees Terminal.
  - A stale H-hidden flag is cleared when the session windows are visible again.
  - The outline keeps following the selected window's live frame, so manual moves are followed.
- The manager writes its outline/selection state to `~/.cache/herd/manager-state.json` every 2 s for diagnosis.
- The 0.5.7 changelog date is corrected.

## 0.5.7 - 2026-10-12

### Changed
- `?` alone toggles the help overlay (Esc closes it).
- `H` is now "toggle hide": it hides every herd session window (not the manager, never other windows or the docked app) by setting Terminal's `visible` to false, so you can see what is underneath. Sessions keep running and stay attached, and nothing goes to the Dock. Pressing H again shows them and retiles them, keeping the zoom state.
- The outline hides while the windows are hidden. O, N and Z unhide first, then act.
- Hints: `(H) toggle hide`, `(?) help`.

## 0.5.6 - 2026-10-11

### Changed
- Selection colour is now white on slate blue: xterm-256 colour 25, #005faf (COLOR_BLUE on 8-colour terminals). It replaces black on cyan, which made the green attached dot look black. The dot on the selected row is drawn with its own pair (green on the selection background), so it stays green.
- The selected-window outline uses the same colour (#005faf) and is a third thinner: 6 px instead of 9 px (`HERD_OUTLINE_RGB` / `HERD_OUTLINE_PX` still override).

## 0.5.5 - 2026-10-11

### Changed
- `X` removed. `O` toggles open/detach: a session without a window is opened (non-activating, as before); a session with a window is detached (the session keeps running) and its window is closed. The hint reads `(O) open/detach`.
- The live broadcast line no longer echoes typed text: just a bright `> ` and the yellow `(click list to end)`.

### Fixed
- Detach showed Terminal's "terminate running processes… herdr" dialog. The client lookup used `pgrep -f "herdr terminal attach <id>$"`, but windows attach with `--takeover` appended, so nothing matched, the client kept running and closing the window prompted. Detach now matches with or without trailing args, waits until the tab is no longer busy, and only then closes the window. If it stays busy, the window is left open (session kept).

## 0.5.4 - 2026-10-11

### Fixed
- A session that cd'd into `~/git/worktrees/elephant_ears_V1/elephant_ears_V1-issue-1148` stayed `dev-1`. Auto-naming does re-run on every manager poll, but it only recognized issue worktrees through git, and that folder is not a git worktree: git does not list it, and it only contains an `elephant-ears-website` subfolder. Naming now uses the realpath of the cwd (so `~/git` -> `~/Development/git` symlinks don't matter). Outside git, a path matching `.../worktrees/<repo>/…issue-<N>` names the session `<prefix>-<N>`. Only auto-named sessions are renamed, never manual names.

## 0.5.3 - 2026-10-11

### Added
- `herd new [DIR] [-C DIR]` starts the session in DIR. `~` is expanded and relative paths resolve against the current directory; a missing DIR is a clear error. It is auto-named right away (ee-<issue> in a worktree, otherwise dev-N). A bare word that isn't a path or existing directory is still a manual NAME, as before.

## 0.5.2 - 2026-10-11

### Changed
- New dock-mode terminal tiling order:
  - 1 = full area; 2 = two full-height columns; 3 = 2 cells on top, 1 full-width cell below; 4 = 2x2.
  - 5 = 3 rows (2, 2, 1 full width); 6 = 3x2.
  - 7+: 3 rows, with columns added one at a time and filled top to bottom. The cells of a partly filled last column share its full height (7: one full-height cell, 8: two halves). 10+ uses 4 columns, and so on.
- Dock-off tiling is unchanged.

## 0.5.1 - 2026-10-11

### Changed
- The dock-mode left panel (manager and dock) is now max(30% of the tiled width, `dock_min_width`), so a docked Grok Bot keeps its width and bot names stay visible. `dock_min_width` lives in `~/.config/herd/config.json` and defaults to 920 (Grok Bot's window measured 916 px). Terminals take the rest.

## 0.5.0 - 2026-10-11

### Changed
- New dock-on layout, replacing the 5x3 grid:
  - The left panel is 30% of the tiled width. The manager sits on top at exactly one row of a 3-row grid, so its bottom lines up with terminal row 1. The dock is the rest of the panel below it.
  - Terminals tile adaptively in the area to the right: 1 = full; 2 = 2 columns; 3 = 3 full-height columns; 4 = 2x2; 5-6 = 3x2; 7-9 = 3x3; more than 9 = 4 columns x ceil(n/4) rows.
  - In partial grids the last columns get one cell fewer and those cells span the column height: with 5 the last column is full height, with 7 the last two columns are halves, with 8 the last column is halves.
- Z zooms to 80% of the terminal area, centered.
- The manager shows one line per session: the full name, then the dim folder/repo subtitle, truncated.
- The forced font 13 is gone. On retile, the manager window gets the largest Monaco size up to 16 that fits every session plus the divider and broadcast line (manager window only).

## 0.4.3 - 2026-10-11

### Changed
- Manager UI:
  - No header line and no permanent hints area.
  - The hints are a centered overlay box over the list, toggled with `?` or `H`; Esc also closes it. `?` is the one non-uppercase command key. The overlay starts hidden.
  - At the bottom: a divider, then a single line. That line is the dim `> click for broadcast` when off. When live it shows a bright `> ` plus the typed echo and a yellow `(click list to end)` at the right end. Transient status messages (F, O, K, ...) show in that line for about 4 s.
- In dock mode the tiler sets the manager window's own font size to 13 (`MGR_FONT`, overridable with `HERD_MGR_FONT`). In its 502x442 cell that gives 23 rows x 60 cols, so all 10 sessions (20 rows) plus the divider and broadcast line fit without scrolling. Other Terminal windows and the profile are untouched.

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

// herd-scrim: dark, click-through, non-activating scrim for zoom. Drawn as the union of rounded rects,
// one per tiled (non-zoomed) herd terminal, using herd's computed frames from layout.json, so the gap
// to the manager/dock panel and the gaps between tiles stay clear and each terminal reads as dimmed.
// Ordered DIRECTLY BELOW the zoomed Terminal window, whose CGWindowID herd already knows (windows.json),
// so it sits above the other herd terminals but under the zoomed one.
// 0.6.20: fully event-driven, no timer and no window-list search. It re-orders itself only on:
//   - a command from the manager (zoom / selection / layout change; "order" = re-order only)
//   - NSWorkspace app activation (+ one 0.15 s follow-up, Terminal raises its windows after posting it), active-Space change, wake; NSApplication screen-parameter change
//   - exit of the zoomed window's `herdr terminal attach` client (DispatchSource process watch): closing
//     the Terminal window kills that client, so the scrim hides at once.
// On each of those it asks the window server about that ONE window id; if it is not on screen
// (minimized, other Space, closed) the scrim hides until the next event.
// Started by the herd manager; exits when stdin closes.
// stdin, one command per line (top-left coordinates of the main screen):
//   "<alpha> <radius> <wid> <attach pid|0> <zl> <zt> <zr> <zb> [<l> <t> <r> <b>]..."   dim the tile rects below window <wid>
//   "order"   re-order below the current window (it may have been raised)
//   "hide"
import AppKit

final class V: NSView {
    var alpha: CGFloat = 0.85, radius: CGFloat = 16
    var rects: [NSRect] = []          // view coordinates
    override func draw(_ r: NSRect) {
        NSColor.clear.set(); bounds.fill()
        NSColor.black.withAlphaComponent(alpha).setFill()
        let p = NSBezierPath()
        for t in rects { p.append(NSBezierPath(roundedRect: t, xRadius: radius, yRadius: radius)) }
        p.fill()
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
panel.ignoresMouseEvents = true; panel.level = .normal
panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
let view = V(); panel.contentView = view
var wid: CGWindowID = 0, shown = false, closed = false
var lastParams: [Double] = []
var procWatch: DispatchSourceProcess? = nil, watchedPid: pid_t = 0

let logPath = (NSHomeDirectory() as NSString).appendingPathComponent(".cache/herd/outline.log")
func slog(_ m: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
    let line = "\(f.string(from: Date())) scrim[\(getpid())] \(m)\n"
    if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
}
func onScreen(_ w: CGWindowID) -> Bool {      // one window, by id: no list search, no rect matching
    guard w != 0, let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], w) as? [[String: Any]], let i = info.first else { return false }
    return (i[kCGWindowIsOnscreen as String] as? Bool) ?? false
}
func setShown(_ v: Bool, _ why: String) { if v != shown { shown = v; slog((v ? "show " : "hide ") + why) } }
func hide(_ why: String) { panel.orderOut(nil); setShown(false, why) }
func reorder(_ why: String) {
    guard wid != 0 else { hide("inactive (\(why))"); return }
    if closed { hide("zoomed window \(wid) closed"); return }
    guard onScreen(wid) else { hide("zoomed window \(wid) not on screen (\(why))"); return }
    panel.order(.below, relativeTo: Int(wid)); setShown(true, "below \(wid) (\(why))")
}
func watch(_ pid: pid_t) {
    if pid == watchedPid { return }
    procWatch?.cancel(); procWatch = nil; watchedPid = pid
    guard pid > 0 else { return }
    if kill(pid, 0) != 0 { closed = true; return }
    let s = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
    s.setEventHandler { closed = true; slog("attach client \(pid) exited"); reorder("window closed") }
    s.resume(); procWatch = s
}
func apply(_ line: String) {
    if line == "order" { reorder("order"); return }
    let p = line.split(separator: " ").compactMap { Double($0) }
    guard p.count >= 12, (p.count - 8) % 4 == 0, let main = NSScreen.screens.first else {
        wid = 0; lastParams = []; watch(0); closed = false; view.rects = []; reorder("hide"); return
    }
    let nw = CGWindowID(p[2])
    if nw != wid { closed = false }
    wid = nw; watch(pid_t(p[3])); lastParams = p
    var tiles: [CGRect] = []
    var i = 8
    while i + 3 < p.count { tiles.append(CGRect(x: p[i], y: p[i+1], width: p[i+2] - p[i], height: p[i+3] - p[i+1])); i += 4 }
    let u = tiles.dropFirst().reduce(tiles[0]) { $0.union($1) }
    let H = main.frame.height
    panel.setFrame(NSRect(x: u.minX, y: H - u.maxY, width: u.width, height: u.height), display: false)
    view.alpha = CGFloat(p[0]); view.radius = CGFloat(p[1])
    view.rects = tiles.map { NSRect(x: $0.minX - u.minX, y: u.maxY - $0.maxY, width: $0.width, height: $0.height) }
    view.needsDisplay = true
    reorder("layout")
}
DispatchQueue.global().async {
    while let line = readLine() {
        let l = line.trimmingCharacters(in: .whitespaces)
        DispatchQueue.main.async { apply(l) }
    }
    DispatchQueue.main.async { exit(0) }
}
let wnc = NSWorkspace.shared.notificationCenter
// stdout to the manager (0.6.21): one `activated <pid>` line per app activation, so the manager's front-app /
// behind / hidden checks run on this event instead of a 1 s osascript poll.
signal(SIGPIPE, SIG_IGN)
func emit(_ s: String) { if let d = (s + "\n").data(using: .utf8) { _ = d.withUnsafeBytes { write(1, $0.baseAddress, d.count) } } }
wnc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
    if let a = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { emit("activated \(a.processIdentifier)") }
    // Terminal raises its windows just AFTER posting activation: one follow-up re-order (one-shot, not a timer)
    reorder("app activated"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { reorder("app activated +0.15s") }
}
wnc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in reorder("space changed") }
wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in reorder("wake") }
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
    if !lastParams.isEmpty { apply(lastParams.map { String($0) }.joined(separator: " ")) } else { reorder("screens changed") }
}
app.run()

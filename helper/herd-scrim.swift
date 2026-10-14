// herd-scrim: dark, click-through, non-activating scrim for zoom. Drawn as the union of rounded rects,
// one per tiled (non-zoomed) herd terminal, using herd's computed frames from layout.json, so the gap
// to the manager/dock panel and the gaps between tiles stay clear and each terminal reads as dimmed.
// Ordered DIRECTLY BELOW the zoomed Terminal window (found by its herd-computed zoom rect in
// CGWindowList, no osascript), so it sits above the other herd terminals but under the zoomed one.
// Started by the herd manager; exits when stdin closes.
// stdin, one command per line (top-left coordinates of the main screen):
//   "<alpha> <radius> <zl> <zt> <zr> <zb> [<l> <t> <r> <b>]..."   dim the given tile rects below the window at z*
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
var active = false, zoomed = CGRect.zero

func terminalWindowID(_ r: CGRect) -> CGWindowID? {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").map { $0.processIdentifier })
    for w in info {
        guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid), (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat], let num = w[kCGWindowNumber as String] as? CGWindowID else { continue }
        let wr = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        if abs(wr.minX - r.minX) <= 4 && abs(wr.minY - r.minY) <= 4 && abs(wr.width - r.width) <= 6 && abs(wr.height - r.height) <= 6 { return num }
    }
    return nil
}
// Re-order only (cheap CGWindowList read); the scrim is redrawn only when herd sends a new layout.
// 0.6.19: a single failed lookup (window list mid-animation, Space/Mission Control, app activation, a few px
// of drift) used to orderOut the panel and the next 0.5 s tick put it back = visible flicker. Now we keep the
// last known zoomed window id while it still exists, and only hide after several consecutive misses.
var lastWid: CGWindowID? = nil, misses = 0, shown = false
let logPath = (NSHomeDirectory() as NSString).appendingPathComponent(".cache/herd/outline.log")
func slog(_ m: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
    let line = "\(f.string(from: Date())) scrim[\(getpid())] \(m)\n"
    if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
}
func windowExists(_ wid: CGWindowID) -> Bool {
    guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]], let w = info.first else { return false }
    return (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
}
func setShown(_ v: Bool, _ why: String) { if v != shown { shown = v; slog((v ? "show " : "hide ") + why) } }
func reorder() {
    guard active else { lastWid = nil; misses = 0; panel.orderOut(nil); setShown(false, "inactive"); return }
    if let wid = terminalWindowID(zoomed) {
        lastWid = wid; misses = 0
        panel.order(.below, relativeTo: Int(wid)); setShown(true, "below \(wid)"); return
    }
    misses += 1
    if let wid = lastWid, windowExists(wid) { panel.order(.below, relativeTo: Int(wid)); return }   // keep, don't flicker
    if misses >= 4 { panel.orderOut(nil); setShown(false, "zoomed window not found (\(misses) misses)") }
}
func apply(_ p: [Double]) {
    guard p.count >= 10, (p.count - 6) % 4 == 0, let main = NSScreen.screens.first else { active = false; view.rects = []; reorder(); return }
    let nz = CGRect(x: p[2], y: p[3], width: p[4] - p[2], height: p[5] - p[3])
    if nz != zoomed { lastWid = nil; misses = 0 }
    zoomed = CGRect(x: p[2], y: p[3], width: p[4] - p[2], height: p[5] - p[3])
    var tiles: [CGRect] = []
    var i = 6
    while i + 3 < p.count { tiles.append(CGRect(x: p[i], y: p[i+1], width: p[i+2] - p[i], height: p[i+3] - p[i+1])); i += 4 }
    let u = tiles.dropFirst().reduce(tiles[0]) { $0.union($1) }
    let H = main.frame.height
    panel.setFrame(NSRect(x: u.minX, y: H - u.maxY, width: u.width, height: u.height), display: false)
    view.alpha = CGFloat(p[0]); view.radius = CGFloat(p[1])
    view.rects = tiles.map { NSRect(x: $0.minX - u.minX, y: u.maxY - $0.maxY, width: $0.width, height: $0.height) }
    view.needsDisplay = true; active = true
    reorder()
}
DispatchQueue.global().async {
    while let line = readLine() {
        let p = line.split(separator: " ").compactMap { Double($0) }
        DispatchQueue.main.async { apply(p) }
    }
    DispatchQueue.main.async { exit(0) }
}
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in reorder() }
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
    reorder(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { reorder() }
}
app.run()

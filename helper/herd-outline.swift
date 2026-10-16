// herd-outline: draws a green, click-through, non-activating border around one rectangle.
// Protocol on stdin, one command per line (Terminal-style top-left coordinates of the main screen).
// Static mode (the only mode since 0.6.20) (herd-outline --static [border_px] [radius] [r g b]): draws any number of rings at the given
// rects, no window tracking or polling. One line per update, replacing everything drawn:
//   "<wid> <left> <top> <right> <bottom>|<wid> ...|..."   (wid = CGWindowID of the window to sit above)
//   "hide"                                                 remove all rings
// A wid prefixed with "+" (the zoomed window) is "topmost": while Terminal is the frontmost app its ring sits at
// floating level, because clicking/raising a window inside Terminal posts no app-activation event and would
// otherwise cover a normal-level ring ordered above it (0.6.12). Other rings, and all rings while another app is
// frontmost, stay at normal level ordered directly above their window. Re-checked on a new line or app switch.
// Exits when stdin closes (the herd manager quit). Needs no Accessibility permission.
import AppKit

// Usage: herd-outline [border_px] [window_corner_radius] [r g b (0-255)]
let args = CommandLine.arguments.dropFirst().compactMap { Double($0) }
let border = CGFloat(args.count > 0 ? args[0] : 9)
let radius: CGFloat = {   // macOS window corner radius: ~16pt on macOS 26, ~10pt before
    if args.count > 1 { return CGFloat(args[1]) }
    return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 16 : 10
}()
let color = args.count > 4 ? NSColor(srgbRed: args[2] / 255, green: args[3] / 255, blue: args[4] / 255, alpha: 1)
                           : NSColor(srgbRed: 51 / 255, green: 187 / 255, blue: 200 / 255, alpha: 1)

final class BorderView: NSView {
    // A filled ring that hugs the window: inner edge = the window's rounded rect (radius R),
    // outer edge = R + border, so the corners stay concentric.
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        let ring = NSBezierPath(roundedRect: bounds, xRadius: radius + border, yRadius: radius + border)
        ring.append(NSBezierPath(roundedRect: bounds.insetBy(dx: border, dy: border), xRadius: radius, yRadius: radius))
        ring.windingRule = .evenOdd
        ring.fill()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if CommandLine.arguments.contains("--static") {
    var panels: [NSPanel] = []
    var wids: [Int] = []
    var tops: [Bool] = []
    func terminalFront() -> Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal" }
    func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
        p.level = .normal; p.collectionBehavior = [.managed, .ignoresCycle]   // 0.6.28: ONE Space (never .canJoinAllSpaces/.stationary/.transient); shown only while its target window is on the active Space
        p.contentView = BorderView()
        return p
    }
    // 0.6.28: one window, by id: is it on screen = on the ACTIVE Space (and not minimized/closed)?
    func onScreen(_ w: Int) -> Bool {
        guard w > 0, let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(w)) as? [[String: Any]], let i = info.first else { return false }
        return (i[kCGWindowIsOnscreen as String] as? Bool) ?? false
    }
    func reorder() {
        let tf = terminalFront()
        for (i, (p, w)) in zip(panels, wids).enumerated() {
            // Target window not on the active Space: take the ring off screen (it re-shows on the next
            // event once the target's Space is active again). A ring is only ever ordered in while its
            // target is on screen, so it is created on / stays with that window's Space.
            guard onScreen(w) else { if p.isVisible { p.orderOut(nil) }; continue }
            let lvl: NSWindow.Level = (tf && i < tops.count && tops[i]) ? .floating : .normal
            if p.level != lvl { p.level = lvl }
            if lvl == .floating { p.orderFrontRegardless() } else { p.order(.above, relativeTo: w) }
        }
    }
    func apply(_ line: String) {
        guard let main = NSScreen.screens.first else { return }
        var rects: [(Int, CGRect)] = []
        var newTops: [Bool] = []
        if line != "hide" {
            for ent in line.split(separator: "|") {
                let top = ent.hasPrefix("+")
                let v = ent.drop(while: { $0 == "+" }).split(separator: " ").compactMap { Double($0) }
                if v.count == 5 { rects.append((Int(v[0]), CGRect(x: v[1], y: v[2], width: v[3] - v[1], height: v[4] - v[2]))); newTops.append(top) }
            }
        }
        while panels.count < rects.count { panels.append(makePanel()) }
        for (i, p) in panels.enumerated() where i >= rects.count { p.orderOut(nil) }
        wids = rects.map { $0.0 }; tops = newTops
        // frontmostApplication is stale in a freshly started process until the run loop has spun: re-check once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reorder() }
        for (i, (_, r)) in rects.enumerated() {
            let frame = NSRect(x: r.minX - border, y: main.frame.height - r.maxY - border, width: r.width + 2 * border, height: r.height + 2 * border)
            if panels[i].frame != frame { panels[i].setFrame(frame, display: true); panels[i].contentView?.needsDisplay = true }
        }
        reorder()
    }
    DispatchQueue.global().async {
        while let line = readLine() { DispatchQueue.main.async { apply(line.trimmingCharacters(in: .whitespaces)) } }
        DispatchQueue.main.async { exit(0) }
    }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
        reorder(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { reorder() }
    }
    // 0.6.28: Space switch -> hide rings whose window is on another Space, re-show them when the herd Space returns
    // (event + one 0.15 s follow-up, the window list lags the notification slightly; no timer, no polling).
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
        reorder(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { reorder() }
    }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in reorder() }
    app.run()
    exit(0)
}
// 0.6.20: the old tracking mode (no --static: find the window by rect in CGWindowList every 0.5 s) is gone;
// herd always passes --static with the window ids and frames it computed itself.
FileHandle.standardError.write("herd-outline: only --static mode is supported\n".data(using: .utf8)!)
exit(2)

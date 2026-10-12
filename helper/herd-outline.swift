// herd-outline: draws a green, click-through, non-activating border around one rectangle.
// Protocol on stdin, one command per line (Terminal-style top-left coordinates of the main screen):
//   "<left> <top> <right> <bottom>"   show the border around that rectangle
//   "hide"                            hide it
// Static mode (herd-outline --static [border_px] [radius] [r g b]): draws any number of rings at the given
// rects, no window tracking or polling. One line per update, replacing everything drawn:
//   "<wid> <left> <top> <right> <bottom>|<wid> ...|..."   (wid = CGWindowID of the window to sit above)
//   "hide"                                                 remove all rings
// A wid prefixed with "+" (the zoomed window) is "topmost": while Terminal is the frontmost app its ring sits at
// floating level, because clicking/raising a window inside Terminal posts no app-activation event and would
// otherwise cover a normal-level ring ordered above it (0.6.12). Other rings, and all rings while another app is
// frontmost, stay at normal level ordered directly above their window. Re-checked on a new line or app switch.
// Exits when stdin closes (the herd manager quit). Needs no Accessibility permission.
// It hides itself when no on-screen Terminal window matches the rectangle (other Space, minimized,
// covered by fullscreen), checked via CGWindowList bounds (no window titles/screen content).
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
        p.level = .normal; p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        p.contentView = BorderView()
        return p
    }
    func reorder() {
        let tf = terminalFront()
        for (i, (p, w)) in zip(panels, wids).enumerated() {
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
    app.run()
    exit(0)
}
let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.level = .normal          // normal level, ordered directly above the target Terminal window
panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
panel.contentView = BorderView()

var target: CGRect? = nil   // top-left coords
var misses = 0, lastWID: CGWindowID? = nil

/// CGWindowID of the on-screen Terminal window (layer 0) with these bounds, or nil.
/// Uses owner PID/name and bounds only (no screen-recording permission needed).
func terminalWindowID(_ r: CGRect) -> CGWindowID? {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    let termPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").map { $0.processIdentifier })
    for w in info {
        guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, termPIDs.contains(pid),
              (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let num = w[kCGWindowNumber as String] as? CGWindowID else { continue }
        let wr = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        if abs(wr.minX - r.minX) <= 4 && abs(wr.minY - r.minY) <= 4 && abs(wr.width - r.width) <= 6 && abs(wr.height - r.height) <= 6 { return num }
    }
    return nil
}

let logPath = (NSHomeDirectory() as NSString).appendingPathComponent(".cache/herd/outline.log")
var lastState = ""
func hlog(_ s: String) {
    if s == lastState { return }
    lastState = s
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
    let line = "\(f.string(from: Date())) helper[\(ProcessInfo.processInfo.processIdentifier)] \(s)\n"
    if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8)) }
}
func refresh() {
    guard let r = target else { hlog("hidden (no target)"); panel.orderOut(nil); return }
    guard let main = NSScreen.screens.first else { return }
    // CGWindowList can transiently miss the window (Terminal re-registering it while it redraws/retitles
    // on output, reorders, retiles). Keep the outline where it is for up to 3 consecutive misses (~1.5 s)
    // instead of hiding it at once -- hiding + reshowing on a single miss is the flicker.
    let found = terminalWindowID(r)
    if found == nil {
        misses += 1
        if misses >= 3 || lastWID == nil { hlog("lookup MISS x\(misses) for \(r): hidden"); panel.orderOut(nil); return }
        hlog("lookup MISS x\(misses) for \(r): kept")
    } else { misses = 0; lastWID = found; hlog("shown above wid \(found!) at \(r)") }
    let wid = found ?? lastWID!
    let pad: CGFloat = border
    let frame = NSRect(x: r.minX - pad, y: main.frame.height - r.maxY - pad, width: r.width + 2 * pad, height: r.height + 2 * pad)
    if panel.frame != frame { panel.setFrame(frame, display: true); panel.contentView?.needsDisplay = true }   // no redraw churn
    panel.order(.above, relativeTo: Int(wid))   // directly above the target: apps in front still cover it
}

DispatchQueue.global().async {
    while let line = readLine() {
        let parts = line.split(separator: " ").compactMap { Double($0) }
        DispatchQueue.main.async {
            misses = 0; lastWID = nil
            if parts.count == 4 { target = CGRect(x: parts[0], y: parts[1], width: parts[2] - parts[0], height: parts[3] - parts[1]) }
            else { target = nil }
            refresh()
        }
    }
    DispatchQueue.main.async { exit(0) }
}
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in refresh() }
// Re-assert ordering promptly when the user switches apps (window order changes).
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
    refresh(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { refresh() }
}
app.run()

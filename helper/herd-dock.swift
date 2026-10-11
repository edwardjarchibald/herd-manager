// herd-dock: the dock area overlay + drop detection for the herd manager.
// Started by the manager; exits when its stdin closes (manager quit/reload).
//   reads  ~/.config/herd/dock-area.json  {"area":[l,t,r,b]}  (written by `herd tile`; absent = dock off)
//   writes ~/.config/herd/dock.json       {"pid":..,"bundle":"..","wid":..} when a window is docked, {} when empty,
//                                         plus "error" when Accessibility is missing.
// Coordinates are top-left of the main screen (same as Terminal bounds / CGWindowList).
// It READS window bounds from CGWindowList (no titles, no screen content) to notice a window being dragged
// with the mouse button down. It only ever MOVES/RESIZES the single window dropped into the area (via
// Accessibility), and never touches any other window.
import AppKit
import ApplicationServices

let cfg = (NSHomeDirectory() as NSString).appendingPathComponent(".config/herd")
let areaFile = cfg + "/dock-area.json", stateFile = cfg + "/dock.json"
let myPID = ProcessInfo.processInfo.processIdentifier
let termBundle = "com.apple.Terminal"
let cyan = NSColor(srgbRed: 51 / 255, green: 187 / 255, blue: 200 / 255, alpha: 1)

final class DockView: NSView {
    var bright = false
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        let p = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
        if bright {
            cyan.withAlphaComponent(0.18).setFill(); p.fill()
            cyan.setStroke(); p.lineWidth = 6; p.stroke()
            let s = "docking activated" as NSString
            let at: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.white]
            let sz = s.size(withAttributes: at)
            s.draw(at: NSPoint(x: bounds.midX - sz.width / 2, y: bounds.midY - sz.height / 2), withAttributes: at)
        } else {
            cyan.withAlphaComponent(0.35).setStroke(); p.lineWidth = 2
            p.setLineDash([10, 8], count: 2, phase: 0); p.stroke()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
let view = DockView(); panel.contentView = view

var area: CGRect? = nil, areaMtime: Date? = nil
var docked: [String: Any] = [:]
var last: [CGWindowID: CGRect] = [:]          // previous tick's bounds of movable windows
var cand: CGWindowID? = nil, candPID: pid_t = 0, candSince = Date(), candFrame = CGRect.zero

func loadArea() {
    let m = (try? FileManager.default.attributesOfItem(atPath: areaFile))?[.modificationDate] as? Date
    if m == areaMtime { return }
    areaMtime = m; area = nil
    if let d = FileManager.default.contents(atPath: areaFile),
       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let a = j["area"] as? [Double], a.count == 4 {
        area = CGRect(x: a[0], y: a[1], width: a[2] - a[0], height: a[3] - a[1])
    }
}
func save(_ d: [String: Any]) {
    docked = d
    if let data = try? JSONSerialization.data(withJSONObject: d) {
        try? data.write(to: URL(fileURLWithPath: stateFile + ".tmp")); rename(stateFile + ".tmp", stateFile)
    }
}
func show(_ mode: Int) {   // 0 hidden, 1 faint, 2 bright
    guard mode > 0, let a = area, let main = NSScreen.screens.first else { panel.orderOut(nil); return }
    panel.setFrame(NSRect(x: a.minX, y: main.frame.height - a.maxY, width: a.width, height: a.height), display: false)
    let b = mode == 2
    if view.bright != b { view.bright = b; view.needsDisplay = true }
    panel.level = b ? .floating : .normal
    if b || !panel.isVisible { panel.orderFrontRegardless() }
}
func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

/// AX window of `pid` whose frame matches `frame` (the CG bounds).
func axWindow(_ pid: pid_t, _ frame: CGRect) -> AXUIElement? {
    let appEl = AXUIElementCreateApplication(pid)
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &v) == .success, let wins = v as? [AXUIElement] else { return nil }
    for w in wins {
        var p: CFTypeRef?, s: CFTypeRef?
        var pt = CGPoint.zero, sz = CGSize.zero
        if AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success { AXValueGetValue(p as! AXValue, .cgPoint, &pt) }
        if AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success { AXValueGetValue(s as! AXValue, .cgSize, &sz) }
        if abs(pt.x - frame.minX) <= 6 && abs(pt.y - frame.minY) <= 6 && abs(sz.width - frame.width) <= 8 && abs(sz.height - frame.height) <= 8 { return w }
    }
    return nil
}
func fit(_ w: AXUIElement, _ a: CGRect) {
    var pt = a.origin, sz = a.size
    if let pv = AXValueCreate(.cgPoint, &pt) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
    if let sv = AXValueCreate(.cgSize, &sz) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
    if let pv = AXValueCreate(.cgPoint, &pt) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }  // again after size clamps
}

func tick() {
    loadArea()
    guard let a = area else { show(0); last = [:]; cand = nil; return }
    let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    var now: [CGWindowID: (CGRect, pid_t)] = [:]
    for w in info {
        guard (w[kCGWindowLayer as String] as? Int) == 0, let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
              let num = w[kCGWindowNumber as String] as? CGWindowID, let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        if NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == termBundle { continue }
        now[num] = (CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0), pid)
    }
    // docked window: still there and still inside?
    if let dw = docked["wid"] as? Int {
        let id = CGWindowID(dw)
        if let (r, _) = now[id] {
            if !a.contains(center(r)) { save([:]) }
        } else if NSRunningApplication(processIdentifier: pid_t(docked["pid"] as? Int ?? 0)) == nil { save([:]) }
    }
    let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
    // a window being dragged = its frame changed since the last tick while the button is down
    if mouseDown {
        for (id, (r, pid)) in now where id != CGWindowID(docked["wid"] as? Int ?? -1) {
            if let old = last[id], old != r { cand = id; candPID = pid; candSince = Date(); candFrame = r }
        }
    }
    last = now.mapValues { $0.0 }
    var mode = docked.isEmpty || docked["error"] != nil ? 1 : 0
    if let c = cand, let (r, _) = now[c] {
        if r != candFrame { candFrame = r; candSince = Date() }
        if a.contains(center(r)) {
            mode = 2
            if !mouseDown && Date().timeIntervalSince(candSince) >= 0.35 {
                if !AXIsProcessTrusted() { save(["error": "accessibility"]); cand = nil }
                else if let w = axWindow(candPID, r) {
                    fit(w, a)
                    save(["pid": Int(candPID), "bundle": NSRunningApplication(processIdentifier: candPID)?.bundleIdentifier ?? "", "wid": Int(c)])
                    cand = nil; mode = 0
                } else { cand = nil }
            }
        } else if !mouseDown { cand = nil }
    } else { cand = nil }
    // faint outline only while Terminal is the active app (so it never sits over other apps' work)
    if mode == 1 && NSWorkspace.shared.frontmostApplication?.bundleIdentifier != termBundle { mode = 0 }
    show(mode)
}

if let d = FileManager.default.contents(atPath: stateFile), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { docked = j }
DispatchQueue.global().async {
    while readLine() != nil {}
    DispatchQueue.main.async { exit(0) }
}
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in tick() }
app.run()

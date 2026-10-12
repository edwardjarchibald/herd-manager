// herd-scrim: dark, click-through, non-activating scrim for zoom. Ordered DIRECTLY BELOW the zoomed
// Terminal window (found by its bounds in CGWindowList, like herd-outline), so it sits above the other
// herd terminals but under the zoomed one. Started by the herd manager; exits when stdin closes.
// stdin, one command per line (top-left coordinates of the main screen):
//   "<l> <t> <r> <b> <alpha> <zl> <zt> <zr> <zb>"   scrim over l,t,r,b below the window with bounds z*
//   "hide"
import AppKit

final class V: NSView {
    var alpha: CGFloat = 0.85
    override func draw(_ r: NSRect) { NSColor.black.withAlphaComponent(alpha).setFill(); bounds.fill() }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
panel.ignoresMouseEvents = true; panel.level = .normal
panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
let view = V(); panel.contentView = view
var area: CGRect? = nil, zoomed = CGRect.zero

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
func refresh() {
    guard let a = area, let wid = terminalWindowID(zoomed), let main = NSScreen.screens.first else { panel.orderOut(nil); return }
    panel.setFrame(NSRect(x: a.minX, y: main.frame.height - a.maxY, width: a.width, height: a.height), display: true)
    panel.order(.below, relativeTo: Int(wid))
}
DispatchQueue.global().async {
    while let line = readLine() {
        let p = line.split(separator: " ").compactMap { Double($0) }
        DispatchQueue.main.async {
            if p.count == 9 {
                area = CGRect(x: p[0], y: p[1], width: p[2] - p[0], height: p[3] - p[1])
                view.alpha = CGFloat(p[4]); view.needsDisplay = true
                zoomed = CGRect(x: p[5], y: p[6], width: p[7] - p[5], height: p[8] - p[6])
            } else { area = nil }
            refresh()
        }
    }
    DispatchQueue.main.async { exit(0) }
}
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in refresh() }
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
    refresh(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { refresh() }
}
app.run()

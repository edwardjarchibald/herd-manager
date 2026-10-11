// herd-outline: draws a green, click-through, non-activating border around one rectangle.
// Protocol on stdin, one command per line (Terminal-style top-left coordinates of the main screen):
//   "<left> <top> <right> <bottom>"   show the border around that rectangle
//   "hide"                            hide it
// Exits when stdin closes (the herd manager quit). Needs no Accessibility permission.
// It hides itself when no on-screen Terminal window matches the rectangle (other Space, minimized,
// covered by fullscreen), checked via CGWindowList bounds (no window titles/screen content).
import AppKit

let border: CGFloat = 3
final class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemGreen.setStroke()
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: border / 2, dy: border / 2), xRadius: 8, yRadius: 8)
        p.lineWidth = border
        p.stroke()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
panel.contentView = BorderView()

var target: CGRect? = nil   // top-left coords

func terminalWindowOnScreen(_ r: CGRect) -> Bool {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
    for w in info {
        guard (w[kCGWindowOwnerName as String] as? String) == "Terminal",
              let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let wr = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        if abs(wr.minX - r.minX) <= 4 && abs(wr.minY - r.minY) <= 4 && abs(wr.width - r.width) <= 6 && abs(wr.height - r.height) <= 6 { return true }
    }
    return false
}

func refresh() {
    guard let r = target, terminalWindowOnScreen(r), let main = NSScreen.screens.first else { panel.orderOut(nil); return }
    let pad: CGFloat = border
    let frame = NSRect(x: r.minX - pad, y: main.frame.height - r.maxY - pad, width: r.width + 2 * pad, height: r.height + 2 * pad)
    panel.setFrame(frame, display: true)
    panel.contentView?.needsDisplay = true
    panel.orderFrontRegardless()
}

DispatchQueue.global().async {
    while let line = readLine() {
        let parts = line.split(separator: " ").compactMap { Double($0) }
        DispatchQueue.main.async {
            if parts.count == 4 { target = CGRect(x: parts[0], y: parts[1], width: parts[2] - parts[0], height: parts[3] - parts[1]) }
            else { target = nil }
            refresh()
        }
    }
    DispatchQueue.main.async { exit(0) }
}
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in refresh() }
app.run()

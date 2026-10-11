// herd-outline: draws a green, click-through, non-activating border around one rectangle.
// Protocol on stdin, one command per line (Terminal-style top-left coordinates of the main screen):
//   "<left> <top> <right> <bottom>"   show the border around that rectangle
//   "hide"                            hide it
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

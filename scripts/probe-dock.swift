import AppKit
import CoreGraphics

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func run(_ label: String) {
    let screen = NSScreen.screens[0]
    print("--- \(label) frame=\(screen.frame) visible=\(screen.visibleFrame)")
    let frame = NSRect(x: screen.frame.maxX - 300, y: screen.frame.minY, width: 300, height: screen.frame.height - 40)
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.backgroundColor = .red
    panel.setFrame(frame, display: true)
    panel.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    print("statusBar level raw=\(NSWindow.Level.statusBar.rawValue) dock level raw=\(CGWindowLevelForKey(.dockWindow))")
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    var i = 0
    for w in info {
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
        if owner == "Dock" || pid == Int(getpid()) {
            print("order \(i): owner=\(owner) layer=\(w[kCGWindowLayer as String] ?? "-") bounds=\((w[kCGWindowBounds as String] as? [String: Any]).map { "\($0["X"]!),\($0["Y"]!),\($0["Width"]!),\($0["Height"]!)" } ?? "-")")
        }
        i += 1
    }
    // 帯の下の端の真ん中の点で、いちばん手前のウインドウを調べる
    let point = CGPoint(x: frame.midX, y: 10) // CG の座標は左上が原点
    if let top = info.first(where: { w in
        guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
        return CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!).contains(CGPoint(x: point.x, y: screen.frame.height - 10))
    }) {
        print("frontmost at band bottom: owner=\(top[kCGWindowOwnerName as String] ?? "?") layer=\(top[kCGWindowLayer as String] ?? "-")")
    }
    panel.orderOut(nil)
}
let mode = CommandLine.arguments.dropFirst().first ?? "?"
run(mode)

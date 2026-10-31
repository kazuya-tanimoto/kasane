import AppKit
import CoreGraphics
import QuartzCore

// 履歴ウインドウの枠の作り方を比べる（一時的な調べ。マージしない）
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let out = CommandLine.arguments.dropFirst().first ?? "probe-out"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

print("PROBE screenCaptureAccess=\(CGPreflightScreenCaptureAccess()) axTrusted=\(AXIsProcessTrusted())")
for name in ["_cornerMask", "_cornerRadius", "_setCornerRadius:", "setCornerRadius:", "_getCornerRadius"] {
    print("PROBE NSWindow responds \(name)=\(NSWindow.instancesRespond(to: Selector((name))))")
}
func listMethods(_ cls: AnyClass?, _ label: String) {
    guard let cls else { print("PROBE no class \(label)"); return }
    var count: UInt32 = 0
    if let methods = class_copyMethodList(cls, &count) {
        for i in 0..<Int(count) {
            let n = NSStringFromSelector(method_getName(methods[i]))
            if n.lowercased().contains("corner") || n.lowercased().contains("shape") { print("PROBE method \(label) \(n)") }
        }
        free(methods)
    }
}
listMethods(NSWindow.self, "NSWindow")
listMethods(NSPanel.self, "NSPanel")
listMethods(NSClassFromString("NSThemeFrame"), "NSThemeFrame")
listMethods(NSClassFromString("NSTitledFrame"), "NSTitledFrame")
listMethods(NSClassFromString("NSFrameView"), "NSFrameView")

typealias ConnF = @convention(c) () -> Int32
typealias BlurF = @convention(c) (Int32, Int, Int32) -> Int32
let h = UnsafeMutableRawPointer(bitPattern: -2)
let conn = unsafeBitCast(dlsym(h, "CGSMainConnectionID")!, to: ConnF.self)
let setBlur = unsafeBitCast(dlsym(h, "CGSSetWindowBackgroundBlurRadius")!, to: BlurF.self)
func blur(_ w: NSWindow, _ r: Int32) { print("PROBE blur status=\(setBlur(conn(), w.windowNumber, r))") }

func cornerImage(_ r: CGFloat) -> NSImage {
    let s = r * 2 + 1
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
        return true
    }
    img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
    img.resizingMode = .stretch
    return img
}

class Plain: NSPanel { override var canBecomeKey: Bool { true } }
class Masked: NSPanel {
    override var canBecomeKey: Bool { true }
    @objc func _cornerMask() -> NSImage? { cornerImage(20) }
}
class Radius20: NSPanel {
    override var canBecomeKey: Bool { true }
    @objc func _cornerRadius() -> CGFloat { 20 }
}
class Radius20Mask: NSPanel {
    override var canBecomeKey: Bool { true }
    @objc func _cornerRadius() -> CGFloat { 20 }
    @objc func _cornerMask() -> NSImage? { cornerImage(20) }
}

final class Stripes: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        var x: CGFloat = 0
        var i = 0
        while x < bounds.width {
            (i % 2 == 0 ? NSColor.red : NSColor.blue).setFill()
            NSRect(x: x, y: 0, width: 3, height: bounds.height).fill()
            x += 6; i += 1
        }
    }
}

let screen = NSScreen.screens[0]
print("PROBE screen=\(screen.frame) scale=\(screen.backingScaleFactor)")
let bg = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
bg.contentView = Stripes()
bg.level = .normal
bg.orderFrontRegardless()

func content(rounded: Bool) -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.25).cgColor
    if rounded {
        v.layer?.cornerRadius = 20
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
        v.layer?.borderWidth = 1
        v.layer?.borderColor = NSColor(white: 0, alpha: 0.8).cgColor
    }
    return v
}

var windows: [(String, NSWindow)] = []
func place(_ name: String, _ w: NSWindow, col: Int, row: Int, blurRadius: Int32?) {
    w.isOpaque = false
    w.backgroundColor = .clear
    w.level = .floating
    w.setFrame(NSRect(x: 40 + col * 340, y: 60 + row * 300, width: 300, height: 220), display: true)
    w.orderFrontRegardless()
    if let blurRadius { blur(w, blurRadius) }
    windows.append((name, w))
}
let titledMask: NSWindow.StyleMask = [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView]
let borderlessMask: NSWindow.StyleMask = [.borderless, .resizable, .nonactivatingPanel]
func hideTitle(_ w: NSWindow) {
    w.titleVisibility = .hidden; w.titlebarAppearsTransparent = true
    for t in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(t)?.isHidden = true }
}

// 1 今の作り
let w1 = Plain(contentRect: .zero, styleMask: titledMask, backing: .buffered, defer: false); hideTitle(w1); w1.contentView = content(rounded: false); w1.hasShadow = true
place("1-titled-now", w1, col: 0, row: 1, blurRadius: 20)
// 2 縁なし＋半径のぼかし
let w2 = Plain(contentRect: .zero, styleMask: borderlessMask, backing: .buffered, defer: false); w2.contentView = content(rounded: true); w2.hasShadow = false
place("2-borderless-cgs", w2, col: 1, row: 1, blurRadius: 20)
// 3 縁なし＋_cornerMask＋半径のぼかし
let w3 = Masked(contentRect: .zero, styleMask: borderlessMask, backing: .buffered, defer: false); w3.contentView = content(rounded: true); w3.hasShadow = false
place("3-borderless-cornermask-cgs", w3, col: 2, row: 1, blurRadius: 20)
// 4 縁なし＋NSVisualEffectView の maskImage
let w4 = Plain(contentRect: .zero, styleMask: borderlessMask, backing: .buffered, defer: false)
let vev = NSVisualEffectView(); vev.blendingMode = .behindWindow; vev.state = .active; vev.material = .popover; vev.maskImage = cornerImage(20)
let c4 = content(rounded: true); c4.autoresizingMask = [.width, .height]; vev.addSubview(c4); w4.contentView = vev; w4.hasShadow = false
place("4-borderless-vev-mask", w4, col: 3, row: 1, blurRadius: nil)
c4.frame = vev.bounds
// 5 タイトル付き＋_cornerRadius 20
let w5 = Radius20(contentRect: .zero, styleMask: titledMask, backing: .buffered, defer: false); hideTitle(w5); w5.contentView = content(rounded: false); w5.hasShadow = true
place("5-titled-radius20", w5, col: 0, row: 0, blurRadius: 20)
// 6 タイトル付き＋_cornerRadius 20＋影なし
let w6 = Radius20(contentRect: .zero, styleMask: titledMask, backing: .buffered, defer: false); hideTitle(w6); w6.contentView = content(rounded: false); w6.hasShadow = false
place("6-titled-radius20-noshadow", w6, col: 1, row: 0, blurRadius: 20)
// 7 縁なし＋_cornerRadius と _cornerMask＋半径のぼかし
let w7 = Radius20Mask(contentRect: .zero, styleMask: borderlessMask, backing: .buffered, defer: false); w7.contentView = content(rounded: true); w7.hasShadow = false
place("7-borderless-radius-mask-cgs", w7, col: 2, row: 0, blurRadius: 20)
// 8 縁なし＋ぼかしなし（比べる元）
let w8 = Plain(contentRect: .zero, styleMask: borderlessMask, backing: .buffered, defer: false); w8.contentView = content(rounded: true); w8.hasShadow = false
place("8-borderless-noblur", w8, col: 3, row: 0, blurRadius: nil)

RunLoop.main.run(until: Date().addingTimeInterval(2))
for (name, w) in windows { print("PROBE frame \(name) \(w.frame) number=\(w.windowNumber)") }

func capture(_ file: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "\(out)/\(file)"]
    try? p.run(); p.waitUntilExit()
    print("PROBE capture \(file) status=\(p.terminationStatus)")
}
capture("all.png")

// 端をつかんで大きさを変えられるか（右の端と右下の角）。マウスの操作を送れないときは、1 の今の作りも変わらない
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
let H = screen.frame.height
func drag(_ w: NSWindow, from: NSPoint, by dx: CGFloat, _ dy: CGFloat) {
    let a = CGPoint(x: from.x, y: H - from.y)
    post(.mouseMoved, a); RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    post(.leftMouseDown, a); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    for k in 1...10 {
        post(.leftMouseDragged, CGPoint(x: a.x + dx * CGFloat(k) / 10, y: a.y - dy * CGFloat(k) / 10))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    post(.leftMouseUp, CGPoint(x: a.x + dx, y: a.y - dy)); RunLoop.main.run(until: Date().addingTimeInterval(0.5))
}
for (name, w) in windows where ["1-titled-now", "2-borderless-cgs", "3-borderless-cornermask-cgs", "7-borderless-radius-mask-cgs"].contains(name) {
    for inset: CGFloat in [-2, 1, 3] {
        let before = w.frame
        drag(w, from: NSPoint(x: before.maxX + inset * -1, y: before.midY), by: 30, 0)
        print("PROBE resize-right \(name) edgeInset=\(inset) before=\(before.size) after=\(w.frame.size)")
        w.setFrame(before, display: true)
    }
    let before = w.frame
    drag(w, from: NSPoint(x: before.maxX - 2, y: before.minY + 2), by: 30, -30)
    print("PROBE resize-corner \(name) before=\(before.size) after=\(w.frame.size)")
    w.setFrame(before, display: true)
    w.makeKeyAndOrderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    print("PROBE key \(name) isKey=\(w.isKeyWindow)")
}
capture("after.png")

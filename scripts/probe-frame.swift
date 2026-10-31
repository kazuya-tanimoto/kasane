import AppKit
import CoreGraphics
import QuartzCore

// 履歴ウインドウの枠の作り方を比べる 2 回目（一時的な調べ。マージしない）
setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let out = CommandLine.arguments.dropFirst().first ?? "probe-out"

typealias ConnF = @convention(c) () -> Int32
typealias BlurF = @convention(c) (Int32, Int, Int32) -> Int32
let h = UnsafeMutableRawPointer(bitPattern: -2)
let conn = unsafeBitCast(dlsym(h, "CGSMainConnectionID")!, to: ConnF.self)
let setBlur = unsafeBitCast(dlsym(h, "CGSSetWindowBackgroundBlurRadius")!, to: BlurF.self)
func blur(_ w: NSWindow, _ r: Int32) { print("PROBE blur \(r) status=\(setBlur(conn(), w.windowNumber, r))") }
func wait(_ s: Double) {
    if Thread.isMainThread {
        let end = Date().addingTimeInterval(s)
        while Date() < end {
            if let e = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) { app.sendEvent(e) }
        }
    } else {
        Thread.sleep(forTimeInterval: s)
    }
}
func onMain<T>(_ f: () -> T) -> T { DispatchQueue.main.sync(execute: f) }
app.finishLaunching()

final class Stripes: NSView {
    var clicks = 0
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        var x: CGFloat = 0; var i = 0
        while x < bounds.width {
            (i % 2 == 0 ? NSColor.red : NSColor.blue).setFill()
            NSRect(x: x, y: 0, width: 3, height: bounds.height).fill()
            x += 6; i += 1
        }
    }
    override func mouseDown(with event: NSEvent) { clicks += 1 }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class DragArea: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

let screen = NSScreen.screens[0]
let H = screen.frame.height
let bgView = Stripes()
let bg = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768), styleMask: [.borderless], backing: .buffered, defer: false)
bg.contentView = bgView
bg.level = .normal
bg.orderFrontRegardless()

func makeContent() -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.25).cgColor
    v.layer?.cornerRadius = 20
    v.layer?.cornerCurve = .continuous
    v.layer?.masksToBounds = true
    v.layer?.borderWidth = 1
    v.layer?.borderColor = NSColor(white: 0, alpha: 0.8).cgColor
    let drag = DragArea(frame: NSRect(x: 0, y: 0, width: 10, height: 28))
    drag.autoresizingMask = [.width, .minYMargin]
    v.addSubview(drag)
    let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 24))
    field.autoresizingMask = []
    v.addSubview(field)
    return v
}

/// 影だけのウインドウ。角丸の外にだけ影を落とし、クリックは後ろに通す
final class ShadowPanel: NSPanel {
    let caster = CALayer()
    let holder = CALayer()
    let pad: CGFloat = 120
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; ignoresMouseEvents = true
        let v = NSView(); v.wantsLayer = true
        caster.shadowColor = NSColor.black.cgColor
        caster.shadowOpacity = 0.35
        caster.shadowRadius = 40
        caster.shadowOffset = CGSize(width: 0, height: -30)
        holder.addSublayer(caster)
        v.layer?.addSublayer(holder)
        contentView = v
    }
    override var canBecomeKey: Bool { false }
    func follow(_ w: NSWindow) {
        setFrame(w.frame.insetBy(dx: -pad, dy: -pad), display: false)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let bounds = CGRect(origin: .zero, size: frame.size)
        holder.frame = bounds
        let shape = CGRect(x: pad, y: pad, width: w.frame.width, height: w.frame.height)
        caster.frame = bounds
        caster.shadowPath = CGPath(roundedRect: shape, cornerWidth: 20, cornerHeight: 20, transform: nil)
        let mask = CAShapeLayer()
        let p = CGMutablePath(); p.addRect(bounds); p.addRoundedRect(in: shape, cornerWidth: 20, cornerHeight: 20)
        mask.path = p; mask.fillRule = .evenOdd
        holder.mask = mask
        CATransaction.commit()
    }
}

// A: 縁なし、出してからぼかし 0 → 20 に変える
let a = Panel(contentRect: .zero, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
a.isOpaque = false; a.backgroundColor = .clear; a.level = .floating; a.hasShadow = false
a.contentView = makeContent()
a.setFrame(NSRect(x: 60, y: 400, width: 300, height: 220), display: true)
a.orderFrontRegardless(); blur(a, 0); wait(0.5); blur(a, 20)
// B: 縁なし、ぼかし 20、影のウインドウ付き（子ウインドウ）
let b = Panel(contentRect: .zero, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
b.isOpaque = false; b.backgroundColor = .clear; b.level = .floating; b.hasShadow = false
b.contentView = makeContent()
b.setFrame(NSRect(x: 520, y: 380, width: 300, height: 220), display: true)
let shadow = ShadowPanel(); shadow.level = .floating
b.orderFrontRegardless(); blur(b, 20)
shadow.follow(b)
b.addChildWindow(shadow, ordered: .below)
wait(1.5)
func capture(_ file: String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "\(out)/\(file)"]; try? p.run(); p.waitUntilExit()
    print("PROBE capture \(file) status=\(p.terminationStatus)")
}
capture("1-start.png")

// マウスの操作を送る。届いたかは、モニタで数える
nonisolated(unsafe) var seen: [String: Int] = [:]
_ = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]) { e in
    seen["\(e.type.rawValue)@\(e.window.map { $0 === a ? "A" : $0 === b ? "B" : $0 === bg ? "bg" : "?" } ?? "-")", default: 0] += 1
    return e
}
// 比べる元: タイトル付きのウインドウ
let t = Panel(contentRect: .zero, styleMask: [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
t.level = .floating
t.contentView = NSView()
t.setFrame(NSRect(x: 60, y: 60, width: 300, height: 220), display: true)
t.orderFrontRegardless(); wait(0.5)

Thread.detachNewThread {
let src = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: NSPoint) {
    CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: CGPoint(x: p.x, y: H - p.y), mouseButton: .left)?.post(tap: .cghidEventTap)
}
func drag(from: NSPoint, by dx: CGFloat, _ dy: CGFloat) {
    post(.mouseMoved, from); wait(0.4)
    post(.leftMouseDown, from); wait(0.3)
    for k in 1...15 { post(.leftMouseDragged, NSPoint(x: from.x + dx * CGFloat(k) / 15, y: from.y + dy * CGFloat(k) / 15)); wait(0.04) }
    wait(0.2); post(.leftMouseUp, NSPoint(x: from.x + dx, y: from.y + dy)); wait(0.6)
}
for (name, w) in [("titled", t as NSWindow), ("A", a), ("B", b)] {
    for inset: CGFloat in [-3, 0, 2, 5] {
        let before = onMain { w.frame }
        drag(from: NSPoint(x: before.maxX - inset, y: before.midY - 40), by: 40, 0)
        print("PROBE resize-right \(name) inset=\(inset) before=\(before.size) after=\(onMain { w.frame.size })")
        onMain { if w.frame != before { w.setFrame(before, display: true) } }
    }
    do {
        let before = onMain { w.frame }
        drag(from: NSPoint(x: before.minX + 1, y: before.minY + 1), by: -30, -30)
        print("PROBE resize-bottomleft \(name) before=\(before) after=\(onMain { w.frame })")
        onMain { if w.frame != before { w.setFrame(before, display: true) } }
    }
    do {
        let before = onMain { w.frame }
        drag(from: NSPoint(x: before.midX, y: before.maxY - 2), by: 0, 30)
        print("PROBE resize-top \(name) before=\(before) after=\(onMain { w.frame })")
        onMain { if w.frame != before { w.setFrame(before, display: true) } }
    }
}
print("PROBE seen \(onMain { seen })")
// ドラッグで動かす（上の帯の DragArea）
for (name, w) in [("A", a), ("B", b)] {
    let before = onMain { w.frame }
    drag(from: NSPoint(x: before.midX, y: before.maxY - 14), by: 50, -40)
    print("PROBE move \(name) before=\(before.origin) after=\(onMain { w.frame.origin }) shadowFollows=\(onMain { shadow.frame.origin })")
}
// 大きさを変えたら影も合わせる（コードで）
onMain { b.setFrame(NSRect(x: b.frame.minX, y: b.frame.minY, width: 380, height: 260), display: true); shadow.follow(b) }
wait(0.8)
capture("2-moved-resized.png")
// 影の所をクリックすると後ろに届くか（B の下の影の所）
let clicksBefore = onMain { bgView.clicks }
let shadowPoint = onMain { NSPoint(x: b.frame.midX, y: b.frame.minY - 30) }
post(.mouseMoved, shadowPoint); wait(0.3); post(.leftMouseDown, shadowPoint); wait(0.1); post(.leftMouseUp, shadowPoint); wait(0.5)
print("PROBE click-through-shadow at=\(shadowPoint) bgClicks \(clicksBefore)->\(onMain { bgView.clicks })")
// 角の外（ウインドウの四角の中で、角丸の外）をクリックするとどこに届くか
let cornerPoint = onMain { NSPoint(x: b.frame.minX + 2, y: b.frame.maxY - 2) }
let c0 = onMain { bgView.clicks }
post(.mouseMoved, cornerPoint); wait(0.3); post(.leftMouseDown, cornerPoint); wait(0.1); post(.leftMouseUp, cornerPoint); wait(0.5)
print("PROBE click-corner-outside bgClicks \(c0)->\(onMain { bgView.clicks })")
// キー入力
onMain { b.makeKeyAndOrderFront(nil) }; wait(0.3)
onMain { if let field = b.contentView?.subviews.compactMap({ $0 as? NSTextField }).first { b.makeFirstResponder(field) } }
wait(0.3)
for code: CGKeyCode in [0, 11] { // a, b
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    wait(0.2)
}
wait(0.5)
let typed = onMain { b.contentView?.subviews.compactMap({ $0 as? NSTextField }).first?.stringValue ?? "?" }
print("PROBE key B isKey=\(onMain { b.isKeyWindow }) typed='\(typed)' seen=\(onMain { seen })")

exit(0)
}
app.run()

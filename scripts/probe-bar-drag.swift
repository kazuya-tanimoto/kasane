import AppKit
import CoreGraphics

// 一時的な調べ（probe/glass-bar-extend）。マージしない。
// 右下の帯の、ボタンの左の空いた所をつかんでウインドウが動くかを、初めの幅と一番狭い幅で確かめる
setvbuf(stdout, nil, _IOLBF, 0)
let binary = CommandLine.arguments[1], out = CommandLine.arguments[2]
let proc = Process()
proc.executableURL = URL(fileURLWithPath: binary)
try! proc.run()
let pid = proc.processIdentifier
Thread.sleep(forTimeInterval: 6)

let src = CGEventSource(stateID: .hidSystemState)
func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true); d?.flags = flags; d?.post(tap: .cghidEventTap)
    let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false); u?.flags = flags; u?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.15)
}
func mouse(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func drag(_ from: CGPoint, _ dx: CGFloat, _ dy: CGFloat) {
    mouse(.mouseMoved, from); Thread.sleep(forTimeInterval: 0.4)
    mouse(.leftMouseDown, from); Thread.sleep(forTimeInterval: 0.3)
    for k in 1...15 { mouse(.leftMouseDragged, CGPoint(x: from.x + dx * CGFloat(k) / 15, y: from.y + dy * CGFloat(k) / 15)); Thread.sleep(forTimeInterval: 0.04) }
    Thread.sleep(forTimeInterval: 0.2); mouse(.leftMouseUp, CGPoint(x: from.x + dx, y: from.y + dy)); Thread.sleep(forTimeInterval: 0.8)
}
func history() -> CGRect? {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let rects: [CGRect] = info.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, (w[kCGWindowLayer as String] as? Int) == 3,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat], b["Width"]! > 400 else { return nil }
        return CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
    }
    return rects.sorted { $0.width < $1.width }.first
}
func capture(_ name: String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "\(out)/\(name).png"]; try? p.run(); p.waitUntilExit()
}
func open() { key(9, flags: .maskAlternate); Thread.sleep(forTimeInterval: 1.2) }
func ensureOpen() -> CGRect? { if let w = history() { return w }; print("PROBE (reopen)"); open(); return history() }

func all() -> [String] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        return "\(w[kCGWindowLayer as String] ?? -1):\(b)"
    }
}
print("PROBE windows at launch: \(all())")
for _ in 0..<3 where history() == nil { open(); Thread.sleep(forTimeInterval: 1.5); print("PROBE after ⌥V: \(all())") }
guard var w = history() else { print("PROBE history window not found"); capture("notfound"); proc.terminate(); exit(0) }
print("PROBE open frame \(w)")
capture("1-default")
// 帯の縦の真ん中（下から 10 + 帯の高さ 34 の半分）
let barY: (CGRect) -> CGFloat = { $0.maxY - 10 - 17 }
// 1. 初めの幅: 帯の左端（左から 202）の少し右をつかむ
drag(CGPoint(x: w.minX + 202 + 20, y: barY(w)), 60, -40)
var after = history()
print("PROBE default-width drag-in-bar width=\(w.width) origin \(w.origin)->\(after?.origin ?? .zero)")
// 2. 帯の左端より左（一覧の上）をつかんでも動かないこと（一覧の行）
w = ensureOpen() ?? w
drag(CGPoint(x: w.minX + 202 - 30, y: barY(w)), 60, -40)
after = history()
print("PROBE default-width drag-on-list-left-of-bar origin \(w.origin)->\(after?.origin ?? .zero)")
// 3. 一番狭くする: 右の縁をつかんで左へ 400
w = ensureOpen() ?? w
drag(CGPoint(x: w.maxX - 2, y: w.midY), -400, 0)
w = ensureOpen() ?? w
print("PROBE narrow frame \(w)")
capture("2-narrow")
// 4. 一番狭い幅: 帯の左端の少し右をつかむ（ボタンの左の空きは約 40pt）
drag(CGPoint(x: w.minX + 202 + 12, y: barY(w)), 60, -40)
after = history()
print("PROBE narrow-width drag-in-bar width=\(w.width) origin \(w.origin)->\(after?.origin ?? .zero)")
// 5. 一番狭い幅: ペーストのボタンを押すと動かない（押した扱い）こと。ボタンの上でドラッグしてもウインドウは動かない
w = ensureOpen() ?? w
capture("3-narrow-moved")
proc.terminate()

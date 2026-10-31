import AppKit
import CoreGraphics

// 履歴ウインドウの動きを、変える前（main）と後で比べる（一時的な調べ。マージしない）
// 使い方: swift scripts/probe-e2e.swift <Kasane の実行ファイル> <名前> <出力先> <余白>
setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
let binary = args[1], label = args[2], out = args[3]
let margin = CGFloat(Double(args[4]) ?? 0)

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
func click(_ p: CGPoint) {
    mouse(.mouseMoved, p); Thread.sleep(forTimeInterval: 0.3)
    mouse(.leftMouseDown, p); Thread.sleep(forTimeInterval: 0.1); mouse(.leftMouseUp, p); Thread.sleep(forTimeInterval: 0.8)
}
struct Win { let bounds: CGRect; let layer: Int; let alpha: Double; let number: Int }
func windows() -> [Win] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        return Win(bounds: CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!), layer: w[kCGWindowLayer as String] as? Int ?? -1, alpha: w[kCGWindowAlpha as String] as? Double ?? -1, number: w[kCGWindowNumber as String] as? Int ?? 0)
    }
}
/// 履歴ウインドウ: 浮いているウインドウのうち、影のウインドウ（いちばん大きい）でない方
func history() -> CGRect? {
    let floating = windows().filter { $0.layer == 3 && $0.bounds.width > 400 }
    let sorted = floating.sorted { $0.bounds.width < $1.bounds.width }
    return sorted.first?.bounds
}
func capture(_ name: String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "\(out)/\(label)-\(name).png"]; try? p.run(); p.waitUntilExit()
}
func open() { key(9, flags: .maskAlternate); Thread.sleep(forTimeInterval: 1.2) }
func log(_ s: String) { print("PROBE \(label) \(s)") }
/// 外をクリックすると閉じるので、閉じていたら開き直してから、今の位置を返す
func ensureOpen() -> CGRect? {
    if let w = history() { return w }
    log("(reopen)")
    open()
    return history()
}

log("windows at launch: \(windows().map { "\($0.layer):\($0.bounds)" })")
open()
log("windows after ⌥V: \(windows().map { "\($0.layer):\($0.bounds) a=\($0.alpha)" })")
guard var w = history() else { log("history window not found"); capture("notfound"); proc.terminate(); exit(0) }
capture("1-open")

// 見える縁から外へ d pt の所をつかんで、右へ 30 動かす
for d: CGFloat in [4, 3, 2, 1, 0, -1, -2, -3, -5] {
    w = ensureOpen() ?? w
    let edge = w.maxX - margin
    drag(CGPoint(x: edge + d, y: w.midY), 30, 0)
    let after = history() ?? w
    log("resize-right d=\(d) width \(w.width)->\(after.width) visible=\(history() != nil)")
    if after.width != w.width { drag(CGPoint(x: after.maxX - margin + d, y: after.midY), -30, 0) }
}
for d: CGFloat in [3, 1, 0, -2, -4] {
    w = ensureOpen() ?? w
    let corner = CGPoint(x: w.maxX - margin + d, y: w.maxY - margin + d)
    drag(corner, 30, 30)
    let after = history() ?? w
    log("resize-bottomright d=\(d) size \(w.size)->\(after.size) visible=\(history() != nil)")
    if after.size != w.size { drag(CGPoint(x: after.maxX - margin + d, y: after.maxY - margin + d), -30, -30) }
}
for d: CGFloat in [3, 1, 0, -2, -4] {
    w = ensureOpen() ?? w
    let corner = CGPoint(x: w.minX + margin - d, y: w.minY + margin - d)
    drag(corner, -30, -30)
    let after = history() ?? w
    log("resize-topleft d=\(d) frame \(w)->\(after) visible=\(history() != nil)")
    if after.size != w.size { drag(CGPoint(x: after.minX + margin - d, y: after.minY + margin - d), 30, 30) }
}
// 上の「Kasane」の帯をつかんで動かす
w = ensureOpen() ?? w
drag(CGPoint(x: w.midX, y: w.minY + margin + 14), 60, 40)
let moved = history() ?? w
log("move origin \(w.origin)->\(moved.origin) visible=\(history() != nil)")
log("windows after move: \(windows().map { "\($0.layer):\($0.bounds)" })")
// キー入力（検索欄に abc）
w = ensureOpen() ?? w
key(0); key(11); key(8)
Thread.sleep(forTimeInterval: 0.5)
capture("2-typed")
// 影の所（下の縁の 40pt 下）をクリックすると、履歴ウインドウが閉じるか（クリックが後ろに届くと閉じる）
w = ensureOpen() ?? w
click(CGPoint(x: w.midX, y: w.maxY + 40))
Thread.sleep(forTimeInterval: 0.5)
log("after clicking the shadow, history visible=\(history() != nil)")
// ダークで開き直す
let osa = Process(); osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
osa.arguments = ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to true"]
try? osa.run(); osa.waitUntilExit()
log("dark mode osascript status=\(osa.terminationStatus)")
Thread.sleep(forTimeInterval: 1.5)
open()
capture("3-dark")
log("windows dark: \(windows().map { "\($0.layer):\($0.bounds)" })")
key(53) // Esc
let osa2 = Process(); osa2.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
osa2.arguments = ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to false"]
try? osa2.run(); osa2.waitUntilExit()
proc.terminate()

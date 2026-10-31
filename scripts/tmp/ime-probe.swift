import Carbon
import Foundation

func id(_ s: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}
func current() -> String { id(TISCopyCurrentKeyboardInputSource().takeRetainedValue()) }
let all = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
let jp = all.filter { id($0).contains("Kotoeri") }
print("kotoeri sources:", jp.map(id))
for s in jp { TISEnableInputSource(s) }
let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
func find(_ suffix: String) -> TISInputSource? { list.first { id($0).hasSuffix(suffix) } }
guard let kata = find("Katakana"), let hira = find("Japanese") ?? find("Hiragana") else { print("no katakana/hiragana enabled; enabled:", list.map(id)); exit(0) }
let abc = list.first { id($0).hasSuffix("ABC") || id($0).hasSuffix("US") }
print("katakana:", id(kata), "hiragana:", id(hira), "abc:", abc.map(id) ?? "-")
func measure(_ label: String, from: TISInputSource, to: TISInputSource) {
    TISSelectInputSource(from)
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    let start = Date()
    TISSelectInputSource(to)
    let call = Date().timeIntervalSince(start)
    var reached: Double = -1
    while Date().timeIntervalSince(start) < 2 {
        if current() == id(to) { reached = Date().timeIntervalSince(start); break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.002))
    }
    print(String(format: "%@ call=%.1fms reached=%.1fms now=%@", label, call * 1000, reached * 1000, current()))
}
for i in 1...5 {
    measure("hira->kata #\(i)", from: hira, to: kata)
    if let abc { measure("abc->kata #\(i)", from: abc, to: kata) }
}

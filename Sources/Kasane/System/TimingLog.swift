import AppKit
import Carbon
import os

/// 一時的な計測用。かなのときに履歴ウインドウの開閉が遅い原因を調べる（原因がわかって直したら消す）。
///
/// 開く・閉じるごとに、ショートカットを受け取ってからの経過時間をログに出す。
/// あわせて、メインスレッドが止まっていた時間と、入力方法が実際に切り替わった時刻も出す。
/// 見るとき: `log show --last 2m --predicate 'subsystem == "io.github.kazuya-tanimoto.kasane"' --style compact`
@MainActor
enum TimingLog {
    private static let logger = Logger(subsystem: "io.github.kazuya-tanimoto.kasane", category: "timing")
    private static var start = CFAbsoluteTimeGetCurrent()
    private static var label = "-"
    private static var count = 0
    private static var ticker: Timer?
    private static var lastTick = CFAbsoluteTimeGetCurrent()
    private static var tickerUntil = CFAbsoluteTimeGetCurrent()
    private static var observer: NSObjectProtocol?

    /// 開く・閉じるの始まり。ここからの経過時間を出す
    static func begin(_ name: String) {
        installObserverIfNeeded()
        count += 1
        label = "\(name)#\(count)"
        start = CFAbsoluteTimeGetCurrent()
        write("\(label) begin switch=\(AppSettings.switchesToASCIIOnOpen ? "on" : "off")")
        watchMainThread()
    }

    static func mark(_ event: String) {
        write("\(label) +\(elapsed())ms \(event)")
    }

    /// `body` にかかった時間も出す
    @discardableResult
    static func measure<T>(_ event: String, _ body: () -> T) -> T {
        let before = CFAbsoluteTimeGetCurrent()
        let result = body()
        let took = String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - before) * 1000)
        write("\(label) +\(elapsed())ms \(event) took=\(took)ms")
        return result
    }

    private static func write(_ text: String) {
        logger.log("\(text, privacy: .public)")
    }

    private static func elapsed() -> String {
        String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    /// 1 秒間、10ms ごとにメインスレッドが動いているか確かめる。40ms 以上止まっていたらログに出す
    private static func watchMainThread() {
        lastTick = CFAbsoluteTimeGetCurrent()
        tickerUntil = lastTick + 1
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.01, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = CFAbsoluteTimeGetCurrent()
                let gap = (now - lastTick) * 1000
                if gap > 40 {
                    write("\(label) +\(elapsed())ms main thread blocked \(String(format: "%.0f", gap))ms")
                }
                lastTick = now
                if now > tickerUntil {
                    ticker?.invalidate()
                    ticker = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// 入力方法が実際に切り替わったとき（日本語入力から届く通知）
    private static func installObserverIfNeeded() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                write("\(label) +\(elapsed())ms input source changed to \(currentSourceID())")
            }
        }
    }

    private static func currentSourceID() -> String {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(current, kTISPropertyInputSourceID)
        else { return "?" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

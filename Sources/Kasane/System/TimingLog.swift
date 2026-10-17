import AppKit
import Carbon
import os

/// 一時的な計測用。かなのときに履歴ウインドウの開閉が遅い原因を調べる（原因がわかって直したら消す）。
///
/// 開く・閉じるごとに、その始まりからの経過時間をログに出す。あわせて次も出す:
/// - キーを押してから Kasane に届くまでの時間
/// - ウインドウが実際に画面に出た・消えた時刻
/// - 入力方法が実際に切り替わった時刻
/// - メインスレッドが止まっていた時間（起動中ずっと見る）
/// 見るとき: `log show --last 5m --predicate 'subsystem == "io.github.kazuya-tanimoto.kasane"' --style compact`
@MainActor
enum TimingLog {
    /// 閉じるときに比べる条件。閉じた順に交互に変える
    enum CloseCondition: String {
        /// ふだんどおり（0.1 秒でフェードアウトしてから隠す）
        case fade
        /// 検索欄のフォーカスを外してから、フェードアウトして隠す
        case unfocusFirst

        static func forClose(_ index: Int) -> CloseCondition {
            index % 2 == 0 ? .fade : .unfocusFirst
        }
    }

    private static let logger = Logger(subsystem: "io.github.kazuya-tanimoto.kasane", category: "timing")
    private static var start = CFAbsoluteTimeGetCurrent()
    private static var label = "-"
    private static var count = 0
    private static var ticker: Timer?
    private static var lastTick = CFAbsoluteTimeGetCurrent()
    private static var observer: NSObjectProtocol?

    /// 起動時に呼ぶ。入力方法の切り替えの通知と、メインスレッドの見張りを始める
    static func startWatching() {
        installObserverIfNeeded()
        watchMainThread()
        write("started switch=\(AppSettings.switchesToASCIIOnOpen ? "on" : "off")")
    }

    /// 開く・閉じるの始まり。ここからの経過時間を出す
    static func begin(_ name: String) {
        count += 1
        label = "\(name)#\(count)"
        start = CFAbsoluteTimeGetCurrent()
        write("\(label) begin switch=\(AppSettings.switchesToASCIIOnOpen ? "on" : "off")")
    }

    /// キーを押してから Kasane に届くまでの時間。`eventTime` は起動してからの秒数（`NSEvent.timestamp` と同じ）
    static func keyDelivered(_ name: String, eventTime: TimeInterval) {
        let delay = String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - eventTime) * 1000)
        write("key \(name) delivered \(delay)ms after it was pressed")
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

    /// Kasane が持っているウインドウを全部出す（AppKit のウインドウと、画面に出ているウインドウの番号）
    static func listWindows(_ when: String) {
        for window in NSApp.windows {
            write("\(label) \(when) NSWindow #\(window.windowNumber) \(type(of: window)) visible=\(window.isVisible) level=\(window.level.rawValue) frame=\(window.frame)")
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in all where (info[kCGWindowOwnerPID as String] as? Int32) == pid {
            let number = info[kCGWindowNumber as String] ?? "?"
            let onScreen = info[kCGWindowIsOnscreen as String] ?? false
            let layer = info[kCGWindowLayer as String] ?? "?"
            let bounds = info[kCGWindowBounds as String] ?? "?"
            write("\(label) \(when) CGWindow #\(number) onScreen=\(onScreen) layer=\(layer) bounds=\(bounds)")
        }
    }

    private static func write(_ text: String) {
        logger.log("\(text, privacy: .public)")
    }

    private static func elapsed() -> String {
        String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    /// 10ms ごとにメインスレッドが動いているか確かめる。40ms 以上止まっていたらログに出す
    private static func watchMainThread() {
        guard ticker == nil else { return }
        lastTick = CFAbsoluteTimeGetCurrent()
        let timer = Timer(timeInterval: 0.01, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = CFAbsoluteTimeGetCurrent()
                let gap = (now - lastTick) * 1000
                if gap > 40 {
                    write("\(label) +\(elapsed())ms main thread blocked \(String(format: "%.0f", gap))ms")
                }
                lastTick = now
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

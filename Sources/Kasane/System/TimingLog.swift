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
    /// 比べる条件。起動してから開いた順に、4 回ずつ変える（20 回を過ぎたら、ふだんどおり）
    enum Condition: String {
        /// ふだんどおり（開く直前に英数キー、閉じたあとにかなキー）
        case current
        /// 英数に切り替えない（閉じたあとも戻さない）
        case noSwitch
        /// 開く直前に英数キーを送るが、閉じたあとにかなに戻さない
        case noRestore
        /// 英数キーを送り、英数に変わったのを確かめてからウインドウを出す
        case waitBeforeShow
        /// ふだんどおりで、App Nap（使っていないアプリの動きを抑える macOS の仕組み）を止める
        case noAppNap

        static let order: [Condition] = [.current, .noSwitch, .noRestore, .waitBeforeShow, .noAppNap]
        static let timesEach = 4

        static func forOpen(_ index: Int) -> Condition {
            let block = index / timesEach
            return block < order.count ? order[block] : .current
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

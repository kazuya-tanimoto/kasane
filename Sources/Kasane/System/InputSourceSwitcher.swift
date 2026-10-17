import AppKit
import Carbon

/// 履歴ウインドウを開いている間だけ、日本語入力をオフ（英数）にする。
///
/// Kasane はローマ字で日本語の項目も検索できるので、英数のまま打てば大半の検索ができる。
/// 閉じたら開く前の入力方法に戻す。ウインドウは前のアプリを前面に残したまま開くので、
/// 戻さないと貼り付け先のアプリまで英数のままになる。
/// 日本語入力へは かなキー で戻すので、戻るのは「ひらがな」（開く前がカタカナなどでも）。
///
/// 切り替えは、利用者が 英数 / かな キーを押したときと同じキーを送って行う。
/// 入力方法を選び直す API（TISSelectInputSource）は日本語入力との切り替えに時間がかかり、
/// ウインドウの開閉が目に見えて遅くなったため（2026-10-17、Mac で確認）。
/// 英数 / かな キーは日本語入力（ことえり、Google 日本語入力など）が自分で処理する。
///
/// キーは Kasane のウインドウではなく、前面にある作業中のアプリに送る。Kasane のウインドウで
/// 日本語入力を切り替えると、その処理を待つ間ウインドウの表示が遅れたため（2026-10-17、Mac で確認）。
/// 日本語入力の英数 / かなは全部のアプリで共通なので、作業中のアプリで切り替えれば Kasane でも英数になる。
/// `defaults write io.github.kazuya-tanimoto.kasane switchesToASCIIOnOpen -bool false` で切り替えをやめられる
@MainActor
final class InputSourceSwitcher {
    /// 開いたときに日本語入力などがオンだったか。nil なら開いていない
    private var wasNonASCII: Bool?

    private var switchObserver: NSObjectProtocol?
    private var waitID = 0

    /// ウインドウを出す直前に呼ぶ（キーは前面にある作業中のアプリの日本語入力が受け取る）。
    /// 英数キーを送ったら true を返し、英数に変わったら（0.3 秒たっても変わらなければそこで）`onSwitched` を呼ぶ
    @discardableResult
    func switchToASCII(onSwitched: @escaping (_ switched: Bool) -> Void) -> Bool {
        guard wasNonASCII == nil, AppSettings.switchesToASCIIOnOpen else { return false }
        let nonASCII = !Self.isCurrentASCII()
        wasNonASCII = nonASCII
        guard nonASCII else { return false }
        // 切り替わった知らせを取りこぼさないよう、キーを送る前に待ち始める
        waitForSwitch(timeout: 0.3, onSwitched)
        Self.post(key: CGKeyCode(kVK_JIS_Eisu))
        return true
    }

    private func waitForSwitch(timeout: TimeInterval, _ done: @escaping (Bool) -> Void) {
        stopWaiting()
        waitID += 1
        let id = waitID
        var finished = false
        // 前に待ち始めた分が後から終わっても、今の待ちには触らない
        let finish: (Bool) -> Void = { [weak self] switched in
            guard let self, !finished, self.waitID == id else { return }
            finished = true
            self.stopWaiting()
            done(switched)
        }
        switchObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { finish(true) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            MainActor.assumeIsolated { finish(false) }
        }
    }

    private func stopWaiting() {
        if let switchObserver {
            DistributedNotificationCenter.default().removeObserver(switchObserver)
        }
        switchObserver = nil
    }

    /// ウインドウを閉じたあとに呼ぶ（キーは前面に戻ったアプリの日本語入力が受け取る）
    func restore() {
        guard let wasNonASCII else { return }
        self.wasNonASCII = nil
        if wasNonASCII {
            // ウインドウの中でかなキーを押していても、もう一度押すだけなので変わらない
            Self.post(key: CGKeyCode(kVK_JIS_Kana))
        } else if !Self.isCurrentASCII() {
            // 開く前は英数で、ウインドウの中でかなキーを押したときだけ戻す
            Self.post(key: CGKeyCode(kVK_JIS_Eisu))
        }
    }

    /// 前面にある、Kasane 以外のアプリ
    private static var workingAppPID: pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return app.processIdentifier
    }

    private static func isCurrentASCII() -> Bool {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(current, kTISPropertyInputSourceIsASCIICapable)
        else { return true }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    /// 作業中のアプリで英数 / かな キーを 1 回押したことにする。
    /// 作業中のアプリがなければ、キーウインドウに送る。アクセシビリティ権限がないと送れない（そのときは何もしない）
    private static func post(key: CGKeyCode) {
        let pid = workingAppPID
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Paster.syntheticEventMarker)
            if let pid {
                event.postToPid(pid)
            } else {
                event.post(tap: .cgSessionEventTap)
            }
        }
    }
}

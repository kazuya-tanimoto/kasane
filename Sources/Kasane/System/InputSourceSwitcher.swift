import AppKit
import Carbon

/// 履歴ウインドウを開いている間だけ、日本語入力をオフ（英数）にする。
///
/// Kasane はローマ字で日本語の項目も検索できるので、英数のまま打てば大半の検索ができる。
/// 閉じたら開く前の入力方法に戻す。ウインドウは前のアプリを前面に残したまま開くので、
/// 戻さないと貼り付け先のアプリまで英数のままになる。
///
/// 切り替えは、利用者が 英数 / かな キーを押したときと同じキーを送って行う。
/// 入力方法を選び直す API（TISSelectInputSource）は日本語入力との切り替えに時間がかかり、
/// ウインドウの開閉が目に見えて遅くなったため（2026-10-17、Mac で確認）。
/// 英数 / かな キーは日本語入力（ことえり、Google 日本語入力など）が自分で処理する。
/// ただし、かな入力のまま開くと表示に遅れが出ることがある（2026-10-17 調査中）。
/// `defaults write io.github.kazuya-tanimoto.kasane switchesToASCIIOnOpen -bool false` で切り替えをやめられる
@MainActor
final class InputSourceSwitcher {
    /// 開いたときに日本語入力などがオンだったか。nil なら開いていない
    private var wasNonASCII: Bool?

    /// ウインドウがキーウインドウになった直後に呼ぶ（送ったキーをウインドウの日本語入力が受け取る）
    func switchToASCII() {
        guard wasNonASCII == nil, AppSettings.switchesToASCIIOnOpen else { return }
        let nonASCII = !Self.isCurrentASCII()
        wasNonASCII = nonASCII
        if nonASCII {
            Self.post(key: CGKeyCode(kVK_JIS_Eisu))
        }
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

    private static func isCurrentASCII() -> Bool {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(current, kTISPropertyInputSourceIsASCIICapable)
        else { return true }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    /// 英数 / かな キーを 1 回押したことにする。アクセシビリティ権限がないと送れない（そのときは何もしない）
    private static func post(key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Paster.syntheticEventMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}

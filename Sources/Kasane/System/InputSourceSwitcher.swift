import AppKit
import Carbon

/// 履歴ウインドウを開いている間だけ、日本語入力をオフ（英数）にする。
///
/// Kasane はローマ字で日本語の項目も検索できるので、英数のまま打てば大半の検索ができる。
/// 閉じたら開く前の入力方法に戻す。ウインドウは前のアプリを前面に残したまま開くので、
/// 戻さないと貼り付け先のアプリまで英数のままになる
@MainActor
final class InputSourceSwitcher {
    /// 開く前の入力方法。閉じたときに戻す
    private var saved: TISInputSource?

    func switchToASCII() {
        guard saved == nil, let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        saved = current
        guard !Self.bool(current, kTISPropertyInputSourceIsASCIICapable),
              let ascii = Self.asciiSource(near: current)
        else { return }
        let status = TISSelectInputSource(ascii)
        if status != noErr {
            NSLog("Kasane: TISSelectInputSource failed (%d)", status)
        }
    }

    func restore() {
        guard let saved else { return }
        self.saved = nil
        // ウインドウの中でかなキーなどで切り替えていても、開く前の入力方法に戻す
        if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           Self.string(current, kTISPropertyInputSourceID) == Self.string(saved, kTISPropertyInputSourceID) {
            return
        }
        TISSelectInputSource(saved)
    }

    /// 切り替え先の英数の入力方法。同じ日本語入力の「英字」があればそれを選ぶ
    /// （ABC などに切り替えると、メニューバーの入力方法そのものが変わってしまうため）
    private static func asciiSource(near current: TISInputSource) -> TISInputSource? {
        let filter = [
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceIsEnabled as String: true,
        ] as CFDictionary
        let bundleID = string(current, kTISPropertyBundleID)
        if bundleID != nil, let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() {
            let sources = list as! [TISInputSource]
            let sameMethod = sources.first { source in
                string(source, kTISPropertyBundleID) == bundleID
                    && string(source, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String)
                    && bool(source, kTISPropertyInputSourceIsASCIICapable)
            }
            if let sameMethod { return sameMethod }
        }
        return TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func bool(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}

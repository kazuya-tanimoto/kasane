import AppKit
import ApplicationServices

enum Permissions {
    enum PasteboardAccess {
        /// システム設定で「許可」になっている
        case allowed
        /// 読むたびに確認アラートが出る
        case ask
        /// 拒否されている（履歴を取れない）
        case denied
        /// まだ一度もアラートが出ていない。システム設定にも Kasane が表示されない
        case notDetermined
    }

    // MARK: - アクセシビリティ（自動ペーストと FIFO/LIFO の ⌘V 検知）

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 許可を求めるシステムのダイアログを出す（許可済みなら何もしない）
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    // MARK: - 他のアプリからのペースト（macOS 15.4 以降のクリップボードのプライバシー保護）

    static var pasteboardAccess: PasteboardAccess {
        switch NSPasteboard.general.accessBehavior {
        case .alwaysAllow: return .allowed
        case .alwaysDeny: return .denied
        case .ask: return .ask
        case .default: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// クリップボードを一度読んで、確認アラートを出す。
    /// これで Kasane がシステム設定の一覧に表示され、「許可」を選べるようになる
    static func triggerPasteboardPrompt() {
        _ = NSPasteboard.general.string(forType: .string)
    }

    static func openPasteboardSettings() {
        // 項目を直接開く URL は公開されていないので、見つからなければプライバシーとセキュリティの画面が開く
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}

import AppKit
import SwiftUI

/// 設定のウインドウ。AppKit のウインドウに SwiftUI の画面を載せる（設定画面の仕組みの設計 settings-implementation-2026-10-22.md §2 の A）。
///
/// Kasane は Dock に出ないアプリなので、開いたときに前面に来ないと、後ろに隠れて「開かない」と感じる。
/// まず `NSApp.activate()` で前に出し、前に出なかったときだけ、開いている間だけ Dock に出るアプリにする
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: SettingsWindow?
    private let makeContent: () -> AnyView
    /// 前に出すために、一時的に Dock に出るアプリにしたか。閉じたら戻す
    private var promotedToRegular = false

    init(content: @escaping () -> AnyView) {
        makeContent = content
    }

    var isVisible: Bool { window?.isVisible ?? false }
    var isKey: Bool { window?.isKeyWindow ?? false }

    /// ウインドウの名前（開いているタブの名前にする。Apple の Human Interface Guidelines「Settings」）
    var title: String {
        get { window?.title ?? "" }
        set { window?.title = newValue }
    }

    func show() {
        if window == nil {
            let window = SettingsWindow(contentViewController: NSHostingController(rootView: makeContent()))
            // しまう・広げるのボタンは押せない見た目にする（設定のウインドウの慣習）
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // 前に出たかは、すぐには分からない（macOS が次の描画のあとに決める）ので、少し待ってから確かめる
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.bringToFrontIfHidden()
        }
    }

    func close() {
        window?.close()
    }

    /// ほかのアプリの後ろに開いてしまったら、Dock に出るアプリにしてから前に出し直す
    private func bringToFrontIfHidden() {
        guard let window, window.isVisible else { return }
        if NSApp.isActive && window.isKeyWindow {
            NSLog("Kasane: settings window came to front with activate()")
            return
        }
        NSLog("Kasane: settings window stayed behind; showing Kasane in the Dock while it is open")
        promotedToRegular = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // .regular にして activate() しても前に出ないことがある（Apple の開発者フォーラムの報告、PRレビュー調べ）
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        if promotedToRegular {
            promotedToRegular = false
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// メニューバーにメニューを出さないので、⌘W や、入力欄の ⌘C・⌘V などをここで受け取る
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let characters = event.charactersIgnoringModifiers?.lowercased() {
            if characters == "w", flags.isDisjoint(with: [.shift, .option, .control]) {
                performClose(nil)
                return true
            }
            if let action = HistoryPanelController.editAction(characters, flags: flags),
               NSApp.sendAction(action, to: nil, from: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

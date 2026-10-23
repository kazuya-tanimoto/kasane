import AppKit
import KasaneCore
import KasaneStore

/// メニューバーのアイコンとメニュー
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var showHistory: () -> Void
        var toggleQueue: (QueueMode) -> Void
        var showSettings: () -> Void
        var showOnboarding: () -> Void
    }

    struct Shortcuts {
        var history: String
        var fifo: String
        var lifo: String
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let actions: Actions
    /// メニューは開くたびに作り直すので、変えれば次に開いたときから出る
    var shortcuts: Shortcuts
    private var queueMode: QueueMode?
    private var queueCount = 0

    init(actions: Actions, shortcuts: Shortcuts) {
        self.actions = actions
        self.shortcuts = shortcuts
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        update(queueMode: nil, count: 0)
    }

    /// FIFO / LIFO モード中は、アイコンを変えて残り件数を出す
    func update(queueMode: QueueMode?, count: Int) {
        self.queueMode = queueMode
        queueCount = count
        guard let button = statusItem.button else { return }
        switch queueMode {
        case nil:
            button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Kasane")
            button.title = ""
            button.toolTip = "Kasane"
        case .fifo?:
            button.image = NSImage(systemSymbolName: "arrow.right.to.line", accessibilityDescription: "FIFO")
            button.title = " FIFO \(count)"
            button.toolTip = "FIFO モード（残り \(count) 件）"
        case .lifo?:
            button.image = NSImage(systemSymbolName: "arrow.uturn.left", accessibilityDescription: "LIFO")
            button.title = " LIFO \(count)"
            button.toolTip = "LIFO モード（残り \(count) 件）"
        }
        button.imagePosition = .imageLeading
    }

    // メニューを開くたびに作り直す（状態を常に正しく出すため）。
    // 設定は設定画面にまとめ、メニューは履歴と FIFO / LIFO を開くためのものにする（2026-10-22 決定。settings-screen §5）
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("履歴を開く  \(shortcuts.history)", #selector(showHistory)))
        menu.addItem(.separator())

        let fifoTitle = queueMode == .fifo ? "FIFO モードを終了（残り \(queueCount) 件）" : "FIFO モードを開始"
        menu.addItem(item("\(fifoTitle)  \(shortcuts.fifo)", #selector(toggleFIFO)))
        let lifoTitle = queueMode == .lifo ? "LIFO モードを終了（残り \(queueCount) 件）" : "LIFO モードを開始"
        menu.addItem(item("\(lifoTitle)  \(shortcuts.lifo)", #selector(toggleLIFO)))
        menu.addItem(.separator())

        let settings = item("設定…", #selector(showSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        if !(Permissions.isAccessibilityTrusted && Permissions.pasteboardAccess == .allowed) {
            menu.addItem(item("⚠︎ 許可の設定が必要です…", #selector(showOnboarding)))
        }
        menu.addItem(.separator())

        let about = NSMenuItem(title: "Kasane \(AppInfo.version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        let quit = NSMenuItem(title: "Kasane を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showHistory() { actions.showHistory() }
    @objc private func toggleFIFO() { actions.toggleQueue(.fifo) }
    @objc private func toggleLIFO() { actions.toggleQueue(.lifo) }
    @objc private func showSettings() { actions.showSettings() }
    @objc private func showOnboarding() { actions.showOnboarding() }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static let repositoryURL = URL(string: "https://github.com/kazuya-tanimoto/kasane")!
}

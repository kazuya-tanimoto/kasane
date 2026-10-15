import AppKit
import KasaneCore
import KasaneStore

/// メニューバーのアイコンとメニュー
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var showHistory: () -> Void
        var toggleQueue: (QueueMode) -> Void
        var setSortOrder: (SortOrder) -> Void
        var setHistoryLimit: (Int) -> Void
        var showOnboarding: () -> Void
        var clearHistory: () -> Void
    }

    struct Shortcuts {
        var history: String
        var fifo: String
        var lifo: String
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let actions: Actions
    private let shortcuts: Shortcuts
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

    // メニューを開くたびに作り直す（状態を常に正しく出すため）
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("履歴を開く  \(shortcuts.history)", #selector(showHistory)))
        menu.addItem(.separator())

        let fifoTitle = queueMode == .fifo ? "FIFO モードを終了（残り \(queueCount) 件）" : "FIFO モードを開始"
        menu.addItem(item("\(fifoTitle)  \(shortcuts.fifo)", #selector(toggleFIFO)))
        let lifoTitle = queueMode == .lifo ? "LIFO モードを終了（残り \(queueCount) 件）" : "LIFO モードを開始"
        menu.addItem(item("\(lifoTitle)  \(shortcuts.lifo)", #selector(toggleLIFO)))
        menu.addItem(.separator())

        let sortMenu = NSMenu()
        for order in SortOrder.allCases {
            let entry = item(order.displayName, #selector(selectSortOrder(_:)))
            entry.representedObject = order.rawValue
            entry.state = AppSettings.sortOrder == order ? .on : .off
            sortMenu.addItem(entry)
        }
        let sortItem = NSMenuItem(title: "並び順", action: nil, keyEquivalent: "")
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)

        let limitMenu = NSMenu()
        for limit in AppSettings.historyLimitOptions {
            let entry = item("\(limit.formatted()) 件", #selector(selectHistoryLimit(_:)))
            entry.representedObject = limit
            entry.state = AppSettings.historyLimit == limit ? .on : .off
            limitMenu.addItem(entry)
        }
        let limitItem = NSMenuItem(title: "履歴の保存件数", action: nil, keyEquivalent: "")
        limitItem.submenu = limitMenu
        menu.addItem(limitItem)

        let login = item("ログイン時に起動", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let permissionsTitle = Permissions.isAccessibilityTrusted && Permissions.pasteboardAccess == .allowed
            ? "権限の設定…" : "⚠︎ 権限の設定が必要です…"
        menu.addItem(item(permissionsTitle, #selector(showOnboarding)))
        menu.addItem(item("履歴を削除（ピン留め以外）…", #selector(clearHistory)))
        menu.addItem(.separator())

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let about = NSMenuItem(title: "Kasane \(version)", action: nil, keyEquivalent: "")
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
    @objc private func showOnboarding() { actions.showOnboarding() }
    @objc private func clearHistory() { actions.clearHistory() }
    @objc private func toggleLoginItem() { LoginItem.setEnabled(!LoginItem.isEnabled) }

    @objc private func selectSortOrder(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let order = SortOrder(rawValue: raw) else { return }
        actions.setSortOrder(order)
    }

    @objc private func selectHistoryLimit(_ sender: NSMenuItem) {
        guard let limit = sender.representedObject as? Int else { return }
        actions.setHistoryLimit(limit)
    }
}

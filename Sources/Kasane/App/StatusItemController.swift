import AppKit
import KasaneCore
import KasaneStore

/// メニューバーのアイコンとメニュー
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var showHistory: () -> Void
        var toggleQueue: (QueueMode) -> Void
        var setSortOrder: (HistorySortOrder) -> Void
        var setHistoryLimit: (Int) -> Void
        var setHUDPosition: (HUDPosition) -> Void
        var setHUDFontSize: (Double) -> Void
        var resetHistoryWindowFrame: () -> Void
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
        for order in HistorySortOrder.allCases {
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

        menu.addItem(appearanceItem())

        let linkPreview = item("URL のページ情報を取得", #selector(toggleLinkPreviews))
        linkPreview.state = AppSettings.fetchesLinkPreviews ? .on : .off
        linkPreview.toolTip = "URL のプレビューで、ページのタイトルと画像を取りに行きます"
        menu.addItem(linkPreview)

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

    /// アクセントカラー・透明度・ぼかし・小さな表示の位置と文字の大きさ。設定画面ができるまではメニューで変える
    private func appearanceItem() -> NSMenuItem {
        let appearance = AppearanceSettings.shared
        let menu = NSMenu()

        menu.addItem(header("アクセントカラー"))
        for accent in AccentColor.allCases {
            let title = accent == .default ? "\(accent.displayName)（標準）" : accent.displayName
            let entry = item(title, #selector(selectAccent(_:)))
            entry.representedObject = accent.rawValue
            entry.state = appearance.accent == accent ? .on : .off
            entry.indentationLevel = 1
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(header("不透明度"))
        for percent in stride(from: 10, through: 100, by: 10) {
            let entry = item("\(percent)%", #selector(selectOpacity(_:)))
            entry.representedObject = percent
            entry.state = Int((appearance.opacity * 100).rounded()) == percent ? .on : .off
            entry.indentationLevel = 1
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(header(WindowBlur.isAvailable ? "背景のぼかし（半径）" : "背景のぼかし"))
        for radius in BlurPreset.radii {
            // 半径を指定できない macOS では、ぼかしあり / なしだけになる
            if !WindowBlur.isAvailable && radius != 0 && radius != BlurPreset.defaultRadius { continue }
            let title: String
            if radius == 0 {
                title = "なし"
            } else if !WindowBlur.isAvailable {
                title = "あり"
            } else {
                title = radius == BlurPreset.defaultRadius ? "\(radius)（標準）" : "\(radius)"
            }
            let entry = item(title, #selector(selectBlur(_:)))
            entry.representedObject = radius
            entry.state = (WindowBlur.isAvailable ? appearance.blurRadius == radius : (appearance.blurRadius > 0) == (radius > 0)) ? .on : .off
            entry.indentationLevel = 1
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(header("FIFO / LIFO の小さな表示の位置"))
        for position in HUDPosition.allCases {
            let entry = item(position.displayName, #selector(selectHUDPosition(_:)))
            entry.representedObject = position.rawValue
            entry.state = AppSettings.hudPosition == position ? .on : .off
            entry.indentationLevel = 1
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(header("FIFO / LIFO の小さな表示の文字の大きさ"))
        for size in [11.0, 12, 14, 16, 18, 20] {
            let entry = item(size == 12 ? "12 pt（標準）" : "\(Int(size)) pt", #selector(selectHUDFontSize(_:)))
            entry.representedObject = size
            entry.state = AppSettings.hudFontSize == size ? .on : .off
            entry.indentationLevel = 1
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(item("履歴ウインドウの位置と大きさを元に戻す", #selector(resetHistoryWindowFrame)))

        let appearanceItem = NSMenuItem(title: "見た目", action: nil, keyEquivalent: "")
        appearanceItem.submenu = menu
        return appearanceItem
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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
        guard let raw = sender.representedObject as? String, let order = HistorySortOrder(rawValue: raw) else { return }
        actions.setSortOrder(order)
    }

    @objc private func selectOpacity(_ sender: NSMenuItem) {
        guard let percent = sender.representedObject as? Int else { return }
        AppearanceSettings.shared.opacity = Double(percent) / 100
    }

    @objc private func selectBlur(_ sender: NSMenuItem) {
        guard let radius = sender.representedObject as? Int else { return }
        AppearanceSettings.shared.blurRadius = radius
    }

    @objc private func selectAccent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let accent = AccentColor(rawValue: raw) else { return }
        AppearanceSettings.shared.accent = accent
    }

    @objc private func selectHUDFontSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Double else { return }
        actions.setHUDFontSize(size)
    }

    @objc private func toggleLinkPreviews() { AppSettings.fetchesLinkPreviews.toggle() }
    @objc private func resetHistoryWindowFrame() { actions.resetHistoryWindowFrame() }

    @objc private func selectHUDPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let position = HUDPosition(rawValue: raw) else { return }
        actions.setHUDPosition(position)
    }

    @objc private func selectHistoryLimit(_ sender: NSMenuItem) {
        guard let limit = sender.representedObject as? Int else { return }
        actions.setHistoryLimit(limit)
    }
}

import AppKit
import KasaneCore
import KasaneStore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// ショートカットの初期値（仮）。どれも `defaults write` で変えられる。設定画面は v1 の仕上げで作る
    static let defaultHotKeys = (history: "ctrl+cmd+v", fifo: "ctrl+opt+cmd+f", lifo: "ctrl+opt+cmd+l")

    private var store: HistoryStore!
    private var model: HistoryModel!
    private let writer = PasteboardWriter()
    private var monitor: PasteboardMonitor!
    private var panel: HistoryPanelController!
    private var queue: QueueController!
    private lazy var queueHUD = QueueHUDController()
    private var statusItem: StatusItemController!
    private var onboarding: OnboardingWindowController?
    /// 保存の処理（ハッシュ、サムネイル、ローマ字、DB への書き込み）は順番どおりにバックグラウンドで行う
    private let processingQueue = DispatchQueue(label: "io.github.kazuya-tanimoto.kasane.capture", qos: .utility)

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try HistoryStore(directory: AppSettings.dataDirectory)
        } catch {
            let alert = NSAlert()
            alert.messageText = "履歴のデータベースを開けませんでした"
            alert.informativeText = "\(AppSettings.dataDirectory.path)\n\(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        model = HistoryModel(store: store, sortOrder: AppSettings.sortOrder)
        model.onActivate = { [weak self] id, action in self?.activate(itemID: id, action: action) }
        model.onDelete = { [weak self] ids in self?.queue.remove(itemIDs: Set(ids)) }
        model.load()

        panel = HistoryPanelController(model: model)

        queue = QueueController(store: store, writer: writer)
        queue.isHistoryPanelKey = { [weak self] in self?.panel.isKey ?? false }
        queue.onChange = { [weak self] in self?.queueDidChange() }
        queue.onPasted = { [weak self] id in self?.recordPaste(itemID: id) }

        monitor = PasteboardMonitor(writer: writer)
        monitor.onCapture = { [weak self] raw in self?.process(raw) }
        monitor.start()

        let shortcuts = registerHotKeys()
        statusItem = StatusItemController(
            actions: .init(
                showHistory: { [weak self] in self?.panel.show() },
                toggleQueue: { [weak self] mode in self?.toggleQueue(mode) },
                setSortOrder: { [weak self] order in self?.setSortOrder(order) },
                setHistoryLimit: { [weak self] limit in self?.setHistoryLimit(limit) },
                setHUDPosition: { [weak self] position in
                    AppSettings.hudPosition = position
                    self?.updateQueueHUD()
                },
                setHUDFontSize: { [weak self] size in
                    AppSettings.hudFontSize = size
                    self?.updateQueueHUD()
                },
                resetHistoryWindowFrame: { [weak self] in self?.panel.resetFrame() },
                showOnboarding: { [weak self] in self?.showOnboarding() },
                clearHistory: { [weak self] in self?.confirmClearHistory() }
            ),
            shortcuts: shortcuts
        )

        if !AppSettings.hasCompletedOnboarding
            || !Permissions.isAccessibilityTrusted
            || Permissions.pasteboardAccess != .allowed {
            showOnboarding()
        }
    }

    // MARK: - ショートカット

    private func registerHotKeys() -> StatusItemController.Shortcuts {
        let center = HotKeyCenter.shared
        func register(_ name: String, _ fallback: String, _ handler: @escaping () -> Void) -> String {
            let spec = AppSettings.hotKey(name, default: fallback)
            guard let hotKey = HotKeyCenter.HotKey(spec) ?? HotKeyCenter.HotKey(fallback) else { return "" }
            if !center.register(hotKey, handler: handler) {
                NSLog("Kasane: hotkey \(spec) is already in use")
                return "（\(hotKey.displayString) は使用中）"
            }
            return hotKey.displayString
        }
        let keys = Self.defaultHotKeys
        return .init(
            history: register("history", keys.history) { [weak self] in self?.panel.toggle() },
            fifo: register("fifo", keys.fifo) { [weak self] in self?.toggleQueue(.fifo) },
            lifo: register("lifo", keys.lifo) { [weak self] in self?.toggleQueue(.lifo) }
        )
    }

    // MARK: - 履歴の保存

    private func process(_ raw: RawCapture) {
        let store = self.store!
        let limit = AppSettings.historyLimit
        processingQueue.async { [weak self] in
            guard let capture = CaptureBuilder.build(raw) else { return }
            do {
                let result = try store.save(capture, limit: limit)
                let candidate = SearchCandidate(
                    id: result.item.id ?? -1,
                    text: result.item.text ?? result.item.title,
                    romaji: result.item.romaji
                )
                // 保存した順に反映する（FIFO のキューの順番を守るため、Task ではなく main キューを使う）
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.didSave(result, candidate: candidate)
                    }
                }
            } catch {
                NSLog("Kasane: failed to save clipboard item: \(error)")
            }
        }
    }

    private func didSave(_ result: HistoryStore.SaveResult, candidate: SearchCandidate) {
        model.upsert(result.item, candidate: candidate)
        model.remove(ids: result.prunedIDs)
        queue.remove(itemIDs: Set(result.prunedIDs))
        if let id = result.item.id {
            queue.didCapture(itemID: id)
        }
    }

    // MARK: - ペースト

    private func activate(itemID: Int64, action: PasteAction) {
        guard let item = try? store.item(id: itemID),
              let representations = try? store.representations(itemID: itemID)
        else { return }
        // FIFO / LIFO 中の ⌥⏎ は、選んだ項目をキューに追加するだけ（クリップボードは変えない）。
        // ウインドウは閉じず、続けて選んで追加できるようにする（追加したことは隅の小さいウインドウでわかる）
        if action == .copyOnly, queue.mode != nil {
            queue.didCapture(itemID: itemID)
            return
        }

        // 画像などテキストのない項目は、⇧⏎ でもそのまま貼り付ける
        let plainTextOnly = action == .plainText && item.text != nil && item.kind != .file
        writer.write(representations, plainText: item.text, plainTextOnly: plainTextOnly)

        panel.hide { [weak self] in
            guard action != .copyOnly else { return }
            guard Permissions.isAccessibilityTrusted else {
                // 権限がなければクリップボードに入れるところまで。案内を出す
                self?.showOnboarding()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.pasteDelay) {
                MainActor.assumeIsolated { TimingLog.measure("post ⌘V") { Paster.postCommandV() } }
            }
        }
        if action != .copyOnly {
            recordPaste(itemID: itemID)
        }
    }

    private func recordPaste(itemID: Int64) {
        try? store.recordPaste(itemID: itemID)
        model.didPaste(id: itemID)
    }

    // MARK: - FIFO / LIFO

    private func toggleQueue(_ mode: QueueMode) {
        if !queue.toggle(mode) {
            showOnboarding()
        }
    }

    private func queueDidChange() {
        let current = queue.queue
        statusItem?.update(queueMode: current?.mode, count: current?.count ?? 0)
        if model.queueMode != current?.mode {
            model.queueMode = current?.mode
        }
        updateQueueHUD()
    }

    /// モード中は、履歴ウインドウの開閉に関係なく、画面の隅にキューの全件を出す
    private func updateQueueHUD() {
        let current = queue.queue
        let titles = current?.itemsInPasteOrder.map { model.summary(id: $0)?.title ?? "?" } ?? []
        queueHUD.update(mode: current?.mode, titles: titles)
    }

    // MARK: - メニュー

    private func setSortOrder(_ order: HistorySortOrder) {
        AppSettings.sortOrder = order
        model.setSortOrder(order)
    }

    private func setHistoryLimit(_ limit: Int) {
        AppSettings.historyLimit = limit
        let pruned = (try? store.prune(limit: limit)) ?? []
        model.remove(ids: pruned)
        queue.remove(itemIDs: Set(pruned))
    }

    private func showOnboarding() {
        if onboarding == nil {
            let controller = OnboardingWindowController()
            controller.onClose = { AppSettings.hasCompletedOnboarding = true }
            onboarding = controller
        }
        onboarding?.show()
    }

    private func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "履歴を削除しますか？"
        alert.informativeText = "ピン留めした項目は残ります。この操作は取り消せません。"
        alert.addButton(withTitle: "削除")
        alert.addButton(withTitle: "キャンセル")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ids = (try? store.deleteAll(keepPinned: true)) ?? []
        model.remove(ids: ids)
        queue.remove(itemIDs: Set(ids))
    }
}

import AppKit
import Combine
import KasaneCore
import KasaneStore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: HistoryStore!
    private var model: HistoryModel!
    private let writer = PasteboardWriter()
    private var monitor: PasteboardMonitor!
    private var panel: HistoryPanelController!
    private var queue: QueueController!
    private lazy var queueHUD = QueueHUDController()
    private var statusItem: StatusItemController!
    private var shortcuts: ShortcutController!
    private var onboarding: OnboardingWindowController?
    private var settingsModel: SettingsModel?
    private var settingsWindow: SettingsWindowController?
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
        model.load()

        panel = HistoryPanelController(model: model)

        queue = QueueController(store: store, writer: writer)
        queue.isHistoryPanelKey = { [weak self] in self?.panel.isKey ?? false }
        queue.onChange = { [weak self] in self?.queueDidChange() }
        queue.onPasted = { [weak self] id in self?.recordPaste(itemID: id) }

        monitor = PasteboardMonitor(writer: writer)
        monitor.onCapture = { [weak self] raw in self?.process(raw) }
        monitor.start()

        shortcuts = ShortcutController { [weak self] slot in self?.hotKeyPressed(slot) }
        panel.onOpenSettings = { [weak self] in self?.showSettings() }
        statusItem = StatusItemController(
            actions: .init(
                showHistory: { [weak self] in self?.panel.show() },
                toggleQueue: { [weak self] mode in self?.toggleQueue(mode) },
                showSettings: { [weak self] in self?.showSettings() },
                showOnboarding: { [weak self] in self?.showOnboarding() }
            ),
            shortcuts: menuShortcuts()
        )
        shortcuts.onChange = { [weak self] in
            guard let self else { return }
            self.statusItem.shortcuts = self.menuShortcuts()
            self.settingsModel?.shortcutsDidChange()
        }

        if !AppSettings.hasCompletedOnboarding
            || !Permissions.isAccessibilityTrusted
            || Permissions.pasteboardAccess != .allowed {
            showOnboarding()
        }
    }

    // MARK: - ショートカット

    private func hotKeyPressed(_ slot: ShortcutSlot) {
        switch slot {
        case .history: panel.toggle()
        case .fifo: toggleQueue(.fifo)
        case .lifo: toggleQueue(.lifo)
        }
    }

    private func menuShortcuts() -> StatusItemController.Shortcuts {
        .init(
            history: shortcuts.menuTitle(.history),
            fifo: shortcuts.menuTitle(.fifo),
            lifo: shortcuts.menuTitle(.lifo)
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
        if let id = result.item.id {
            queue.didCapture(itemID: id)
            fetchLinkForQueue(result.item)
        }
    }

    /// FIFO / LIFO 中にキューへ入った URL は、コピーした時点でページ情報を取りに行く（2026-10-30 決定。requirements.md §3.3）
    private func fetchLinkForQueue(_ item: ClipItem) {
        guard queue.mode != nil, item.kind == .url, let id = item.id else { return }
        model.links.fetchNow(itemID: id)
    }

    // MARK: - ペースト

    private func activate(itemID: Int64, action: PasteAction) {
        guard let item = try? store.item(id: itemID),
              let representations = try? store.representations(itemID: itemID)
        else { return }
        // FIFO / LIFO 中の ⌘⏎ は、選んだ項目をキューに追加するだけ（クリップボードは変えない）。
        // ウインドウは閉じず、続けて選んで追加できるようにする（追加したことは隅の小さいウインドウでわかる）
        if action == .copyOnly, queue.mode != nil {
            queue.didCapture(itemID: itemID)
            fetchLinkForQueue(item)
            return
        }

        // 画像などテキストのない項目は、⇧⏎ でもそのまま貼り付ける
        let plainTextOnly = action == .plainText && item.text != nil && item.kind != .file
        writer.write(representations, plainText: item.text, plainTextOnly: plainTextOnly)
        let outcome = action.outcome(openedOverKasane: panel.openedOverKasane)
        if outcome.movesToTop {
            let now = Date()
            try? store.recordReuse(itemID: itemID, now: now)
            model.didReuse(id: itemID, at: now)
        }

        panel.hide { [weak self] in
            guard outcome.sendsCommandV else { return }
            guard Permissions.isAccessibilityTrusted else {
                // 権限がなければクリップボードに入れるところまで。案内を出す
                self?.showOnboarding()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.pasteDelay) {
                Paster.postCommandV()
            }
        }
        if outcome.countsPaste {
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
        let titles = current?.itemsInPasteOrder.map(\.title) ?? []
        queueHUD.update(mode: current?.mode, titles: titles)
    }

    // MARK: - 設定

    private func showSettings() {
        if settingsWindow == nil {
            let model = SettingsModel(
                actions: .init(
                    setSortOrder: { [weak self] order in self?.setSortOrder(order) },
                    setHistoryLimit: { [weak self] limit, completion in
                        guard let self else { return completion(false) }
                        self.setHistoryLimit(limit, completion: completion)
                    },
                    clearHistory: { [weak self] in self?.confirmClearHistory() },
                    unpinnedCount: { [weak self] in self?.model.unpinnedCount ?? 0 },
                    // 履歴の一覧が変わったあとで数え直す（objectWillChange は変わる前に届くので、次の回で読む）
                    historyChanges: self.model.objectWillChange
                        .map { _ in () }
                        .receive(on: RunLoop.main)
                        .eraseToAnyPublisher(),
                    queueHUDChanged: { [weak self] in self?.updateQueueHUD() },
                    fetchesLinkPreviewsChanged: { [weak self] enabled in self?.model.links.setEnabled(enabled) },
                    resetHistoryWindowFrame: { [weak self] in self?.panel.resetFrame() },
                    isHistoryWindowStandard: { [weak self] in self?.panel.isFrameStandard ?? true }
                ),
                shortcuts: shortcuts
            )
            let window = SettingsWindowController { SettingsTabController(model: model) }
            window.onShow = {
                model.refresh()
                model.permissions.startPolling()
                model.startObservingHistory()
            }
            window.onBecomeKey = { model.refresh() }
            window.onClose = {
                model.permissions.stopPolling()
                model.stopObservingHistory()
            }
            settingsModel = model
            settingsWindow = window
        }
        settingsWindow?.show()
    }

    private func setSortOrder(_ order: HistorySortOrder) {
        AppSettings.sortOrder = order
        model.setSortOrder(order)
    }

    /// 保存件数を変える。今のピン留め以外の件数が新しい件数を超えるときは、削除する前に確認を出す。
    /// ポップアップの選び間違いで削除した履歴は戻せないため（settings-screen-2026-10-22.md §3「履歴」）。キャンセルなら false を返す
    private func setHistoryLimit(_ limit: Int, completion: @escaping (Bool) -> Void) {
        let apply = { [weak self] in
            guard let self else { return }
            AppSettings.historyLimit = limit
            // 確認を出している間にコピーされた分も含め、押した時点の履歴を新しい件数まで減らす
            let pruned = (try? self.store.prune(limit: limit)) ?? []
            self.model.remove(ids: pruned)
        }
        let deleting = ((try? store.unpinnedCount()) ?? 0) - limit
        guard deleting > 0 else {
            apply()
            return completion(true)
        }
        let alert = NSAlert()
        // 思いがけず履歴が消える操作なので、注意の記号を出す（アプリのアイコンが小さく重なる）。「履歴を削除…」の確認には付けない
        // （2026-10-24 Kazuya さんが決定。design/delete-alerts-hig-2026-10-24.md §7）
        alert.alertStyle = .critical
        alert.messageText = "古い履歴 \(deleting.formatted()) 件を削除しますか？"
        alert.informativeText = "保存件数を \(limit.formatted()) 件にするため、超えた分を古いものから削除します。"
            + "削除した履歴は戻せません。ピン留めした項目は削除されません。"
        // 右が「削除」、左が「キャンセル」。どちらも既定のボタンにしない（⏎ では押されない）。Esc はキャンセル。
        // 選んだのは件数で、削除そのものではないので、削除のボタンを赤くする（Apple の Alerts）
        let delete = alert.addButton(withTitle: "削除")
        let cancel = alert.addButton(withTitle: "キャンセル")
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        cancel.keyEquivalent = "\u{1b}"
        presentInSettings(alert) { response in
            guard response == .alertFirstButtonReturn else { return completion(false) }
            apply()
            completion(true)
        }
    }

    private func showOnboarding() {
        if onboarding == nil {
            let controller = OnboardingWindowController()
            controller.onClose = { AppSettings.hasCompletedOnboarding = true }
            onboarding = controller
        }
        onboarding?.show()
    }

    /// 「履歴を削除…」の確認。削除そのものを選んだ操作なので、「削除」を既定のボタン（⏎）にし、赤くしない（Apple の Alerts。
    /// settings-screen-2026-10-22.md §3「履歴」）
    private func confirmClearHistory() {
        let count = (try? store.unpinnedCount()) ?? 0
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "履歴 \(count.formatted()) 件を削除しますか？"
        alert.informativeText = "削除した履歴は戻せません。ピン留めした項目と、FIFO / LIFO のキューは削除されません。"
        // 最初に足したボタンが右端で、⏎ の既定になる
        alert.addButton(withTitle: "削除")
        let cancel = alert.addButton(withTitle: "キャンセル")
        cancel.keyEquivalent = "\u{1b}"
        presentInSettings(alert) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            // 確認を出している間にコピーされた分も含め、押した時点のピン留め以外を全部削除する
            let ids = (try? self.store.deleteAll(keepPinned: true)) ?? []
            self.model.remove(ids: ids)
        }
    }

    private func presentInSettings(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let settingsWindow {
            settingsWindow.present(alert, completion: completion)
        } else {
            NSApp.activate()
            completion(alert.runModal())
        }
    }
}

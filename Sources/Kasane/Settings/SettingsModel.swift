import AppKit
import Combine
import KasaneCore
import KasaneStore
import UniformTypeIdentifiers

/// 設定画面の値。変えたらその場で保存して反映する（「適用」ボタンなし。settings-implementation-2026-10-22.md §2）。
/// 見た目（色・不透明度・ぼかし・履歴ウインドウの文字の大きさ）は `AppearanceSettings` が持ち、ここでは扱わない
@MainActor
final class SettingsModel: ObservableObject {
    /// 保存のほかに、アプリのほかの所を動かす必要がある操作
    struct Actions {
        var setSortOrder: (HistorySortOrder) -> Void
        /// 保存件数を変える。減らして削除が起きるときは確認を出し、変えたかどうかを返す（キャンセルなら false）
        var setHistoryLimit: (Int, @escaping (Bool) -> Void) -> Void
        var clearHistory: () -> Void
        /// ピン留め以外の履歴の件数（「履歴を削除…」を押せるか）
        var unpinnedCount: () -> Int
        /// 履歴が変わったとき（コピー、削除、ピン留め）に届く
        var historyChanges: AnyPublisher<Void, Never>
        /// 小さいウインドウの位置か文字の大きさが変わった
        var queueHUDChanged: () -> Void
        /// URL のタイトルと画像を取りに行くスイッチが変わった（オフなら取っている途中のものもやめる）
        var fetchesLinkPreviewsChanged: (Bool) -> Void
        var resetHistoryWindowFrame: () -> Void
        /// 履歴ウインドウの位置と大きさが標準のままか
        var isHistoryWindowStandard: () -> Bool
    }

    struct ExcludedApp: Identifiable, Equatable {
        var bundleID: String
        var name: String
        var url: URL?
        var id: String { bundleID }
    }

    let actions: Actions
    let shortcuts: ShortcutController
    let permissions = PermissionState()
    let appearance = AppearanceSettings.shared

    @Published var loginEnabled = LoginItem.isEnabled
    @Published private(set) var historyLimit = AppSettings.historyLimit
    @Published private(set) var sortOrder = AppSettings.sortOrder
    @Published private(set) var fetchesLinkPreviews = AppSettings.fetchesLinkPreviews
    @Published private(set) var excludedApps: [ExcludedApp] = []
    @Published private(set) var searchLooseness = AppSettings.searchLooseness
    @Published private(set) var switchesToASCII = AppSettings.switchesToASCIIOnOpen
    @Published private(set) var hudSide = AppSettings.hudSide
    @Published private(set) var hudTextSize = AppSettings.hudTextSize
    @Published private(set) var isHistoryWindowStandard = true
    /// ピン留め以外の履歴があるか。0 件なら「履歴を削除…」を押せなくする
    @Published private(set) var hasUnpinnedHistory = true
    /// ショートカットの表示を描き直すため（キーが変わったとき、登録欄の待ちが終わったとき）
    @Published private(set) var shortcutsVersion = 0
    private var historyObservation: AnyCancellable?

    init(actions: Actions, shortcuts: ShortcutController) {
        self.actions = actions
        self.shortcuts = shortcuts
        reloadExcludedApps()
    }

    /// 設定ウインドウを開くたびに、ほかの所で変わったかもしれない値を読み直す
    func refresh() {
        loginEnabled = LoginItem.isEnabled
        historyLimit = AppSettings.historyLimit
        sortOrder = AppSettings.sortOrder
        isHistoryWindowStandard = actions.isHistoryWindowStandard()
        hasUnpinnedHistory = actions.unpinnedCount() > 0
        permissions.refresh()
        shortcutsVersion += 1
    }

    /// 設定ウインドウを開いている間だけ、履歴の件数の変化を見る。
    /// 開いている間もコピーや削除で件数は変わるので、「履歴を削除…」を押せるかをすぐ変える（settings-screen-2026-10-22.md §3「履歴」）
    func startObservingHistory() {
        historyObservation = actions.historyChanges.sink { [weak self] in
            guard let self else { return }
            let hasUnpinned = self.actions.unpinnedCount() > 0
            if hasUnpinned != self.hasUnpinnedHistory { self.hasUnpinnedHistory = hasUnpinned }
        }
    }

    func stopObservingHistory() {
        historyObservation = nil
    }

    // MARK: - 一般

    func setLoginEnabled(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        // 登録に失敗したときは元の表示に戻す
        loginEnabled = LoginItem.isEnabled
    }

    // MARK: - 履歴

    func setHistoryLimit(_ limit: Int) {
        guard limit != historyLimit else { return }
        actions.setHistoryLimit(limit) { [weak self] changed in
            guard let self else { return }
            if changed {
                self.historyLimit = limit
            } else {
                // キャンセルしたら、ポップアップを前の件数に戻す
                self.objectWillChange.send()
            }
        }
    }

    func setSortOrder(_ order: HistorySortOrder) {
        sortOrder = order
        actions.setSortOrder(order)
    }

    func setFetchesLinkPreviews(_ value: Bool) {
        fetchesLinkPreviews = value
        AppSettings.fetchesLinkPreviews = value
        actions.fetchesLinkPreviewsChanged(value)
    }

    func addExcludedApp(bundleID: String) {
        var ids = AppSettings.excludedBundleIDs
        ids.insert(bundleID)
        AppSettings.excludedBundleIDs = ids
        reloadExcludedApps()
    }

    func removeExcludedApp(bundleID: String) {
        var ids = AppSettings.excludedBundleIDs
        ids.remove(bundleID)
        AppSettings.excludedBundleIDs = ids
        reloadExcludedApps()
    }

    /// 「開いているアプリ」: Dock に出ているアプリから、Kasane と追加済みを除いて名前順
    func runningAppsToAdd() -> [ExcludedApp] {
        let excluded = AppSettings.excludedBundleIDs
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> ExcludedApp? in
                guard let id = app.bundleIdentifier, id != own, !excluded.contains(id), seen.insert(id).inserted else { return nil }
                return ExcludedApp(bundleID: id, name: app.localizedName ?? id, url: app.bundleURL)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 「ほかのアプリを選ぶ…」: アプリのファイルを選ばせて追加する
    func chooseAppToAdd() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "追加"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }
        addExcludedApp(bundleID: bundleID)
    }

    private func reloadExcludedApps() {
        excludedApps = AppSettings.excludedBundleIDs.map { id in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url.map { FileManager.default.displayName(atPath: $0.path) }
                .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
            return ExcludedApp(bundleID: id, name: name ?? id, url: url)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - 検索

    func setSearchLooseness(_ value: SearchLooseness) {
        searchLooseness = value
        AppSettings.searchLooseness = value
    }

    func setSwitchesToASCII(_ value: Bool) {
        switchesToASCII = value
        AppSettings.switchesToASCIIOnOpen = value
    }

    // MARK: - 外観

    func setHUDSide(_ side: HUDSide) {
        hudSide = side
        AppSettings.hudSide = side
        actions.queueHUDChanged()
    }

    func setHUDTextSize(_ level: TextSizeLevel) {
        hudTextSize = level
        AppSettings.hudTextSize = level
        actions.queueHUDChanged()
    }

    func resetHistoryWindowFrame() {
        actions.resetHistoryWindowFrame()
        isHistoryWindowStandard = actions.isHistoryWindowStandard()
    }

    func historyTextSizeChanged() {
        // 文字の大きさで標準の大きさが変わるので、「標準に戻す」を出すかを決め直す
        isHistoryWindowStandard = actions.isHistoryWindowStandard()
    }

    static let standardOpacity = 0.7

    var isBackgroundStandard: Bool {
        Int((appearance.opacity * 100).rounded()) == Int(Self.standardOpacity * 100)
            && appearance.blurRadius == BlurPreset.defaultRadius
    }

    func resetBackground() {
        appearance.opacity = Self.standardOpacity
        appearance.blurRadius = BlurPreset.defaultRadius
    }

    // MARK: - ショートカット

    func shortcutsDidChange() {
        shortcutsVersion += 1
    }
}

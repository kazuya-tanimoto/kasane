import AppKit
import KasaneCore
import KasaneStore

/// UserDefaults に保存する設定。設定画面（メニューバーの「設定…」、履歴ウインドウで ⌘,）で変える
enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    static let historyLimitOptions = [100, 500, 1_000, 5_000, 10_000]

    /// 履歴の保存件数（ピン留めは含めない）
    static var historyLimit: Int {
        get {
            let value = defaults.integer(forKey: "historyLimit")
            return value > 0 ? value : 1_000
        }
        set { defaults.set(newValue, forKey: "historyLimit") }
    }

    static var sortOrder: HistorySortOrder {
        get { HistorySortOrder(rawValue: defaults.string(forKey: "sortOrder") ?? "") ?? .recent }
        set { defaults.set(newValue.rawValue, forKey: "sortOrder") }
    }

    /// 検索のゆるさ（要件書 §3.2。2026-10-22 決定）
    static var searchLooseness: SearchLooseness {
        get { SearchLooseness(rawValue: defaults.string(forKey: "searchLooseness") ?? "") ?? .default }
        set { defaults.set(newValue.rawValue, forKey: "searchLooseness") }
    }

    /// 履歴に残さないアプリのバンドルID
    static var excludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "excludedBundleIDs") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "excludedBundleIDs") }
    }

    /// クリップボードの変更を確認する間隔（秒）
    static var pollInterval: TimeInterval {
        let value = defaults.double(forKey: "pollInterval")
        return value > 0 ? value : 0.3
    }

    /// ウインドウを閉じてから ⌘V を送るまでの待ち時間（秒）。元のアプリにフォーカスが戻るのを待つ
    static var pasteDelay: TimeInterval {
        let value = defaults.double(forKey: "pasteDelay")
        return value > 0 ? value : 0.05
    }

    /// 履歴ウインドウを開いたら英数に切り替え、閉じたら戻すか（初期値はオン）
    static var switchesToASCIIOnOpen: Bool {
        get { defaults.object(forKey: "switchesToASCIIOnOpen") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "switchesToASCIIOnOpen") }
    }

    /// プレビューの下に詳細を出すか（⌘I）
    static var showsDetails: Bool {
        get { defaults.bool(forKey: "showsDetails") }
        set { defaults.set(newValue, forKey: "showsDetails") }
    }

    /// 履歴ウインドウの不透明度（0〜1）。背景のぼかしの上に重ねる色の濃さ
    static var panelOpacity: Double {
        get {
            let value = defaults.object(forKey: "panelOpacity") as? Double ?? 0.7
            return min(max(value, 0), 1)
        }
        set { defaults.set(newValue, forKey: "panelOpacity") }
    }

    /// 背景のぼかしの半径（0 でぼかしなし）
    static var blurRadius: Int {
        get {
            let value = defaults.object(forKey: "blurRadius") as? Int ?? BlurPreset.defaultRadius
            return min(max(value, 0), BlurPreset.maxRadius)
        }
        set { defaults.set(newValue, forKey: "blurRadius") }
    }

    static var accentColor: AccentColor {
        get { AccentColor(rawValue: defaults.string(forKey: "accentColor") ?? "") ?? .default }
        set { defaults.set(newValue.rawValue, forKey: "accentColor") }
    }

    /// 履歴ウインドウの一覧とプレビューの文字の大きさ（2026-10-22 決定）
    static var historyTextSize: TextSizeLevel {
        get { TextSizeLevel(rawValue: defaults.string(forKey: "historyTextSize") ?? "") ?? .default }
        set { defaults.set(newValue.rawValue, forKey: "historyTextSize") }
    }

    /// FIFO / LIFO 中の小さいウインドウの文字の大きさ（2026-10-22 決定）。
    /// 前の版では pt（11〜20）で選んでいたので、その設定があれば一番近い段階にする
    static var hudTextSize: TextSizeLevel {
        get {
            if let level = TextSizeLevel(rawValue: defaults.string(forKey: "hudTextSize") ?? "") {
                return level
            }
            if let old = defaults.object(forKey: "hudFontSize") as? Double {
                return .nearest(toHUDFontSize: CGFloat(old))
            }
            return .default
        }
        set { defaults.set(newValue.rawValue, forKey: "hudTextSize") }
    }

    /// FIFO / LIFO の帯の幅（12pt のときの値。2026-10-30 決定）。nil なら初期の幅。
    /// 帯の内側の端をドラッグして変える。文字の大きさの倍率を掛けて出す（`QueueBandLayout`）
    static var hudBandWidth: CGFloat? {
        get { (defaults.object(forKey: "hudBandWidth") as? Double).map { CGFloat($0) } }
        set { defaults.set(newValue.map { Double($0) }, forKey: "hudBandWidth") }
    }

    /// 小さいウインドウの文字の大きさ（pt）
    static var hudFontSize: Double { Double(hudTextSize.hudFontSize) }

    /// URL のプレビューでページのタイトルと画像を取りに行くか。
    /// 初期値はオン（2026-10-30 決定。10/15 はオフだった）: リンクを見分けやすくするため。一度きりのリンクが気になる人はオフにする
    static var fetchesLinkPreviews: Bool {
        get { defaults.object(forKey: "fetchesLinkPreviews") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fetchesLinkPreviews") }
    }

    /// 履歴ウインドウの大きさ。nil なら既定の大きさ
    static var historyWindowSize: NSSize? {
        get { (defaults.string(forKey: "historyWindowSize")).map(NSSizeFromString) }
        set { defaults.set(newValue.map(NSStringFromSize), forKey: "historyWindowSize") }
    }

    /// 履歴ウインドウの中心の、画面の中心からのずれ。nil なら既定の位置（中央の少し上）。
    /// 画面ごとではなくずれで覚えるので、別の画面で開いても同じあたりに出る
    static var historyWindowOffset: NSPoint? {
        get { (defaults.string(forKey: "historyWindowOffset")).map(NSPointFromString) }
        set { defaults.set(newValue.map(NSStringFromPoint), forKey: "historyWindowOffset") }
    }

    /// 小さいウインドウ（画面の端の帯）を出す側（左は左端、右は右端）。前の版の 4 つの角の設定は、初めて読むときに 1 回だけ読み替える
    static var hudSide: HUDSide {
        get {
            if let side = HUDSide(rawValue: defaults.string(forKey: "hudSide") ?? "") {
                return side
            }
            let side = HUDSide(legacyPosition: defaults.string(forKey: "hudPosition"))
            defaults.set(side.rawValue, forKey: "hudSide")
            return side
        }
        set { defaults.set(newValue.rawValue, forKey: "hudSide") }
    }

    /// 設定ウインドウで最後に見たタブ。次に開いたときに出す
    static var settingsTab: String? {
        get { defaults.string(forKey: "settingsTab") }
        set { defaults.set(newValue, forKey: "settingsTab") }
    }

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    /// グローバルショートカット。前の版の `defaults write <bundle id> hotkey.history "opt+v"` の設定は、初めて読むときに 1 回だけ読み替える
    static func shortcut(_ slot: ShortcutSlot) -> Shortcut {
        shortcutStore.shortcut(slot)
    }

    static func setShortcut(_ shortcut: Shortcut, for slot: ShortcutSlot) {
        shortcutStore.setShortcut(shortcut, for: slot)
    }

    private static var shortcutStore: ShortcutStore {
        ShortcutStore(read: { defaults.string(forKey: $0) }, write: { defaults.set($1, forKey: $0) })
    }

    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kasane", isDirectory: true)
    }
}

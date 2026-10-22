import AppKit
import KasaneCore
import KasaneStore

/// UserDefaults に保存する設定。設定画面は v1 の仕上げで作るので、MVP ではメニューと `defaults` コマンドで変える
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
        Set(defaults.stringArray(forKey: "excludedBundleIDs") ?? [])
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
        defaults.object(forKey: "switchesToASCIIOnOpen") as? Bool ?? true
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

    /// FIFO / LIFO 中の小さいウインドウの文字の大きさ（pt）
    static var hudFontSize: Double {
        get {
            let value = defaults.object(forKey: "hudFontSize") as? Double ?? 12
            return min(max(value, 10), 24)
        }
        set { defaults.set(newValue, forKey: "hudFontSize") }
    }

    /// URL のプレビューでページのタイトルと画像を取りに行くか。
    /// 初期値はオフ: 社内のリンクやログイン用の一度きりのリンクに、コピーしただけでアクセスしないようにする
    static var fetchesLinkPreviews: Bool {
        get { defaults.bool(forKey: "fetchesLinkPreviews") }
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

    static var hudPosition: HUDPosition {
        get { HUDPosition(rawValue: defaults.string(forKey: "hudPosition") ?? "") ?? .topRight }
        set { defaults.set(newValue.rawValue, forKey: "hudPosition") }
    }

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    /// グローバルショートカット。`defaults write <bundle id> hotkey.history "opt+v"` の形で上書きできる
    static func hotKey(_ name: String, default value: String) -> String {
        defaults.string(forKey: "hotkey.\(name)") ?? value
    }

    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kasane", isDirectory: true)
    }
}

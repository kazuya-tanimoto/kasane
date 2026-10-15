import Foundation
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

    /// プレビューの下に詳細を出すか（⌘I）
    static var showsDetails: Bool {
        get { defaults.bool(forKey: "showsDetails") }
        set { defaults.set(newValue, forKey: "showsDetails") }
    }

    /// 履歴ウインドウの不透明度（0.3〜1.0）。背景のぼかしの上に重ねる色の濃さ
    static var panelOpacity: Double {
        get {
            let value = defaults.object(forKey: "panelOpacity") as? Double ?? 0.7
            return min(max(value, 0.3), 1.0)
        }
        set { defaults.set(newValue, forKey: "panelOpacity") }
    }

    static var blurLevel: BlurLevel {
        get { BlurLevel(rawValue: defaults.integer(forKey: "blurLevel") - 1) ?? .standard }
        set { defaults.set(newValue.rawValue + 1, forKey: "blurLevel") }
    }

    static var hudPosition: HUDPosition {
        get { HUDPosition(rawValue: defaults.string(forKey: "hudPosition") ?? "") ?? .topRight }
        set { defaults.set(newValue.rawValue, forKey: "hudPosition") }
    }

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    /// グローバルショートカット。`defaults write <bundle id> hotkey.history "ctrl+cmd+v"` の形で上書きできる
    static func hotKey(_ name: String, default value: String) -> String {
        defaults.string(forKey: "hotkey.\(name)") ?? value
    }

    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kasane", isDirectory: true)
    }
}

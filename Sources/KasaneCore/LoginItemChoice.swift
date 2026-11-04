import Foundation

/// 初回の案内の「ログイン時に起動」のチェック（requirements.md §3.8、2026-10-30 決定）
public enum LoginItemChoice {
    /// 案内を開いたときのチェック。初めて起動したときはオン、許可が外れて出し直すときは今の設定のまま
    public static func initialValue(hasCompletedOnboarding: Bool, currentlyEnabled: Bool) -> Bool {
        hasCompletedOnboarding ? currentlyEnabled : true
    }

    /// 案内を閉じたときに設定を変えるか。今と同じなら変えない
    /// （登録し直すたびに macOS が「ログイン項目が追加されました」の通知を出すことがあるため）
    public static func change(checked: Bool, currentlyEnabled: Bool) -> Bool? {
        checked == currentlyEnabled ? nil : checked
    }
}

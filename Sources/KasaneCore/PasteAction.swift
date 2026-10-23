import Foundation

/// 履歴ウインドウで項目を選んだときの操作
public enum PasteAction: Sendable {
    /// 元のアプリに自動ペーストする（⏎、⌘1〜9）
    case paste
    /// 書式なしで自動ペーストする（⇧⏎）
    case plainText
    /// クリップボードにコピーするだけ（⌘⏎）
    case copyOnly

    /// 選んだあとに何をするか。
    ///
    /// - Parameter openedOverKasane: 履歴ウインドウを開いたときに、一番前が Kasane のウインドウ（設定、初回の案内）だったか。
    ///   そのときはペースト先が Kasane 自身になり、ペーストする欄がないので、クリップボードに入れるだけにする。
    ///   実際にはペーストしていないので、回数にも数えない（「ペースト回数順」がずれないように。2026-10-22 決定）
    public func outcome(openedOverKasane: Bool) -> PasteOutcome {
        switch self {
        case .copyOnly:
            // ⌘C でコピーし直したときと同じく一番上に移す（2026-10-18 決定）
            return PasteOutcome(sendsCommandV: false, movesToTop: true, countsPaste: false)
        case .paste, .plainText:
            if openedOverKasane {
                return PasteOutcome(sendsCommandV: false, movesToTop: false, countsPaste: false)
            }
            // ペーストでは一番上に移さない。並びと ⌘ 番号が変わらないように（2026-10-18 決定）
            return PasteOutcome(sendsCommandV: true, movesToTop: false, countsPaste: true)
        }
    }
}

public struct PasteOutcome: Equatable, Sendable {
    /// 元のアプリに ⌘V を送るか
    public var sendsCommandV: Bool
    /// コピー日時を今にして一番上に移すか
    public var movesToTop: Bool
    /// ペーストした回数に数えるか
    public var countsPaste: Bool
}

import Foundation

public enum QueueMode: String, Sendable, CaseIterable {
    /// 先にコピーしたものから貼り付ける
    case fifo
    /// 後にコピーしたものから貼り付ける
    case lifo
}

extension QueueMode {
    /// メニューバーのメニューで、このモードの項目に出す言葉
    /// - Parameters:
    ///   - current: 今のモード。モード外なら nil
    ///   - count: キューの残り件数
    /// 別のモードの最中は、積んだものを残して順番だけ切り替えるので「切り替え」と出す
    /// （2026-11-05 Kazuya さんが OK「言葉を変えても良いですよ。実際の動きに合わせるってことですよね。」）
    public func menuTitle(current: QueueMode?, count: Int) -> String {
        let name = self == .fifo ? "FIFO" : "LIFO"
        switch current {
        case self: return "\(name) モードを終了（残り \(count) 件）"
        case nil: return "\(name) モードを開始"
        default: return "\(name) に切り替え"
        }
    }
}

/// FIFO / LIFO モードで積んだ項目のキュー。
///
/// クリップボードの操作は持たず、「次に貼り付けるのはどれか」だけを管理する。
public struct PasteQueue<Element: Equatable>: Equatable {
    public private(set) var mode: QueueMode
    public private(set) var items: [Element] = []

    public init(mode: QueueMode) {
        self.mode = mode
    }

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }

    /// 次の ⌘V で貼り付ける項目
    public var next: Element? {
        mode == .fifo ? items.first : items.last
    }

    /// 貼り付ける順に並べた中身（履歴ウインドウでの表示用）
    public var itemsInPasteOrder: [Element] {
        mode == .fifo ? items : items.reversed()
    }

    public mutating func push(_ element: Element) {
        items.append(element)
    }

    /// 積んだあとで中身を変える（並びは変えない）。後から作った縮小を足すときに使う
    public mutating func update(where match: (Element) -> Bool, _ change: (inout Element) -> Void) {
        for index in items.indices where match(items[index]) {
            change(&items[index])
        }
    }

    /// 積んだ中身はそのままで、貼る順番だけを変える（FIFO 中に LIFO のキーを押したときなど。2026-11-04 Kazuya さんが決定）。
    /// 中身はコピーした順に持っているので、モードを変えるだけで次に貼るものと並びが変わる
    public mutating func switchMode(to mode: QueueMode) {
        self.mode = mode
    }

    /// 次の項目を取り出す（貼り付けが済んだときに呼ぶ）
    @discardableResult
    public mutating func popNext() -> Element? {
        guard !items.isEmpty else { return nil }
        return mode == .fifo ? items.removeFirst() : items.removeLast()
    }
}

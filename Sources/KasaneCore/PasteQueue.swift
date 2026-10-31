import Foundation

public enum QueueMode: String, Sendable, CaseIterable {
    /// 先にコピーしたものから貼り付ける
    case fifo
    /// 後にコピーしたものから貼り付ける
    case lifo
}

/// FIFO / LIFO モードで積んだ項目のキュー。
///
/// クリップボードの操作は持たず、「次に貼り付けるのはどれか」だけを管理する。
public struct PasteQueue<Element: Equatable>: Equatable {
    public let mode: QueueMode
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

    /// 次の項目を取り出す（貼り付けが済んだときに呼ぶ）
    @discardableResult
    public mutating func popNext() -> Element? {
        guard !items.isEmpty else { return nil }
        return mode == .fifo ? items.removeFirst() : items.removeLast()
    }
}

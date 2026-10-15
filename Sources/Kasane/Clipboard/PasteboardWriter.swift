import AppKit
import KasaneStore

/// 履歴の項目をクリップボードに書き込む。
///
/// 書き込んだときの `changeCount` を覚えておき、監視側が「自分の書き込み」を新しいコピーと
/// 取り違えないようにする。
@MainActor
final class PasteboardWriter {
    private let pasteboard = NSPasteboard.general
    private var ownChangeCounts: [Int] = []

    func isOwnChange(_ changeCount: Int) -> Bool {
        ownChangeCounts.contains(changeCount)
    }

    /// - Parameters:
    ///   - representations: 保存しておいた型ごとのデータ。元の書式のまま貼り付けられる
    ///   - plainTextOnly: true なら書式を捨ててプレーンテキストだけを書く（⇧⏎）
    func write(_ representations: [Capture.Representation], plainText: String?, plainTextOnly: Bool) {
        pasteboard.clearContents()
        if plainTextOnly, let plainText {
            pasteboard.setString(plainText, forType: .string)
        } else {
            let groups = Dictionary(grouping: representations, by: \.itemIndex).sorted { $0.key < $1.key }
            let items = groups.map { _, reps -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for rep in reps {
                    item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type))
                }
                return item
            }
            if items.isEmpty, let plainText {
                pasteboard.setString(plainText, forType: .string)
            } else {
                pasteboard.writeObjects(items)
            }
        }
        ownChangeCounts.append(pasteboard.changeCount)
        if ownChangeCounts.count > 32 {
            ownChangeCounts.removeFirst(ownChangeCounts.count - 32)
        }
    }
}

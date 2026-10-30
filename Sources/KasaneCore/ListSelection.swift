import Foundation

/// 履歴ウインドウの一覧で、操作のあとにどの行を選ぶか（requirements.md §3.5）
public enum ListSelection {
    /// 削除したあとに選ぶ行。消す前にすぐ下にあった行、なければすぐ上の行、どちらもなければなし
    public static func afterRemoving<ID: Equatable>(_ id: ID, from list: [ID]) -> ID? {
        guard let index = list.firstIndex(of: id) else { return list.first }
        if index + 1 < list.count { return list[index + 1] }
        return index > 0 ? list[index - 1] : nil
    }
}

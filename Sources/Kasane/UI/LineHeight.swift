import AppKit

/// モックの行の高さ（CSS の line-height。文字の大きさの何倍か）を、SwiftUI の lineSpacing に直す
enum LineHeight {
    /// 行の間に足す高さ。システムの文字の標準の行の高さとの差（標準より狭くはしない）
    @MainActor
    static func spacing(multiple: CGFloat, fontSize: CGFloat) -> CGFloat {
        let natural = NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: fontSize))
        return max(0, fontSize * multiple - natural)
    }
}

import AppKit
import SwiftUI

/// モックの行の高さ（CSS の line-height。文字の大きさの何倍か）を SwiftUI で再現する。
/// CSS は、行の高さと文字の高さの差を、行の上と下に半分ずつ足す。
/// SwiftUI の lineSpacing は行と行の間にしか足さないので、まとまりの上と下にも半分ずつ余白を足す
enum LineHeight {
    /// 1 行ごとに足す高さ。システムの文字の標準の行の高さとの差（標準より狭くはしない）
    @MainActor
    static func extra(multiple: CGFloat, fontSize: CGFloat) -> CGFloat {
        max(0, fontSize * multiple - naturalHeight(fontSize: fontSize))
    }

    /// 標準の行の高さは文字の大きさごとに 1 回だけ測って覚える（一覧の行ごと・描くたびに NSLayoutManager を作らないため）
    @MainActor private static var naturalHeights: [CGFloat: CGFloat] = [:]
    @MainActor private static let layoutManager = NSLayoutManager()

    @MainActor
    private static func naturalHeight(fontSize: CGFloat) -> CGFloat {
        if let height = naturalHeights[fontSize] { return height }
        let height = layoutManager.defaultLineHeight(for: NSFont.systemFont(ofSize: fontSize))
        naturalHeights[fontSize] = height
        return height
    }
}

extension View {
    /// 行の高さを文字の大きさの `multiple` 倍にする（CSS の line-height と同じ置き方）
    func lineHeight(_ multiple: CGFloat, fontSize: CGFloat) -> some View {
        let extra = LineHeight.extra(multiple: multiple, fontSize: fontSize)
        return lineSpacing(extra).padding(.vertical, extra / 2)
    }
}

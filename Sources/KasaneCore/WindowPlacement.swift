import Foundation
#if canImport(CoreGraphics)
// macOS では CGRect の width や midX は CoreGraphics にあり、Foundation だけでは見えない
import CoreGraphics
#endif

/// 履歴ウインドウを置く位置と大きさの計算。AppKit に依存しないので Linux でもテストできる
public enum WindowPlacement {
    /// - Parameters:
    ///   - screen: 置く画面の使える範囲（メニューバーと Dock を除いた枠）
    ///   - savedSize: 前に変えた大きさ。nil なら `defaultSize`
    ///   - savedOffset: 画面の中心からウインドウの中心までのずれ。nil なら中心より少し上
    /// - Returns: 画面からはみ出さないように収めた枠
    public static func frame(
        in screen: CGRect,
        savedSize: CGSize?,
        savedOffset: CGPoint?,
        defaultSize: CGSize,
        minSize: CGSize
    ) -> CGRect {
        let wanted = savedSize ?? defaultSize
        // 画面が最小サイズより小さいときは画面に合わせる
        let size = CGSize(
            width: min(max(wanted.width, minSize.width), screen.width),
            height: min(max(wanted.height, minSize.height), screen.height)
        )
        let offset = savedOffset ?? CGPoint(x: 0, y: screen.height * 0.06)
        let origin = CGPoint(
            x: min(max(screen.midX + offset.x - size.width / 2, screen.minX), screen.maxX - size.width),
            y: min(max(screen.midY + offset.y - size.height / 2, screen.minY), screen.maxY - size.height)
        )
        return CGRect(origin: origin, size: size)
    }

    /// 保存する、画面の中心からウインドウの中心までのずれ
    public static func offset(of window: CGRect, in screen: CGRect) -> CGPoint {
        CGPoint(x: window.midX - screen.midX, y: window.midY - screen.midY)
    }
}

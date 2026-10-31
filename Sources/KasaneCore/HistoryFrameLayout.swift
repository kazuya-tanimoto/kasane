import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// 履歴ウインドウの枠（角・縁・影）の寸法。デザインモック「C案 改訂版」（Match のボード）の値
/// （border-radius 20px、border 1px、box-shadow 0 30px 80px 黒 35%）を、px をそのまま pt にして使う
/// （2026-10-31 決定。reviews/design-fix-2026-10-31/history-window-frame-padding-2026-10-31.md）
public enum HistoryFrameLayout {
    public static let cornerRadius: CGFloat = 20
    public static let borderWidth: CGFloat = 1
    /// 縁の色の白の不透明度。ダークは白 12%、ライトは白 70%
    public static func borderWhiteOpacity(dark: Bool) -> CGFloat { dark ? 0.12 : 0.70 }

    public static let shadowOffsetY: CGFloat = 30
    public static let shadowBlur: CGFloat = 80
    public static let shadowOpacity: CGFloat = 0.35
    /// 影を描く所の、ウインドウの周りの幅。CSS のぼかしは標準偏差がぼかしの半分のガウスなので、
    /// その 3 倍とずらした分で見えなくなる
    public static let shadowExtent: CGFloat = shadowOffsetY + shadowBlur * 1.5

    /// 角丸の外に残す、ほとんど透明な余白。端をつかんで大きさを変える所の、見える縁の外側の分（外 3pt の所がウインドウの中に入るよう 4）
    public static let resizeMargin: CGFloat = 4
    /// 端をつかめる所の幅（ウインドウの端から内へ）。見える縁の外 3pt から内 3pt まで。
    /// 縁なしのウインドウは、Mac に任せるとウインドウの端の内側 3pt ほどでしかつかめず、角の透明な所では斜めに大きさを変えられない。
    /// 前のシステムのウインドウは見える縁の外 3pt から内 3pt でつかめた（2026-10-31、CI の Mac で 1pt ずつ測った）ので、自分でつかむ所を作って合わせる
    public static let resizeEdge: CGFloat = resizeMargin + 3
    /// 角で斜めに大きさを変えられる所の、ウインドウの角からの長さ
    public static let resizeCorner: CGFloat = resizeMargin + 13

    /// ウインドウの中の、角丸の本体の四角
    public static func body(in window: CGRect) -> CGRect {
        window.insetBy(dx: resizeMargin, dy: resizeMargin)
    }

    /// 角丸の本体を囲むウインドウの四角（本体の周りに余白を足す）
    public static func window(aroundBody body: CGRect) -> CGRect {
        body.insetBy(dx: -resizeMargin, dy: -resizeMargin)
    }

    /// 本体を置ける画面の所。周りの余白を足したウインドウが画面に収まるよう、余白の分だけ内へ寄せる。
    /// 中心は画面と同じなので、中心からのずれで覚えた位置はそのまま使える
    public static func bodyArea(in screen: CGRect) -> CGRect {
        screen.insetBy(dx: resizeMargin, dy: resizeMargin)
    }

    /// 影だけを描く別のウインドウの位置。履歴ウインドウを `shadowExtent` だけ広げた四角
    public static func shadowFrame(window: CGRect) -> CGRect {
        window.insetBy(dx: -shadowExtent, dy: -shadowExtent)
    }

    /// 影のウインドウの中での、角丸の本体の四角（影はここを避けて外にだけ描く）
    public static func shadowCaster(inShadowOfSize size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: shadowExtent + resizeMargin, dy: shadowExtent + resizeMargin)
    }

    /// ウインドウのどの端をつかんだか
    public struct Edges: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let left = Edges(rawValue: 1)
        public static let right = Edges(rawValue: 2)
        public static let bottom = Edges(rawValue: 4)
        public static let top = Edges(rawValue: 8)
    }

    /// ウインドウの中の点（左下が原点）が、どの端をつかむ所か。つかむ所でなければ空
    public static func edges(at point: CGPoint, in size: CGSize) -> Edges {
        let bounds = CGRect(origin: .zero, size: size)
        guard bounds.contains(point) else { return [] }
        var result: Edges = []
        let nearLeft = point.x < resizeCorner, nearRight = point.x > size.width - resizeCorner
        let nearBottom = point.y < resizeCorner, nearTop = point.y > size.height - resizeCorner
        // 角は、2 つの端の近くが重なる所
        if (nearLeft || nearRight) && (nearBottom || nearTop) {
            result.insert(nearLeft ? .left : .right)
            result.insert(nearBottom ? .bottom : .top)
            return result
        }
        if point.x <= resizeEdge { result.insert(.left) }
        if point.x >= size.width - resizeEdge { result.insert(.right) }
        if point.y <= resizeEdge { result.insert(.bottom) }
        if point.y >= size.height - resizeEdge { result.insert(.top) }
        return result
    }

    /// つかんだ端を (dx, dy) 動かしたあとのウインドウの四角（画面の座標、左下が原点）。
    /// 最小の大きさより小さくはせず、そのときは反対側の端を動かさない
    public static func resized(_ frame: CGRect, edges: Edges, dx: CGFloat, dy: CGFloat, minSize: CGSize) -> CGRect {
        var result = frame
        if edges.contains(.right) {
            result.size.width = max(frame.width + dx, minSize.width)
        } else if edges.contains(.left) {
            result.size.width = max(frame.width - dx, minSize.width)
            result.origin.x = frame.maxX - result.width
        }
        if edges.contains(.top) {
            result.size.height = max(frame.height + dy, minSize.height)
        } else if edges.contains(.bottom) {
            result.size.height = max(frame.height - dy, minSize.height)
            result.origin.y = frame.maxY - result.height
        }
        return result
    }
}

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

    /// 角丸の外に残す、ほとんど透明な余白。縁なしのウインドウは、ウインドウの端の内側 1〜4pt ほどでしか
    /// 大きさを変えられず、角の透明な所では斜めに大きさを変えられない（2026-10-31、CI の Mac で確かめた）。
    /// 余白を付けると、つかめる所が見える縁の外 2pt から内 1pt になり、今のシステムのウインドウ（外 3pt から内 2pt）に近くなる
    public static let resizeMargin: CGFloat = 3

    /// ウインドウの中の、角丸の本体の四角
    public static func body(in window: CGRect) -> CGRect {
        window.insetBy(dx: resizeMargin, dy: resizeMargin)
    }

    /// 影だけを描く別のウインドウの位置。履歴ウインドウを `shadowExtent` だけ広げた四角
    public static func shadowFrame(window: CGRect) -> CGRect {
        window.insetBy(dx: -shadowExtent, dy: -shadowExtent)
    }

    /// 影のウインドウの中での、角丸の本体の四角（影はここを避けて外にだけ描く）
    public static func shadowCaster(inShadowOfSize size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: shadowExtent + resizeMargin, dy: shadowExtent + resizeMargin)
    }
}

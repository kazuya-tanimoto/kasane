import Foundation
#if canImport(CoreGraphics)
// macOS では CGFloat や CGRect の計算は CoreGraphics にあり、Foundation だけでは見えない
import CoreGraphics
#endif

/// FIFO / LIFO の小さいウインドウ（画面の端の帯）の大きさと位置（2026-10-30 決定。requirements.md §3.6）。
///
/// - 設定の「左 / 右」の側の画面の端にくっつけ、メニューバーの下から画面の下まで出す。Dock は避けずにかぶせる
///   （2026-10-30 Kazuya さんが決定「Dockにかぶせていいです」）
/// - 幅は内側の端のドラッグで変える。12pt のときの幅で覚え、文字の大きさの倍率を掛けて出す
/// - 最小（と初期）は今までの幅、最大はカードの本文が 1 行に全角 40 字になる幅（WCAG 1.4.8「40 if CJK」）
public enum QueueBandLayout {
    /// 12pt のときの、今までの幅。初期と最小に使う
    public static let baseWidth: CGFloat = 260
    /// 1 行に出す全角の字数の上限
    public static let maxCharacters: CGFloat = 40

    /// 余白など（12pt のときの値。倍率を掛けて使う）。カードの描画も同じ値を使う
    public enum Metrics {
        /// 帯の左右の余白
        public static let bandPadding: CGFloat = 10
        /// カードの中の左右の余白
        public static let cardPadding: CGFloat = 10
        /// 番号の丸の直径
        public static let numberDiameter: CGFloat = 18
        /// 番号の丸と中身の間
        public static let numberGap: CGFloat = 8
        /// 帯の内側の端の、ドラッグでつかめる幅（倍率は掛けない）
        public static let handleWidth: CGFloat = 6
    }

    /// 12pt のときを 1 とした倍率
    public static func scale(fontSize: CGFloat) -> CGFloat { fontSize / 12 }

    /// 本文の幅のほかに、帯の幅に要る分（余白と番号の丸）
    public static func chromeWidth(fontSize: CGFloat) -> CGFloat {
        let m = Metrics.self
        return (m.bandPadding * 2 + m.cardPadding * 2 + m.numberDiameter + m.numberGap) * scale(fontSize: fontSize)
    }

    public static func minWidth(fontSize: CGFloat, screen: CGRect) -> CGFloat {
        min(baseWidth * scale(fontSize: fontSize), screen.width)
    }

    /// 全角 1 字の幅は文字の大きさとほぼ同じなので、本文が 40 字になる幅。帯が画面からはみ出さないよう、画面の幅で止める
    public static func maxWidth(fontSize: CGFloat, screen: CGRect) -> CGFloat {
        let wanted = maxCharacters * fontSize + chromeWidth(fontSize: fontSize)
        return max(min(wanted, screen.width), minWidth(fontSize: fontSize, screen: screen))
    }

    /// 覚えた幅（12pt のときの値。nil なら初期）から、今の文字の大きさで出す幅
    public static func width(savedBaseWidth: CGFloat?, fontSize: CGFloat, screen: CGRect) -> CGFloat {
        let wanted = (savedBaseWidth ?? baseWidth) * scale(fontSize: fontSize)
        return clamp(wanted, fontSize: fontSize, screen: screen)
    }

    /// 帯を出せる範囲。画面全体からメニューバー（とカメラの出っ張り）の分だけを除く。
    /// Dock の分は除かない（visibleFrame は Dock の分も除くので、上端だけを使う）
    public static func bandArea(screenFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: visibleFrame.maxY - screenFrame.minY
        )
    }

    /// 出したときの枠。`screen` は `bandArea`
    public static func frame(side: HUDSide, width: CGFloat, screen: CGRect) -> CGRect {
        let x: CGFloat
        switch side {
        case .left: x = screen.minX
        case .right: x = screen.maxX - width
        }
        return CGRect(x: x, y: screen.minY, width: width, height: screen.height)
    }

    /// 内側の端をドラッグしたあとの幅。`deltaX` はつかんだ所からの横の動き（右が正）。
    /// 右に出した帯は左端をつかむので、左へ動かすと広がる
    public static func draggedWidth(
        from startWidth: CGFloat,
        deltaX: CGFloat,
        side: HUDSide,
        fontSize: CGFloat,
        screen: CGRect
    ) -> CGFloat {
        let wanted: CGFloat
        switch side {
        case .left: wanted = startWidth + deltaX
        case .right: wanted = startWidth - deltaX
        }
        return clamp(wanted, fontSize: fontSize, screen: screen)
    }

    /// 覚えるときの値（12pt のときの幅）
    public static func baseWidth(for width: CGFloat, fontSize: CGFloat) -> CGFloat {
        width / scale(fontSize: fontSize)
    }

    private static func clamp(_ width: CGFloat, fontSize: CGFloat, screen: CGRect) -> CGFloat {
        let lower = minWidth(fontSize: fontSize, screen: screen)
        let upper = maxWidth(fontSize: fontSize, screen: screen)
        return min(max(width, lower), upper)
    }
}

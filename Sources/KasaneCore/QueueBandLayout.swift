import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(CoreGraphics)
// macOS では CGFloat や CGRect の計算は CoreGraphics にあり、Foundation だけでは見えない
import CoreGraphics
#endif

/// FIFO / LIFO の小さいウインドウ（画面の端の帯）の大きさと位置（2026-10-30 決定。requirements.md §3.6）。
///
/// - 設定の「左 / 右」の側の画面の端にくっつけ、メニューバーの下から画面の下まで出す。Dock は避けずにかぶせる
///   （2026-10-30 Kazuya さんが決定「Dockにかぶせていいです」）
/// - 幅は内側の端のドラッグで変える。12pt のときの幅で覚え、文字の大きさの倍率を掛けて出す
/// - 最小（と初期）は今までの幅、最大はカードの本文が 1 行に全角 40 字になる幅（WCAG 1.4.8「40 if CJK」）。字の幅は測る
public enum QueueBandLayout {
    /// 12pt のときの、今までの幅。初期と最小に使う
    public static let baseWidth: CGFloat = 260
    /// 1 行に出す全角の字数の上限
    public static let maxCharacters: CGFloat = 40
    /// 最大の幅に足す余裕。本文の幅がちょうど 40 字分だと、描画の丸めで 39 字目で折り返すことがあるため。
    /// 全角 1 字より十分小さいので、41 字目は入らない
    public static let maxWidthSlack: CGFloat = 1

    /// 余白など（12pt のときの値。倍率を掛けて使う）。カードの描画も同じ値を使う。
    /// 値は合意したモック（デザインモックの QueueEdge、カードの案）の px を、本文の文字の大きさに合わせて換算したもの。
    /// モックの本文は 8.5px なので、12pt のときは px × 12 / 8.5
    public enum Metrics {
        /// モックの 1px が、12pt のときの何 pt か
        public static let mockPixel: CGFloat = 12 / 8.5
        /// 帯の上下左右の余白（モック 8px）
        public static let bandPadding: CGFloat = 8 * mockPixel
        /// 見出しとカード、カードとカードの間（モック 6px）
        public static let itemSpacing: CGFloat = 6 * mockPixel
        /// カードの中の左右の余白（モック 7px）
        public static let cardPadding: CGFloat = 7 * mockPixel
        /// カードの中の上下の余白（モック 6px）
        public static let cardPaddingVertical: CGFloat = 6 * mockPixel
        /// カードの角の丸み（モック 7px）
        public static let cardRadius: CGFloat = 7 * mockPixel
        /// 番号の丸の直径（モック 12px）
        public static let numberDiameter: CGFloat = 12 * mockPixel
        /// 番号の丸の上のずれ（モック 1px）
        public static let numberTopOffset: CGFloat = 1 * mockPixel
        /// 番号の丸と中身の間（モック 6px）
        public static let numberGap: CGFloat = 6 * mockPixel
        /// カードの中の、画像・タイトル・本文の間（モック 3px）
        public static let contentSpacing: CGFloat = 3 * mockPixel
        /// 画像の高さ（モック 40px。横はカードの幅いっぱい）
        public static let pictureHeight: CGFloat = 40 * mockPixel
        /// 画像の角の丸み（モック 4px）
        public static let pictureRadius: CGFloat = 4 * mockPixel
        /// 見出しの FIFO / LIFO の印と、残りの件数の間（モック 6px）
        public static let headerSpacing: CGFloat = 6 * mockPixel
        /// FIFO / LIFO の印の中の左右・上下の余白（モック 6px・1px）
        public static let badgePaddingHorizontal: CGFloat = 6 * mockPixel
        public static let badgePaddingVertical: CGFloat = 1 * mockPixel
        /// 本文の文字の大きさに対する比（モックの px ÷ 8.5px）
        public static let badgeFontRatio: CGFloat = 8 / 8.5
        public static let countFontRatio: CGFloat = 9 / 8.5
        public static let numberFontRatio: CGFloat = 7.5 / 8.5
        /// 本文の行の高さ（文字の大きさの倍率。モック line-height 1.45）
        public static let lineHeightRatio: CGFloat = 1.45
        /// 帯の影（モック: 内側へだけ。box-shadow 6px 0 20px 黒 28%）。
        /// 帯の外の長さなので、文字の大きさには合わせず、画面を縮めた割合（帯の幅 260pt を 146px に描いた）で戻す
        /// （2026-10-31 画面のデザインのスレッドの決定）。値は pt
        public static let outsidePixel: CGFloat = 260 / 146
        public static let shadowOffset: CGFloat = 6 * outsidePixel
        public static let shadowBlur: CGFloat = 20 * outsidePixel
        public static let shadowOpacity: CGFloat = 0.28
        /// 影を描く所の幅。CSS のぼかしは標準偏差がぼかしの半分のガウスなので、その 3 倍で見えなくなる
        public static let shadowExtent: CGFloat = shadowOffset + shadowBlur * 1.5
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

    /// 本文の全角 1 字の幅。本文と同じシステムの文字で「一」を 40 字並べて測り、40 で割る。
    /// 文字の大きさと同じとは限らない（2026-10-31、そう仮定した最大で 1 行に 43 字入った）。AppKit の無い所では文字の大きさ
    public static func fullWidthCharacterWidth(fontSize: CGFloat) -> CGFloat {
        #if canImport(AppKit)
        let text = NSAttributedString(
            string: String(repeating: "一", count: Int(maxCharacters)),
            attributes: [.font: NSFont.systemFont(ofSize: fontSize)]
        )
        return text.size().width / maxCharacters
        #else
        return fontSize
        #endif
    }

    /// 本文が全角 40 字になる幅（と余裕）。帯が画面からはみ出さないよう、画面の幅で止める
    public static func maxWidth(fontSize: CGFloat, screen: CGRect) -> CGFloat {
        let wanted = maxCharacters * fullWidthCharacterWidth(fontSize: fontSize) + maxWidthSlack + chromeWidth(fontSize: fontSize)
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

    /// 帯の影を描く所。帯の内側の端の外に接し、帯と同じ高さ。影の所のクリックは後ろのアプリに届けるので、帯とは別のウインドウにする
    public static func shadowFrame(band: CGRect, side: HUDSide) -> CGRect {
        let width = Metrics.shadowExtent
        let x: CGFloat
        switch side {
        case .left: x = band.maxX
        case .right: x = band.minX - width
        }
        return CGRect(x: x, y: band.minY, width: width, height: band.height)
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

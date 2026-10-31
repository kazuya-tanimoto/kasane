import Foundation
#if canImport(CoreGraphics)
// macOS では CGFloat や CGRect の計算は CoreGraphics にあり、Foundation だけでは見えない
import CoreGraphics
#endif

/// 文字の大きさの段階（2026-10-22 決定。詳細はデザインの font-size-levels-2026-10-22.md）。
///
/// 履歴ウインドウでは、一覧とプレビューの文字に一段ごとに 1.5pt を足し、アイコンやリストの幅などは
/// リストの見出し（標準 13pt）の割合で大きくする。FIFO / LIFO の小さいウインドウも同じ 3 段階を使う
public enum TextSizeLevel: String, CaseIterable, Sendable {
    case standard, large, extraLarge

    public static let `default` = TextSizeLevel.standard

    /// リストの見出しの標準の大きさ。割合の基準
    public static let baseTitleSize: CGFloat = 13

    /// 一段ごとに足す大きさ
    public static let step: CGFloat = 1.5

    public var displayName: String {
        switch self {
        case .standard: return "標準"
        case .large: return "大"
        case .extraLarge: return "特大"
        }
    }

    private var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// 標準から足す大きさ（0 / 1.5 / 3pt）
    public var pointDelta: CGFloat { CGFloat(index) * Self.step }

    /// 文字以外（アイコン、リストの幅、余白）に掛ける割合（1 / 1.115 / 1.231）
    public var ratio: CGFloat { (Self.baseTitleSize + pointDelta) / Self.baseTitleSize }

    /// 標準での文字の大きさから、この段階の大きさにする
    public func font(_ standardSize: CGFloat) -> CGFloat { standardSize + pointDelta }

    /// 標準での大きさ（文字以外）に割合を掛ける
    public func scaled(_ standardValue: CGFloat) -> CGFloat { standardValue * ratio }

    /// 一段大きい段階。特大なら nil
    public var larger: TextSizeLevel? {
        let next = index + 1
        return next < Self.allCases.count ? Self.allCases[next] : nil
    }

    /// 一段小さい段階。標準なら nil
    public var smaller: TextSizeLevel? {
        index > 0 ? Self.allCases[index - 1] : nil
    }

    /// 小さいウインドウ（FIFO / LIFO）の文字の大きさ（13 / 14.5 / 16pt）
    public var hudFontSize: CGFloat { font(Self.baseTitleSize) }

    /// 前の版で pt で選んでいた小さいウインドウの文字の大きさを、一番近い段階にする
    /// （11・12 → 標準、14 → 大、16・18・20 → 特大。同じ近さなら小さい方）
    public static func nearest(toHUDFontSize size: CGFloat) -> TextSizeLevel {
        var best = TextSizeLevel.standard
        for level in allCases where abs(level.hudFontSize - size) < abs(best.hudFontSize - size) {
            best = level
        }
        return best
    }
}

extension WindowPlacement {
    /// 履歴ウインドウのうち、文字の大きさで変わらない部分（上の帯・検索欄・絞り込み・一覧の下の余白の高さと、左右と間の余白）。
    /// 文字の大きさを変えるときは、ウインドウからこの分を除いた残りに割合を掛ける。
    /// 高さは 上の帯 28 ＋ 線 1 ＋ 検索欄 約 55 ＋ 絞り込み 約 37 ＋ 一覧の下 6 ＝ 127。
    /// 上の帯の下の線 1 は PR #13 で入る（#13 より先にこの行が入る間は実際より 1 多いが、大で約 0.1pt の差）
    /// 下のボタンは一覧の上に浮く帯になり（requirements.md §3.3）、ウインドウの高さを取らないので入れない（前は帯の分を入れて 175）
    public static let historyChrome = CGSize(width: 36, height: 127)

    /// 標準での大きさ `size` を、`level` の大きさにする（初めの大きさと最小の大きさに使う）
    public static func size(_ size: CGSize, scaledTo level: TextSizeLevel) -> CGSize {
        rescale(size, by: level.ratio)
    }

    /// 文字の大きさを `from` から `to` に変えたときの枠。左上は動かさず、画面からはみ出すときは画面に収める
    public static func frame(
        _ frame: CGRect,
        in screen: CGRect,
        changingTextSizeFrom from: TextSizeLevel,
        to: TextSizeLevel,
        minSize: CGSize
    ) -> CGRect {
        let wanted = rescale(frame.size, by: to.ratio / from.ratio)
        let size = CGSize(
            width: min(max(wanted.width, minSize.width), screen.width),
            height: min(max(wanted.height, minSize.height), screen.height)
        )
        // AppKit の座標は下が 0 なので、左上を保つには上端（maxY）をそろえる
        let origin = CGPoint(
            x: min(max(frame.minX, screen.minX), screen.maxX - size.width),
            y: min(max(frame.maxY - size.height, screen.minY), screen.maxY - size.height)
        )
        return CGRect(origin: origin, size: size)
    }

    private static func rescale(_ size: CGSize, by factor: CGFloat) -> CGSize {
        let chrome = historyChrome
        return CGSize(
            width: chrome.width + (size.width - chrome.width) * factor,
            height: chrome.height + (size.height - chrome.height) * factor
        )
    }
}

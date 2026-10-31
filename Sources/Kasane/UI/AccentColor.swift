import AppKit
import KasaneCore
import SwiftUI

/// アクセントカラー。「重ね」にちなんで日本の伝統色から選ぶ。Mac の設定に合わせる「システム」と「モノクロ」も選べる。
///
/// 使うのはペーストのボタン、選んだ行のアイコン、検索で一致した文字、FIFO / LIFO の小さいウインドウの印と番号だけで、
/// ほかは無彩色にする（2026-10-22・23 決定。requirements.md 外観の節）。色の値は KasaneCore の AccentTone
enum AccentColor: String, CaseIterable {
    // 設定に並べる順
    case matcha, seiji, ai, edoMurasaki, enji, rikyuNezumi, system, mono

    static let `default` = AccentColor.ai

    var displayName: String {
        switch self {
        case .seiji: return "青磁"
        case .matcha: return "抹茶"
        case .ai: return "藍"
        case .edoMurasaki: return "江戸紫"
        case .enji: return "臙脂"
        case .rikyuNezumi: return "利休鼠"
        case .system: return "システム"
        case .mono: return "モノクロ"
        }
    }

    /// 伝統色とモノクロの値。システムは nil
    private var tone: AccentTone? { AccentTone(rawValue: rawValue) }

    var color: Color {
        guard let tone else { return Color(nsColor: .controlAccentColor) }
        return Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(Self.isDark(appearance) ? tone.dark : tone.light)
        })
    }

    /// 検索で一致した文字の後ろに敷く塗りの色。白や黒を混ぜず、色みと彩度を保ったまま明るさだけを変えて、
    /// いちばん条件の悪い地で 4.6 以上（「コントラストを上げる」がオンなら 7.0 以上）にする（計算は ContrastFit）
    var matchFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in matchFill(in: appearance) })
    }

    private func matchFill(in appearance: NSAppearance) -> NSColor {
        let dark = Self.isDark(appearance)
        let base = tone.map { dark ? $0.dark : $0.light } ?? Self.systemAccent(in: appearance)
        return NSColor(ContrastFit.matchFill(base, dark: dark, increasedContrast: Self.isHighContrast(appearance)))
    }

    /// 塗りの上の文字の色（ライトは白、ダークは #1D1D1F）
    static let onMatchFill = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(AccentColor.isDark(appearance) ? ContrastFit.onMatchFillDark : ContrastFit.onMatchFillLight)
    })

    /// Mac の設定のアクセントカラー。描いている appearance（ライト / ダーク）での色を読む
    /// （provider の中で、そのときの描画の appearance が渡されたものと同じとは限らないため）
    private static func systemAccent(in appearance: NSAppearance) -> SRGBColor {
        let c = systemAccentNSColor(in: appearance)
        return SRGBColor(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
    }

    private static func systemAccentNSColor(in appearance: NSAppearance) -> NSColor {
        // 読めなかったときは Mac の初期の青（#007AFF）
        var color = NSColor(srgbRed: 0, green: 0x7A / 255.0, blue: 1, alpha: 1)
        appearance.performAsCurrentDrawingAppearance {
            if let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) { color = accent }
        }
        return color
    }

    /// 小さいウインドウの次の番号の色（小さいウインドウは今のまま、の決定なので、一致した文字の matchFill とは別）。
    /// ダークでは暗い背景に沈む色（藍・江戸紫・臙脂など）があるので、白を 40% 混ぜて明るくする。
    /// ライトでは明るめの色（青磁・抹茶など）がウインドウの灰色の背景で読みにくいので、
    /// コントラストが 4.5 以上になるまで黒を混ぜる
    var text: Color {
        let tone = tone
        return Color(nsColor: NSColor(name: nil) { appearance in
            let base = tone.map { NSColor(Self.isDark(appearance) ? $0.dark : $0.light) }
                ?? Self.systemAccentNSColor(in: appearance)
            if Self.isDark(appearance) {
                return base.blended(withFraction: 0.4, of: .white) ?? base
            }
            // ライトのウインドウの背景（#ECECEC）の相対輝度
            let backgroundLuminance = 0.84
            var color = base
            var fraction = 0.0
            while (backgroundLuminance + 0.05) / (Self.luminance(color) + 0.05) < 4.5, fraction < 0.6 {
                fraction += 0.05
                color = base.blended(withFraction: fraction, of: .black) ?? base
            }
            return color
        })
    }

    /// WCAG の相対輝度
    private static func luminance(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB) ?? color
        func linear(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    /// アクセントカラーの上に載せる文字の色
    var foreground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in foreground(in: appearance) })
    }

    private func foreground(in appearance: NSAppearance) -> NSColor {
        guard let tone else {
            // システムのアクセントカラーは利用者が変えられる（黄色など明るい色もある）ので、明るさで白か黒を選ぶ
            let accent = Self.systemAccentNSColor(in: appearance)
            let luminance = 0.2126 * accent.redComponent + 0.7152 * accent.greenComponent + 0.0722 * accent.blueComponent
            return luminance > 0.6 ? NSColor(hex: 0x1D1D1F) : .white
        }
        return Self.isDark(appearance) && tone.darkTextOnDark ? NSColor(hex: 0x1D1D1F) : .white
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Mac の「コントラストを上げる」がオンか。色を描くときに渡る appearance で見分ける
    /// （NSWorkspace のフラグだと、切り替えたときに描き直されないことがあるため）
    static func isHighContrast(_ appearance: NSAppearance) -> Bool {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
        return match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
    }
}

extension NSColor {
    convenience init(_ color: SRGBColor) {
        self.init(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }

    convenience init(hex: UInt32) {
        self.init(SRGBColor(hex: hex))
    }
}

extension Color {
    /// 種類の文字とアイコンの記号の灰色（ライト #55585F、ダーク #ABAEB6。どちらも条件の悪い地で 4.5 以上。値は ContrastFit）
    static let kindGray = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(AccentColor.isDark(appearance) ? ContrastFit.kindGrayDark : ContrastFit.kindGrayLight)
    })
}

private struct AccentColorKey: EnvironmentKey {
    static let defaultValue = AccentColor.default
}

extension EnvironmentValues {
    /// 履歴ウインドウの中で使うアクセントカラー
    var kasaneAccent: AccentColor {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
}

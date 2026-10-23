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

    /// 検索で一致した文字の色。白や黒を混ぜず、色みと彩度を保ったまま明るさだけを変えて、
    /// いちばん条件の悪い地で 4.6 以上（「コントラストを上げる」がオンなら 7.0 以上）にする（計算は ContrastFit）
    var matchText: Color {
        let tone = self.tone
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = Self.isDark(appearance)
            let base = tone.map { dark ? $0.dark : $0.light } ?? Self.systemAccent()
            return NSColor(ContrastFit.matchText(base, dark: dark, increasedContrast: Self.isHighContrast(appearance)))
        })
    }

    private static func systemAccent() -> RGBColor {
        let c = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue.usingColorSpace(.sRGB)!
        return RGBColor(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
    }

    /// 小さいウインドウの次の番号の色（小さいウインドウは今のまま、の決定なので、一致した文字の matchText とは別）。
    /// ダークでは暗い背景に沈む色（藍・江戸紫・臙脂など）があるので、白を 40% 混ぜて明るくする。
    /// ライトでは明るめの色（青磁・抹茶など）がウインドウの灰色の背景で読みにくいので、
    /// コントラストが 4.5 以上になるまで黒を混ぜる
    var text: Color {
        let tone = tone
        return Color(nsColor: NSColor(name: nil) { appearance in
            let base = tone.map { NSColor(Self.isDark(appearance) ? $0.dark : $0.light) }
                ?? (NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue)
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
        guard let tone else {
            // システムのアクセントカラーは利用者が変えられる（黄色など明るい色もある）ので、明るさで白か黒を選ぶ
            return Color(nsColor: NSColor(name: nil) { _ in
                let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
                let luminance = 0.2126 * accent.redComponent + 0.7152 * accent.greenComponent + 0.0722 * accent.blueComponent
                return luminance > 0.6 ? NSColor(hex: 0x1D1D1F) : .white
            })
        }
        let darkText = tone.darkTextOnDark
        return Color(nsColor: NSColor(name: nil) { appearance in
            Self.isDark(appearance) && darkText ? NSColor(hex: 0x1D1D1F) : .white
        })
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
    convenience init(_ color: RGBColor) {
        self.init(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }

    convenience init(hex: UInt32) {
        self.init(RGBColor(hex: hex))
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

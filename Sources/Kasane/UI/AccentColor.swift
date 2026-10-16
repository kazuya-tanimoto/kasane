import AppKit
import SwiftUI

/// アクセントカラー。「重ね」にちなんで日本の伝統色から選ぶ。Mac の設定に合わせる「システム」と「モノクロ」も選べる。
///
/// 使うのはペーストのボタン、次に貼る番号、FIFO / LIFO の印だけで、ほかは無彩色にする。
/// 伝統色そのままでは上に載せた文字が読みにくいものがあるので、ライト / ダークそれぞれで
/// 文字とのコントラストが 4.5 以上になる濃さに調整してある
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

    /// ライトの色、ダークの色、ダークで上に黒い文字を載せるか（ライトでは常に白い文字）。システムは nil
    private var palette: (light: UInt32, dark: UInt32, darkTextOnDark: Bool)? {
        switch self {
        case .seiji: return (0x2F7F6F, 0x7EBEAB, true)
        case .matcha: return (0x6B7B26, 0xB4BC5C, true)
        case .ai: return (0x165E83, 0x2A6F9B, false)
        case .edoMurasaki: return (0x745399, 0x80619F, false)
        case .enji: return (0xA8323A, 0xB4434A, false)
        case .rikyuNezumi: return (0x61675A, 0x9AA08E, true)
        case .mono: return (0x1D1D1F, 0xF2F2F5, true)
        case .system: return nil
        }
    }

    var color: Color {
        guard let palette else { return Color(nsColor: .controlAccentColor) }
        return Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: Self.isDark(appearance) ? palette.dark : palette.light)
        })
    }

    /// 背景の上に文字としてアクセントカラーを使うときの色。
    /// ダークでは暗い背景に沈む色（藍・江戸紫・臙脂など）があるので、白を 40% 混ぜて明るくする
    var text: Color {
        let palette = palette
        return Color(nsColor: NSColor(name: nil) { appearance in
            let base = palette.map { NSColor(hex: Self.isDark(appearance) ? $0.dark : $0.light) }
                ?? (NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue)
            guard Self.isDark(appearance) else { return base }
            return base.blended(withFraction: 0.4, of: .white) ?? base
        })
    }

    /// アクセントカラーの上に載せる文字の色
    var foreground: Color {
        guard let palette else {
            // システムのアクセントカラーは利用者が変えられる（黄色など明るい色もある）ので、明るさで白か黒を選ぶ
            return Color(nsColor: NSColor(name: nil) { _ in
                let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
                let luminance = 0.2126 * accent.redComponent + 0.7152 * accent.greenComponent + 0.0722 * accent.blueComponent
                return luminance > 0.6 ? NSColor(hex: 0x1D1D1F) : .white
            })
        }
        let darkText = palette.darkTextOnDark
        return Color(nsColor: NSColor(name: nil) { appearance in
            Self.isDark(appearance) && darkText ? NSColor(hex: 0x1D1D1F) : .white
        })
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
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

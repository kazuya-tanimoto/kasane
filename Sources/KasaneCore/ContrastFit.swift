import Foundation

/// sRGB の色（各成分 0〜1）
public struct RGBColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    /// 8 ビットに丸めた値
    public var hex: UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    /// HSL（色み・彩度・明るさ、どれも 0〜1）
    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let mx = max(red, green, blue), mn = min(red, green, blue)
        let l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == red {
            h = (green - blue) / d + (green < blue ? 6 : 0)
        } else if mx == green {
            h = (blue - red) / d + 2
        } else {
            h = (red - green) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    public init(hue h: Double, saturation s: Double, lightness l: Double) {
        guard s != 0 else {
            self.init(red: l, green: l, blue: l)
            return
        }
        func channel(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        self.init(red: channel(p, q, h + 1.0 / 3), green: channel(p, q, h), blue: channel(p, q, h - 1.0 / 3))
    }
}

/// 文字の色と地の色のコントラスト（WCAG）と、アクセントカラーで書く文字（検索で一致した文字）の色の合わせ方。
///
/// 一致した文字は、白や黒を混ぜずに、色みと彩度を保ったまま明るさだけを変えて、いちばん条件の悪い地で
/// target 以上にする。白を混ぜると色が抜けて、アクセントの色に見えなくなるため
/// （requirements.md 外観の節、design/accent-usage-2026-10-22.md §3.1。手順はモックの ksFitL と同じ）
public enum ContrastFit {
    /// 一致した文字のコントラストの目標。要件の 4.5 に少し余裕を持たせる（モックと同じ）
    public static let matchTarget = 4.6
    /// Mac の「コントラストを上げる」がオンのときの目標
    public static let increasedContrastTarget = 7.0

    /// いちばん条件の悪い地。ライトは選んでいない行（ガラスの上で、白より暗い）、ダークは選んだ行
    public static let lightBackground = RGBColor(hex: 0xF4F4F7)
    public static let darkBackground = RGBColor(hex: 0x3D4047)

    /// 種類の文字とアイコンの記号の灰色。どちらも上の地で 4.5 以上（ダークはモックの #A7AAB2 では 4.47 だったので白に寄せた）
    public static let kindGrayLight = RGBColor(hex: 0x55585F)
    public static let kindGrayDark = RGBColor(hex: 0xABAEB6)

    /// WCAG の相対輝度
    public static func luminance(_ color: RGBColor) -> Double {
        func linear(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    public static func contrast(_ a: RGBColor, _ b: RGBColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// 色みと彩度を保ち、明るさを 0.01 ずつ（地が暗ければ上げ、明るければ下げ）変えて、
    /// 8 ビットに丸めた色で target に届いた最初の色を返す。届かなければ白か黒
    public static func fitLightness(_ color: RGBColor, background: RGBColor, target: Double) -> RGBColor {
        let (h, s, l) = color.hsl
        let raises = luminance(background) < 0.2
        let step = raises ? 0.01 : -0.01
        var lightness = l
        while lightness >= 0 && lightness <= 1 {
            let candidate = RGBColor(hex: RGBColor(hue: h, saturation: s, lightness: lightness).hex)
            if contrast(candidate, background) >= target { return candidate }
            lightness += step
        }
        return raises ? RGBColor(hex: 0xFFFFFF) : RGBColor(hex: 0x000000)
    }

    /// 一致した文字の色
    public static func matchText(_ accent: RGBColor, dark: Bool, increasedContrast: Bool) -> RGBColor {
        fitLightness(
            accent,
            background: dark ? darkBackground : lightBackground,
            target: increasedContrast ? increasedContrastTarget : matchTarget
        )
    }
}

/// アクセントカラーの伝統色の値。アプリ（AccentColor）とテストで同じ値を使う。
/// 伝統色そのままでは上に載せた文字が読みにくいものがあるので、ライト / ダークそれぞれで
/// 上に載せる文字とのコントラストが 4.5 以上になる濃さに調整してある。システム（Mac の設定の色）はここにない
public enum AccentTone: String, CaseIterable, Sendable {
    case matcha, seiji, ai, edoMurasaki, enji, rikyuNezumi, mono

    public var light: RGBColor { RGBColor(hex: values.light) }
    public var dark: RGBColor { RGBColor(hex: values.dark) }
    /// ダークで、塗った上に黒い文字を載せるか（ライトでは常に白い文字）
    public var darkTextOnDark: Bool { values.darkTextOnDark }

    private var values: (light: UInt32, dark: UInt32, darkTextOnDark: Bool) {
        switch self {
        case .seiji: return (0x2F7F6F, 0x7EBEAB, true)
        case .matcha: return (0x6B7B26, 0xB4BC5C, true)
        case .ai: return (0x165E83, 0x2A6F9B, false)
        case .edoMurasaki: return (0x745399, 0x80619F, false)
        case .enji: return (0xA8323A, 0xB4434A, false)
        case .rikyuNezumi: return (0x61675A, 0x9AA08E, true)
        case .mono: return (0x1D1D1F, 0xF2F2F5, true)
        }
    }
}

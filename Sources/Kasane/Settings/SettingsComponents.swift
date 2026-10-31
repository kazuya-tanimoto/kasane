import AppKit
import SwiftUI

/// 設定画面の部品。Mac のシステム設定に近い見た目（角丸の箱の中に行を並べ、行の間に線）にする。
/// Form の grouped は中でスクロールして高さを決めないので、タブごとにウインドウの高さを中身に合わせられるよう自前で並べる

/// 幅と間（全タブ共通。幅は settings-screen-2026-10-22.md §4、余白と間はモック「設定画面 10/22 案」の値）
enum SettingsLayout {
    static let width: CGFloat = 760
    /// 中の余白（モック: 上 18・左右 22・下 22）
    static let padding = EdgeInsets(top: 18, leading: 22, bottom: 22, trailing: 22)
    /// 箱・見出し・説明の間（モック: 16）
    static let rowSpacing: CGFloat = 16
    /// 箱の角の丸み（モック: 12）
    static let boxCornerRadius: CGFloat = 12
}

/// 設定画面の色（モック「設定画面 10/22 案」の KS_THEMES。ライト / ダーク）
enum SettingsColor {
    /// 箱の地（ライト 白、ダーク 白 5%）。ライトでは周りより明るい白い箱にする
    static let box = dynamic(light: .white, dark: NSColor.white.withAlphaComponent(0.05))
    /// 箱の縁と、行の間の線（ライト 黒 8%、ダーク 白 8%）
    static let line = dynamic(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.08))
    /// 見出しと説明の灰色（ライト #61646B、ダーク #A7AAB2）
    static let sub = dynamic(light: rgb(0x61, 0x64, 0x6B), dark: rgb(0xA7, 0xAA, 0xB2))
    /// キーや検索の書き方の札の地（ライト 黒 6%、ダーク 白 10%）
    static let chip = dynamic(light: NSColor.black.withAlphaComponent(0.06), dark: NSColor.white.withAlphaComponent(0.10))
    /// 箱の中の、一段沈んだ地（検索の例。ライト 黒 3.5%、ダーク 白 4%）
    static let inset = dynamic(light: NSColor.black.withAlphaComponent(0.035), dark: NSColor.white.withAlphaComponent(0.04))
    /// 一覧の下の ＋ − の帯の地（ライト #F7F7F9、ダーク 白 3%）
    static let footer = dynamic(light: rgb(0xF7, 0xF7, 0xF9), dark: NSColor.white.withAlphaComponent(0.03))
    /// 赤い文（ライト #C62828、ダーク #FF6B6B）
    static let danger = dynamic(light: rgb(0xC6, 0x28, 0x28), dark: rgb(0xFF, 0x6B, 0x6B))

    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}

/// 文字の大きさ（settings-screen-2026-10-22.md §3「文字の大きさ」）。
/// 読ませる文（説明・状態・赤い文）は Apple の標準の 13pt より小さくしない。タブ名・タイトル・見本の中・確認のシートは変えない
enum SettingsFont {
    /// 項目名、除外の一覧のアプリ名、ショートカットの名前とキーの欄
    static let item: CGFloat = 15
    /// 説明、見出し、ボタン、状態、赤い文、数値の欄、検索の例（タブの中の標準）。
    /// ポップアップと段の切り替えは .font も controlSize も効かず、システムの 13pt のまま（2026-10-24 に CI の Mac で測った）
    static let text: CGFloat = 14
    /// キーの記号の札、いちばん下の行（記号で読む・めったに読まないため）
    static let small: CGFloat = 13
    /// アクセントカラーの色の名前（色の丸が主で、名前は添え字のため）
    static let colorName: CGFloat = 13
}

/// 角丸の箱。中の行の間には `SettingsDivider` を置く
struct SettingsBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .settingsBoxBackground()
    }
}

extension View {
    /// 箱の地と縁（モック: 角 12、縁 1px）
    func settingsBoxBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: SettingsLayout.boxCornerRadius, style: .continuous)
        return background(shape.fill(SettingsColor.box))
            .overlay(shape.strokeBorder(SettingsColor.line, lineWidth: 1))
            .clipShape(shape)
    }
}

/// 行の間の線。モックと同じく、箱の左右の端まで引く
struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(SettingsColor.line).frame(height: 1)
    }
}

/// 箱の上の見出し
struct SettingsHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // モック: 14pt の太字（600）を灰色で。右に「標準に戻す」などを置くときも、行の高さは 24 から
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: SettingsFont.text, weight: .semibold))
                .foregroundStyle(SettingsColor.sub)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 4)
    }
}

extension SettingsHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// 左に項目名と説明、右に操作を置く 1 行
struct SettingsRow<Control: View>: View {
    var title: String
    var description: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: SettingsFont.item))
                if let description {
                    SettingsCaption(description)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .settingsRowPadding()
    }
}

extension View {
    /// 箱の中の 1 行の余白（モック: 上下 11・左右 14）
    func settingsRowPadding() -> some View {
        padding(.horizontal, 14).padding(.vertical, 11)
    }
}

/// 灰色の小さい説明の文
struct SettingsCaption: View {
    var text: String
    /// 行の高さ（文字の大きさの何倍か）。nil ならシステムの標準
    var lineHeight: CGFloat?

    init(_ text: String, lineHeight: CGFloat? = nil) {
        self.text = text
        self.lineHeight = lineHeight
    }

    var body: some View {
        Text(text)
            .font(.system(size: SettingsFont.text))
            .lineSpacing(lineHeight.map { LineHeight.spacing(multiple: $0, fontSize: SettingsFont.text) } ?? 0)
            .foregroundStyle(SettingsColor.sub)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 中身の高さに合わせて縦に伸び、画面より高くなるときだけ中をスクロールする。
/// 設定の中身が下に隠れていると、そこに項目があることに気づけないため（settings-screen-2026-10-22.md §4）
struct FittingScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 300

    /// タイトルバーとタブの帯を除いた、画面で使える高さ
    private var maxHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(screen - 110, 300)
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .font(.system(size: SettingsFont.text))
                .padding(SettingsLayout.padding)
                .frame(width: SettingsLayout.width, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollDisabled(height <= maxHeight)
        .frame(width: SettingsLayout.width, height: min(height, maxHeight))
    }
}

/// 状態の印（許可の行）。モック: 直径 20 の丸を緑（#2F9E44）か橙（#D97706）で塗り、白い ✓ か ! を太字で置く
struct StatusMark: View {
    var ok: Bool

    var body: some View {
        Text(ok ? "✓" : "!")
            .font(.system(size: SettingsFont.small, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color(nsColor: ok ? SettingsColor.rgb(0x2F, 0x9E, 0x44) : SettingsColor.rgb(0xD9, 0x77, 0x06))))
            .accessibilityHidden(true)
    }
}

/// 許可の状態の文の色（モック: 許可は緑 ライト #2B8A3E・ダーク #69DB7C、それ以外は橙 #B45309）
enum StatusTextColor {
    static let ok = SettingsColor.dynamic(light: SettingsColor.rgb(0x2B, 0x8A, 0x3E), dark: SettingsColor.rgb(0x69, 0xDB, 0x7C))
    static let attention = Color(nsColor: SettingsColor.rgb(0xB4, 0x53, 0x09))
}

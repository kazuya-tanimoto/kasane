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

/// 設定画面の色。Mac のシステムの色を使う（requirements.md「設定画面の部品の色はシステムの色を使う（アクセントカラーは使わない）」。
/// 2026-10-31 にモックの決まった色へ変えたのを、Kazuya さんの了解が無いので戻した。fixes-without-asking-2026-10-31.md の前の 9）。
/// システムの色なので、ダークと「コントラストを上げる」にも Mac が合わせる
enum SettingsColor {
    /// 箱の地（main と同じ）
    static let box = Color(nsColor: .quaternaryLabelColor).opacity(0.25)
    /// 箱の縁と、行の間の線
    static let line = Color(nsColor: .separatorColor)
    /// 本文の色
    static let text = Color(nsColor: .labelColor)
    /// ウインドウの地
    static let window = Color(nsColor: .windowBackgroundColor)
    /// 見出しと説明の灰色
    static let sub = Color(nsColor: .secondaryLabelColor)
    /// 文字のボタン、キーや検索の書き方の札の地
    static let chip = Color(nsColor: .tertiarySystemFill)
    /// 箱の中の、一段沈んだ地（検索の例）
    static let inset = Color(nsColor: .quaternarySystemFill)
    /// 一覧の下の ＋ − の帯の地
    static let footer = Color(nsColor: .quaternarySystemFill)
    /// 赤い文
    static let danger = Color(nsColor: .systemRed)

    /// ライトとダークで色を変える（外観タブの見本の絵だけに使う。見本は履歴ウインドウの絵なので、設定画面の色の決めの外）
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
            .lineHeight(lineHeight ?? 0, fontSize: SettingsFont.text)
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
                .foregroundStyle(SettingsColor.text)
                .padding(SettingsLayout.padding)
                .frame(width: SettingsLayout.width, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollDisabled(height <= maxHeight)
        .frame(width: SettingsLayout.width, height: min(height, maxHeight))
        // ウインドウの地（モック: ライト #F5F5F7、ダーク #26282D）。上のタブの帯は Mac 標準のまま
        .background(SettingsColor.window)
    }
}

/// 状態の印（許可の行）。Mac の記号（settings-screen-2026-10-22.md §3 の文字の表「変えない: 許可の状態の前の印（SF Symbols の印）」）
struct StatusMark: View {
    var ok: Bool

    var body: some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? Color.green : Color.orange)
            .font(.system(size: 15))
            .accessibilityHidden(true)
    }
}

/// 文字のボタン（「システム設定を開く」「標準に戻す」など）。モックの形: 平らな地、角 7、上下 4・左右 10（色はシステムの色）。
/// 文字の大きさは置く所で決める（ふだん 14pt、いちばん下の行は 13pt。settings-screen-2026-10-22.md §3）
struct SettingsButtonStyle: ButtonStyle {
    /// 文字の色。nil なら本文の色（「履歴を削除…」だけ赤）
    var tint: Color?
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? (tint ?? SettingsColor.text) : SettingsColor.sub)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(SettingsColor.chip, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == SettingsButtonStyle {
    static var settings: SettingsButtonStyle { SettingsButtonStyle() }
}

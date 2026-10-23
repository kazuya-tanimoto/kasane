import AppKit
import SwiftUI

/// 設定画面の部品。Mac のシステム設定に近い見た目（角丸の箱の中に行を並べ、行の間に線）にする。
/// Form の grouped は中でスクロールして高さを決めないので、タブごとにウインドウの高さを中身に合わせられるよう自前で並べる

/// 幅（全タブ共通。settings-screen-2026-10-22.md §4）
enum SettingsLayout {
    static let width: CGFloat = 760
    static let padding: CGFloat = 20
    static let rowSpacing: CGFloat = 8
}

/// 角丸の箱。中の行の間には `SettingsDivider` を置く
struct SettingsBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 12)
    }
}

/// 箱の上の見出し
struct SettingsHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let description {
                    SettingsCaption(description)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// 灰色の小さい説明の文
struct SettingsCaption: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
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
                .padding(SettingsLayout.padding)
                .frame(width: SettingsLayout.width, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollDisabled(height <= maxHeight)
        .frame(width: SettingsLayout.width, height: min(height, maxHeight))
    }
}

/// 状態の印（許可の行）
struct StatusMark: View {
    var ok: Bool

    var body: some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? Color.green : Color.orange)
            .font(.system(size: 15))
            .accessibilityHidden(true)
    }
}

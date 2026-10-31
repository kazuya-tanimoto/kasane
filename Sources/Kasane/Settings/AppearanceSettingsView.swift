import AppKit
import KasaneCore
import SwiftUI

/// 外観のタブ（settings-screen-2026-10-22.md §3「外観」）。右に、変えた結果を描く見本を置く
struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var appearance: AppearanceSettings
    /// 「標準に戻す」を押したあとの案内。また動かすまで出す
    @State private var didResetWindow = false

    init(model: SettingsModel) {
        self.model = model
        self.appearance = model.appearance
    }

    private static let sampleWidth: CGFloat = 250
    private static let boxSpacing: CGFloat = 14
    /// 見出しと、その下の箱の間（モック: 8）
    private static let headerSpacing: CGFloat = 8

    var body: some View {
        FittingScroll {
            // モック: 左の列と見本の間は 18、左の列の箱の間は 14
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: Self.boxSpacing) {
                    accentBox
                    background
                    historyWindow
                    queueWindow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AppearanceSample(model: model, appearance: appearance)
                    .frame(width: Self.sampleWidth)
            }
        }
        .onChange(of: appearance.historyTextSize) {
            model.historyTextSizeChanged()
            didResetWindow = false
        }
    }

    // MARK: - アクセントカラー

    private var accentBox: some View {
        SettingsBox {
            // モック: 箱の中の上下 12・左右 14。説明との間 2、色の並びとの間 10
            VStack(alignment: .leading, spacing: 2) {
                Text("アクセントカラー").font(.system(size: SettingsFont.item))
                SettingsCaption("ペーストボタン、選んだ行のアイコン、検索で一致した文字、FIFO / LIFO モード中の小さいウインドウの印と番号に使います")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 10) {
                    ForEach(AccentColor.allCases, id: \.self) { accent in
                        accentButton(accent)
                    }
                }
                .padding(.top, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("アクセントカラー")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func accentButton(_ accent: AccentColor) -> some View {
        let selected = appearance.accent == accent
        return Button {
            appearance.accent = accent
        } label: {
            // モック: 丸 22、名前との間 4。選んだ色は 2pt あけて 2pt の輪（本文の色）、ほかは内側に 1px の灰（35%）の輪
            VStack(spacing: 4) {
                Circle()
                    .fill(accent == .system
                          ? AnyShapeStyle(AngularGradient(colors: [.blue, .purple, .pink, .orange, .green, .blue], center: .center))
                          : AnyShapeStyle(accent.color))
                    .overlay(Circle().strokeBorder(Color.gray.opacity(selected ? 0 : 0.35), lineWidth: 1))
                    .frame(width: 22, height: 22)
                    .overlay {
                        if selected {
                            Circle()
                                .strokeBorder(SettingsColor.text, lineWidth: 2)
                                .frame(width: 30, height: 30)
                        }
                    }
                Text(accent.displayName)
                    .font(.system(size: SettingsFont.colorName))
                    .foregroundStyle(selected ? SettingsColor.text : SettingsColor.sub)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 背景

    private var background: some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            SettingsHeader(title: "背景（履歴ウインドウと小さいウインドウ）") {
                if !model.isBackgroundStandard {
                    Button("標準に戻す") { model.resetBackground() }
                        .buttonStyle(.settings)
                }
            }
            .frame(minHeight: 24)
            // 帯のボタンは Liquid Glass で、この 2 つの設定が効かない。使う人が設定と見え方の違いに迷わないように書く
            // （requirements.md §3.3、2026-10-30 Kazuya さん「こういうのは一般人はわかんないんですよ。…明記しておいてくださいね。」）
            SettingsCaption("この 2 つの設定は、履歴ウインドウの右下の「コピー ⌘⏎」などのボタンには反映されません。ボタンの透け方は Mac のシステム設定に従います。")
                .padding(.horizontal, 4)
                // モック: 説明と箱の間は 10（見出しとの間 8 に 2 を足す）
                .padding(.bottom, 2)
            // モック: 2 つを 1 つの箱に、線を引かずに間 12 で並べる（箱の中の上下 12・左右 14）
            SettingsBox {
                VStack(alignment: .leading, spacing: 12) {
                    sliderRow(
                        title: "不透明度",
                        value: Binding(
                            get: { (appearance.opacity * 100).rounded() },
                            set: { appearance.opacity = min(max($0, 10), 100) / 100 }
                        ),
                        range: 10...100,
                        unit: "%",
                        caption: "低いほど後ろが透けて見えます。標準は 70%"
                    )
                    if appearance.usesSystemMaterial {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("後ろをぼかす").font(.system(size: SettingsFont.item))
                                SettingsCaption("この Mac では強さを変えられないため、ぼかすかどうかだけを選べます")
                            }
                            Spacer(minLength: 0)
                            Toggle("後ろをぼかす", isOn: Binding(
                                get: { appearance.blurRadius > 0 },
                                set: { appearance.blurRadius = $0 ? BlurPreset.defaultRadius : 0 }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                    } else {
                        sliderRow(
                            title: "ぼかしの強さ",
                            value: Binding(
                                get: { Double(appearance.blurRadius) },
                                set: { appearance.blurRadius = Int(min(max($0, 0), Double(BlurPreset.maxRadius)).rounded()) }
                            ),
                            range: 0...Double(BlurPreset.maxRadius),
                            unit: "",
                            caption: appearance.blurRadius == 0 ? "0 ではぼかしません" : "強いほど後ろがぼやけます。標準は \(BlurPreset.defaultRadius)"
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, caption: String) -> some View {
        // モック: 名前との間 4、数値の欄 52、説明との間 2
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: SettingsFont.item))
                .padding(.bottom, 4)
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: 1)
                    .labelsHidden()
                    .accessibilityLabel(title)
                TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(title)（数値）")
                Text(unit)
                    .frame(width: 18, alignment: .leading)
                    .foregroundStyle(SettingsColor.sub)
            }
            SettingsCaption(caption)
                .padding(.top, 2)
        }
    }

    // MARK: - 履歴ウインドウ

    private var historyWindow: some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            SettingsHeader("履歴ウインドウ")
            SettingsBox {
                SettingsRow(title: "文字の大きさ", description: "一覧とプレビューに使います。履歴ウインドウでは ⌘+ / ⌘− でも変えられます") {
                    levelPicker("履歴ウインドウの文字の大きさ", selection: Binding(
                        get: { appearance.historyTextSize },
                        set: { appearance.historyTextSize = $0 }
                    ))
                }
                SettingsDivider()
                // 戻したあとにまた動かしたときは、案内を消す（ボタンが「標準に戻す」に戻るのに、案内だけ残らないように）
                SettingsRow(title: "位置と大きさ", description: didResetWindow && model.isHistoryWindowStandard ? "次に開くときは、標準の位置と大きさで表示されます" : nil) {
                    if model.isHistoryWindowStandard {
                        Text("標準のままです").foregroundStyle(SettingsColor.sub)
                    } else {
                        Button("標準に戻す") {
                            model.resetHistoryWindowFrame()
                            didResetWindow = true
                        }
                        .buttonStyle(.settings)
                    }
                }
            }
        }
    }

    // MARK: - 小さいウインドウ

    private var queueWindow: some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            SettingsHeader("FIFO / LIFO の小さいウインドウ")
            SettingsBox {
                SettingsRow(title: "位置") {
                    Picker("小さいウインドウの位置", selection: Binding(
                        get: { model.hudSide },
                        set: { model.setHUDSide($0) }
                    )) {
                        ForEach(HUDSide.allCases, id: \.self) { side in
                            Text(side.displayName).tag(side)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: "文字の大きさ") {
                    levelPicker("小さいウインドウの文字の大きさ", selection: Binding(
                        get: { model.hudTextSize },
                        set: { model.setHUDTextSize($0) }
                    ))
                }
            }
        }
    }

    private func levelPicker(_ label: String, selection: Binding<TextSizeLevel>) -> some View {
        Picker(label, selection: selection) {
            ForEach(TextSizeLevel.allCases, id: \.self) { level in
                Text(level.displayName).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// 見本: 縮小した履歴ウインドウと小さいウインドウを、不透明度・ぼかし・文字の大きさ・位置・アクセントカラーで描く
private struct AppearanceSample: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // モック: 見出しと同じ灰色の太字。絵との間 6、左に 2
            Text("見本")
                .font(.system(size: SettingsFont.text, weight: .semibold))
                .foregroundStyle(SettingsColor.sub)
                .padding(.leading, 2)
                .padding(.bottom, -2)
            ZStack(alignment: .top) {
                backdrop
                historyWindow
                    .padding(.top, 54)
                    .padding(.horizontal, 18)
                // 帯は画面の端に、上から下までくっつける（§3.6）
                queueWindow
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.hudSide == .left ? .leading : .trailing)
            }
            .frame(height: 330)
            // モック: 角 12、縁なし
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
            SettingsCaption("変更はすぐに、この見本と表示中の小さいウインドウに反映されます。", lineHeight: 1.6)
                .padding(.horizontal, 2)
        }
    }

    /// 後ろの画面の代わり。透け具合とぼかしが分かるよう、モックと同じく、斜めのグラデーションに 3 つの色の四角を置く
    /// （地 ライト #C9D6E3→#9FB0C4、ダーク #2A3445→#121821。四角は #E07A5F・#5B8BD0・#81B29A、角 8）
    private var backdrop: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [SettingsColor.dynamic(light: SettingsColor.rgb(0xC9, 0xD6, 0xE3), dark: SettingsColor.rgb(0x2A, 0x34, 0x45), system: nil),
                                    SettingsColor.dynamic(light: SettingsColor.rgb(0x9F, 0xB0, 0xC4), dark: SettingsColor.rgb(0x12, 0x18, 0x21), system: nil)],
                           startPoint: .top, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: SettingsColor.rgb(0xE0, 0x7A, 0x5F)))
                .frame(width: 120, height: 100).offset(x: 14, y: 20)
            RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: SettingsColor.rgb(0x5B, 0x8B, 0xD0)))
                .frame(width: 120, height: 110).offset(x: 110, y: 130)
            RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: SettingsColor.rgb(0x81, 0xB2, 0x9A)))
                .frame(width: 100, height: 70).offset(x: 30, y: 210)
        }
    }

    /// ぼかしは見本の大きさに合わせて弱める（見本は実物の約 1/3）
    private var sampleBlur: CGFloat { CGFloat(appearance.blurRadius) / 3 }

    private var glass: some View {
        ZStack {
            backdrop.blur(radius: sampleBlur)
            Color.panelBase.opacity(appearance.opacity)
        }
    }

    private var historyWindow: some View {
        let scale = appearance.historyTextSize.ratio
        return VStack(alignment: .leading, spacing: 5) {
            Text("Kasane").font(.system(size: 7, weight: .semibold)).frame(maxWidth: .infinity)
            // 検索欄に「push」と打ったところ。選んだ行のアイコンと、一致した文字にアクセントを使う（settings-screen §3 外観の見本）
            Text("push")
                .font(.system(size: 6.5))
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 10, alignment: .leading)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
            ForEach(Array(Self.sampleRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index == 0 ? appearance.accent.color : Color.primary.opacity(0.18))
                        .frame(width: 8 * scale, height: 8 * scale)
                    Text(sampleTitle(row, scale: scale))
                        .font(.system(size: 7.5 * scale))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 1.5)
                .background(index == 0 ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 3))
            }
            // 実物と同じく、右下に浮く両端の丸い帯にする（requirements.md §3.3。実物はガラスだが、見本は縁と薄い地で形だけ描く）
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    Text("ペースト")
                        .font(.system(size: 6.5, weight: .semibold))
                        .foregroundStyle(appearance.accent.foreground)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(appearance.accent.color, in: Capsule())
                    // ペースト以外の 5 つ（書式なし・コピー・ピン・削除・詳細）。実物と同じ 6 つにする
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule().fill(Color.primary.opacity(0.12)).frame(width: 14, height: 5)
                            .padding(.horizontal, 1.5)
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
            }
            .padding(.top, 2)
        }
        .padding(8)
        // モック: 角 12、縁 1px（ライト 白 70%、ダーク 白 12%）、影 0 12 30 黒 35%
        .background(glass.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Self.panelBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 15, y: 12)
    }

    private static let panelBorder = SettingsColor.dynamic(light: NSColor.white.withAlphaComponent(0.7), dark: NSColor.white.withAlphaComponent(0.12), system: nil)

    private static let sampleRows = ["git push origin main", "git push --tags", "push 通知の設定"]

    /// 見本の行の題名。「push」の後ろをアクセントの色で塗り、太字にする（実物と同じ計算）
    private func sampleTitle(_ title: String, scale: CGFloat) -> AttributedString {
        var result = AttributedString(title)
        typealias Attributes = AttributeScopes.SwiftUIAttributes
        for match in MatchHighlighter.ranges(query: "push", title: title) {
            guard let range = Range(NSRange(location: match.lowerBound, length: match.count), in: result) else { continue }
            result[range][Attributes.BackgroundColorAttribute.self] = appearance.accent.matchFill
            result[range][Attributes.ForegroundColorAttribute.self] = AccentColor.onMatchFill
            result[range][Attributes.FontAttribute.self] = .system(size: 7.5 * scale, weight: .bold)
        }
        return result
    }

    private var queueWindow: some View {
        let scale = model.hudTextSize.ratio
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text("FIFO")
                    .font(.system(size: 6.5 * scale, weight: .bold))
                    .foregroundStyle(appearance.accent.foreground)
                    .padding(.horizontal, 3)
                    .background(appearance.accent.color, in: Capsule())
                Text("残り 2 件").font(.system(size: 6.5 * scale)).foregroundStyle(.secondary)
            }
            sampleCard(number: 1, title: "会議のメモ", isNext: true, scale: scale)
            sampleCard(number: 2, title: "見積書.pdf", isNext: false, scale: scale)
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(width: 84 * scale, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(glass)
    }

    /// 帯の 1 件のカード。次に貼る 1 件は、番号の丸をアクセントの色そのもので塗り、地を明るくする（実物と同じ）
    private func sampleCard(number: Int, title: String, isNext: Bool, scale: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 3) {
            Text("\(number)")
                .font(.system(size: 5.5 * scale, weight: .bold, design: .rounded))
                .frame(width: 8 * scale, height: 8 * scale)
                .foregroundStyle(isNext ? appearance.accent.foreground : Color.primary)
                .background(Circle().fill(isNext ? appearance.accent.color : Color.primary.opacity(0.12)))
            Text(title).font(.system(size: 6.5 * scale)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(3)
        .background(Color.primary.opacity(isNext ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 3))
    }
}

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

    var body: some View {
        FittingScroll {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
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
            VStack(alignment: .leading, spacing: 6) {
                Text("アクセントカラー").font(.system(size: SettingsFont.item))
                SettingsCaption("ペーストボタン、検索で一致した文字、FIFO / LIFO の小さいウインドウの印と番号に使います")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 10) {
                    ForEach(AccentColor.allCases, id: \.self) { accent in
                        accentButton(accent)
                    }
                }
                .padding(.top, 6)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("アクセントカラー")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func accentButton(_ accent: AccentColor) -> some View {
        let selected = appearance.accent == accent
        return Button {
            appearance.accent = accent
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(accent == .system
                              ? AnyShapeStyle(AngularGradient(colors: [.blue, .purple, .pink, .orange, .green, .blue], center: .center))
                              : AnyShapeStyle(accent.color))
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.75), lineWidth: 2)
                            .frame(width: 28, height: 28)
                    }
                }
                .frame(width: 30, height: 30)
                Text(accent.displayName)
                    .font(.system(size: SettingsFont.colorName))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 背景

    private var background: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
            SettingsHeader(title: "背景（履歴ウインドウと小さいウインドウ）") {
                if !model.isBackgroundStandard {
                    Button("標準に戻す") { model.resetBackground() }
                }
            }
            SettingsBox {
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
                SettingsDivider()
                if appearance.usesSystemMaterial {
                    SettingsRow(title: "後ろをぼかす", description: "この Mac では強さを変えられないため、ぼかすかどうかだけを選べます") {
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
        }
        .padding(.top, 4)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: SettingsFont.item))
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: 1)
                    .labelsHidden()
                    .accessibilityLabel(title)
                TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(title)（数値）")
                Text(unit)
                    .frame(width: 14, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
            SettingsCaption(caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - 履歴ウインドウ

    private var historyWindow: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
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
                        Text("標準のままです").foregroundStyle(.secondary)
                    } else {
                        Button("標準に戻す") {
                            model.resetHistoryWindowFrame()
                            didResetWindow = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - 小さいウインドウ

    private var queueWindow: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
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
            Text("見本").font(.system(size: SettingsFont.text, weight: .semibold))
            ZStack(alignment: .top) {
                backdrop
                historyWindow
                    .padding(.top, 54)
                    .padding(.horizontal, 18)
                queueWindow
                    .frame(maxWidth: .infinity, alignment: model.hudSide == .left ? .topLeading : .topTrailing)
                    .padding(8)
            }
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .accessibilityHidden(true)
            SettingsCaption("変更はすぐに、この見本と表示中の小さいウインドウに反映されます。")
        }
    }

    /// 後ろの画面の代わり。透け具合とぼかしが分かるよう、色と線のある絵にする
    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 0.78), Color(red: 0.86, green: 0.62, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 12) {
                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(index.isMultiple(of: 2) ? 0.55 : 0.3))
                        .frame(width: CGFloat(80 + (index * 37) % 120), height: 6)
                        .frame(maxWidth: .infinity, alignment: index.isMultiple(of: 3) ? .leading : .trailing)
                }
            }
            .padding(14)
        }
    }

    /// ぼかしは見本の大きさに合わせて弱める（見本は実物の約 1/3）
    private var sampleBlur: CGFloat { CGFloat(appearance.blurRadius) / 3 }

    private var glass: some View {
        ZStack {
            backdrop.blur(radius: sampleBlur)
            Color(nsColor: .windowBackgroundColor).opacity(appearance.opacity)
        }
    }

    private var historyWindow: some View {
        let scale = appearance.historyTextSize.ratio
        return VStack(alignment: .leading, spacing: 5) {
            Text("Kasane").font(.system(size: 7, weight: .semibold)).frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)).frame(height: 10)
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 8 * scale, height: 8 * scale)
                    Text(["git push origin main", "会議のメモ", "https://example.com", "見積書.pdf"][index])
                        .font(.system(size: 7.5 * scale))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 1.5)
                .background(index == 0 ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 3))
            }
            HStack(spacing: 3) {
                Text("ペースト")
                    .font(.system(size: 6.5, weight: .semibold))
                    .foregroundStyle(appearance.accent.foreground)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(appearance.accent.color, in: RoundedRectangle(cornerRadius: 3))
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1)).frame(width: 24, height: 11)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(8)
        .background(glass.clipShape(RoundedRectangle(cornerRadius: 8)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }

    private var queueWindow: some View {
        let scale = model.hudTextSize.ratio
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text("FIFO")
                    .font(.system(size: 6.5 * scale, weight: .bold))
                    .foregroundStyle(appearance.accent.foreground)
                    .padding(.horizontal, 3)
                    .background(appearance.accent.color, in: RoundedRectangle(cornerRadius: 2))
                Text("2 件").font(.system(size: 6.5 * scale)).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Text("1").font(.system(size: 6.5 * scale, weight: .bold)).foregroundStyle(appearance.accent.text)
                Text("会議のメモ").font(.system(size: 6.5 * scale))
            }
            HStack(spacing: 3) {
                Text("2").font(.system(size: 6.5 * scale)).foregroundStyle(.secondary)
                Text("見積書.pdf").font(.system(size: 6.5 * scale))
            }
        }
        .padding(6)
        .frame(width: 78 * scale, alignment: .leading)
        .background(glass.clipShape(RoundedRectangle(cornerRadius: 6)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

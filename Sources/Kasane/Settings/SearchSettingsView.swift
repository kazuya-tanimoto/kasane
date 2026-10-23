import KasaneCore
import SwiftUI

/// 検索のタブ（settings-screen-2026-10-22.md §3「検索」、見せ方は search-looseness-2026-10-22.md）
struct SearchSettingsView: View {
    @ObservedObject var model: SettingsModel

    /// 例。出る / 出ないは表に書かず、今の段階で実際に照合して決める（表と食い違わないことは単体テストで確かめる）
    private static let examples: [(query: String, item: String, note: String)] = [
        ("hstvw", "HistoryView", "文字を飛ばす"),
        ("gpr", "github pull request", "頭文字だけ"),
        ("slack", "see the list and click OK", "関係ない項目"),
    ]

    private static let syntax: [(query: String, text: String)] = [
        ("gtps", "文字を飛ばしても見つかる（git push）"),
        ("kaigi", "ローマ字で日本語も見つかる（会議）"),
        ("make test", "空白で区切ると、すべての語を含む項目だけ"),
        ("'kaigi", "' を付けると、その文字が続けて並ぶ項目だけ"),
    ]

    var body: some View {
        FittingScroll {
            VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
                SettingsBox {
                    looseness
                }
                SettingsBox {
                    SettingsRow(title: "開いたときに英数に切り替える", description: "閉じると元の入力ソースに戻ります") {
                        Toggle("開いたときに英数に切り替える", isOn: Binding(
                            get: { model.switchesToASCII },
                            set: { model.setSwitchesToASCII($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }
                .padding(.top, 6)

                SettingsHeader("検索のしかた")
                SettingsBox {
                    ForEach(Array(Self.syntax.enumerated()), id: \.offset) { index, entry in
                        if index > 0 { SettingsDivider() }
                        HStack(spacing: 16) {
                            Text(entry.query)
                                .font(.system(size: 12.5, design: .monospaced))
                                .frame(width: 96, alignment: .leading)
                            Text(entry.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    private var looseness: some View {
        let levels = SearchLooseness.allCases
        let index = Binding<Double>(
            get: { Double(levels.firstIndex(of: model.searchLooseness) ?? 1) },
            set: { model.setSearchLooseness(levels[min(max(Int($0.rounded()), 0), levels.count - 1)]) }
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("検索のゆるさ")
                Spacer()
                Text(model.searchLooseness.displayName)
                    .foregroundStyle(.secondary)
            }
            Slider(value: index, in: 0...Double(levels.count - 1), step: 1)
                .labelsHidden()
                .accessibilityLabel("検索のゆるさ")
                .accessibilityValue(model.searchLooseness.displayName)
            HStack {
                SettingsCaption(levels.first!.displayName)
                Spacer()
                SettingsCaption(levels.last!.displayName)
            }
            SettingsCaption("ゆるめにするほど、打った文字が離れていても見つかります。そのぶん、関係ない項目も増えます。")
            VStack(alignment: .leading, spacing: 6) {
                Text("例").font(.system(size: 12, weight: .semibold))
                ForEach(Self.examples, id: \.query) { example in
                    exampleRow(example)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// 「出る」は青、「出ない」は灰色。良し悪しではなく、出るかどうかで色を分ける（2026-10-22 決定）
    private func exampleRow(_ example: (query: String, item: String, note: String)) -> some View {
        let shown = FuzzyMatcher.score(
            example.query,
            text: TextNormalizer.normalize(example.item),
            spanRatio: model.searchLooseness.spanRatio
        ) != nil
        return HStack(spacing: 10) {
            Text(shown ? "出る" : "出ない")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(shown ? Color.blue : Color.secondary)
                .frame(width: 44, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(shown ? Color.blue.opacity(0.14) : Color(nsColor: .quaternaryLabelColor).opacity(0.4))
                )
            Text("\(Text(example.query).font(.system(size: 12.5, design: .monospaced))) → \(example.item)（\(example.note)）")
            Spacer(minLength: 0)
        }
    }
}

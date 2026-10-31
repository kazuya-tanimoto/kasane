import AppKit
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

                SettingsHeader("検索のしかた")
                // モック: 箱の中の左右 14・上下 6。行は上下 6 で、線は箱の中の余白の内側に引く。書き方は灰色の札に等幅で
                SettingsBox {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(Self.syntax.enumerated()), id: \.offset) { index, entry in
                            if index > 0 { SettingsDivider() }
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(entry.query)
                                    .font(.system(size: SettingsFont.text, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .frame(minWidth: 92, alignment: .leading)
                                    .background(SettingsColor.chip, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(entry.text)
                                    .foregroundStyle(SettingsColor.sub)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
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
        // モック: 箱の中の上下 14・左右 16、間 10
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("検索のゆるさ").font(.system(size: SettingsFont.item))
                Spacer()
                // 今の段階の名前は太字（モック）。色はシステムの灰（requirements.md「設定画面の部品の色はシステムの色」）、大きさは決めた表の 14pt
                Text(model.searchLooseness.displayName)
                    .font(.system(size: SettingsFont.text, weight: .semibold))
                    .foregroundStyle(SettingsColor.sub)
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
            .padding(.top, -4)
            SettingsCaption("ゆるめにするほど、打った文字が離れていても見つかります。そのぶん、関係ない項目も増えます。", lineHeight: 1.6)
            // モック: 例は一段沈んだ地の中に置く（角 10、上下 10・左右 12、間 6）
            VStack(alignment: .leading, spacing: 6) {
                SettingsCaption("例")
                ForEach(Self.examples, id: \.query) { example in
                    exampleRow(example)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsColor.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// 「出る」は青、「出ない」は灰色。良し悪しではなく、出るかどうかで色を分ける（2026-10-22 決定）。
    /// 札の形と色はモックの値（両端が丸い、14pt の太字、出る: ライト 地 rgba(22,94,131,0.12)・字 #14527A、
    /// ダーク 地 rgba(95,163,207,0.22)・字 #9FCBE6。出ない: ライト 地 黒 7%・字 #5C5F66、ダーク 地 白 8%・字 白 62%）
    private func exampleRow(_ example: (query: String, item: String, note: String)) -> some View {
        let shown = FuzzyMatcher.score(
            example.query,
            text: TextNormalizer.normalize(example.item),
            spanRatio: model.searchLooseness.spanRatio
        ) != nil
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(shown ? "出る" : "出ない")
                .font(.system(size: SettingsFont.text, weight: .semibold))
                .foregroundStyle(shown ? Self.shownText : Self.hiddenText)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                // 3.5 文字分（14pt × 3.5）。「出ない」でも札の幅がそろう
                .frame(minWidth: SettingsFont.text * 3.5)
                .background(Capsule().fill(shown ? Self.shownFill : Self.hiddenFill))
            // 14pt（settings-screen-2026-10-22.md §3 の文字の表。モックの絵は 15 で描いているが、決めた表に従う）
            Text("\(Text(example.query).font(.system(size: SettingsFont.text, design: .monospaced))) → \(example.item)（\(example.note)）")
            Spacer(minLength: 0)
        }
    }

    // 色はシステムの色（main と同じ。requirements.md「設定画面の部品の色はシステムの色を使う」）
    private static let shownFill = Color.blue.opacity(0.14)
    private static let shownText = Color.blue
    private static let hiddenFill = Color(nsColor: .quaternaryLabelColor).opacity(0.4)
    private static let hiddenText = SettingsColor.sub
}

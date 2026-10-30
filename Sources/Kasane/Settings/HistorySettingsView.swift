import AppKit
import KasaneStore
import SwiftUI
import UniformTypeIdentifiers

/// 履歴のタブ（settings-screen-2026-10-22.md §3「履歴」）
struct HistorySettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var selectedApp: String?

    /// 一覧の 1 行の高さと、見える行の数（5 行分。2 行半では、追加したアプリを確かめるたびにスクロールすることになるため）。
    /// 高さは 15pt の名前で窮屈にならないよう 36pt
    private static let appRowHeight: CGFloat = 36
    private static let visibleAppRows: CGFloat = 5

    var body: some View {
        FittingScroll {
            VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
                SettingsBox {
                    SettingsRow(title: "履歴の保存件数", description: "超えた分は古いものから削除されます。ピン留めした項目は数えません") {
                        Picker("履歴の保存件数", selection: Binding(
                            get: { model.historyLimit },
                            set: { model.setHistoryLimit($0) }
                        )) {
                            ForEach(AppSettings.historyLimitOptions, id: \.self) { limit in
                                Text("\(limit.formatted()) 件").tag(limit)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsDivider()
                    SettingsRow(title: "並び順", description: "検索欄が空のときの並び順です") {
                        Picker("並び順", selection: Binding(
                            get: { model.sortOrder },
                            set: { model.setSortOrder($0) }
                        )) {
                            ForEach(HistorySortOrder.allCases, id: \.self) { order in
                                Text(order.displayName).tag(order)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsDivider()
                    SettingsRow(
                        title: "URL のタイトルと画像を表示",
                        description: "履歴ウインドウで見えている URL と、FIFO / LIFO モード中にコピーした URL のページに、自動でアクセスします。パスワード再設定など、1 回限りのリンクは無効になることがあります"
                    ) {
                        Toggle("URL のタイトルと画像を表示", isOn: Binding(
                            get: { model.fetchesLinkPreviews },
                            set: { model.setFetchesLinkPreviews($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }

                SettingsHeader("履歴に残さないアプリ")
                SettingsCaption("追加したアプリでコピーした内容は、履歴に残しません。パスワードなど、コピー元のアプリが残さないよう指定したものは、追加しなくても残しません。")
                    .padding(.horizontal, 4)
                excludedAppsList

                HStack(spacing: 12) {
                    // ピン留め以外が 0 件のときは押せなくする（押しても何も消えないため）
                    Button {
                        model.actions.clearHistory()
                    } label: {
                        Text("履歴を削除…").foregroundStyle(model.hasUnpinnedHistory ? Color.red : Color.secondary)
                    }
                    .disabled(!model.hasUnpinnedHistory)
                    SettingsCaption("ピン留めした項目と、FIFO / LIFO のキューは削除されません")
                }
                .padding(.top, 14)
                .padding(.horizontal, 4)
            }
        }
    }

    private var excludedAppsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.excludedApps) { app in
                        appRow(app)
                    }
                }
            }
            .frame(height: Self.appRowHeight * Self.visibleAppRows)
            .overlay {
                if model.excludedApps.isEmpty {
                    SettingsCaption("アプリはまだありません。＋ で追加できます")
                }
            }
            Divider()
            HStack(spacing: 0) {
                Menu {
                    let running = model.runningAppsToAdd()
                    if !running.isEmpty {
                        Section("開いているアプリ") {
                            ForEach(running) { app in
                                Button {
                                    model.addExcludedApp(bundleID: app.bundleID)
                                    selectedApp = app.bundleID
                                } label: {
                                    Label {
                                        Text(app.name)
                                    } icon: {
                                        Image(nsImage: Self.icon(for: app))
                                    }
                                }
                            }
                        }
                        Divider()
                    }
                    Button("ほかのアプリを選ぶ…") {
                        model.chooseAppToAdd()
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 20)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("アプリを追加")
                Divider().frame(height: 16)
                Button {
                    guard let selectedApp else { return }
                    model.removeExcludedApp(bundleID: selectedApp)
                    self.selectedApp = nil
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(selectedApp == nil)
                .accessibilityLabel("選んだアプリを一覧から外す")
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// 1 行（アイコンとアプリの名前）。バンドル ID は行に書かず、ポインタを重ねたときに出す
    private func appRow(_ app: SettingsModel.ExcludedApp) -> some View {
        let selected = selectedApp == app.bundleID
        return HStack(spacing: 8) {
            Image(nsImage: Self.icon(for: app))
                .resizable()
                .frame(width: 20, height: 20)
            Text(app.name)
                .font(.system(size: SettingsFont.item))
                .foregroundStyle(selected ? Color(nsColor: .alternateSelectedControlTextColor) : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.appRowHeight)
        .background(selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedApp = app.bundleID }
        .help(app.bundleID)
    }

    private static func icon(for app: SettingsModel.ExcludedApp) -> NSImage {
        let image = app.url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .application)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

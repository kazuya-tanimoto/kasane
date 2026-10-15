import AppKit
import KasaneCore
import KasaneStore
import SwiftUI

/// 履歴ウインドウ（デザインモック「C案 改訂版」）
///
/// - 1行目: 検索欄
/// - 2行目: モード（FIFO/LIFO 中のみ）、種類の絞り込み、操作ボタン、詳細の切り替え
/// - 本体: 左に履歴かキューのリスト、右に大きなプレビュー（⌘I で詳細）
struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @ObservedObject var appearance: AppearanceSettings
    @FocusState private var searchFocused: Bool

    static let cornerRadius: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Toolbar(model: model)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            HStack(spacing: 12) {
                Group {
                    if model.isShowingQueue {
                        QueueListView(model: model)
                    } else {
                        ItemListView(model: model)
                    }
                }
                .frame(width: 350)
                PreviewPane(content: model.preview, showsDetails: model.showsDetails)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: HistoryPanelController.size.width, height: HistoryPanelController.size.height)
        .background(PanelBackground(appearance: appearance, cornerRadius: Self.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) {
            searchFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(
                model.isShowingQueue ? "入力すると履歴を検索します" : "履歴を検索（例: kaigi、otsu tani）",
                text: $model.query
            )
            .textFieldStyle(.plain)
            .font(.system(size: 19))
            .focused($searchFocused)
            if !model.isShowingQueue {
                Text("\(model.pinned.count + model.others.count) 件")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - ツールバー（1行）

private struct Toolbar: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        HStack(spacing: 6) {
            if let mode = model.queueMode {
                Button {
                    model.toggleListMode()
                } label: {
                    Text("\(mode == .fifo ? "FIFO" : "LIFO") \(model.queueRows.count)")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(ChipStyle(isOn: model.isShowingQueue, onColor: .orange))
                .help("Tab でキューと履歴を切り替え")
                Divider().frame(height: 18).padding(.horizontal, 4)
            }
            if model.isShowingQueue {
                Text("⌘V で上から順に貼り付け · Tab で履歴に切り替え")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(KindFilter.allCases) { filter in
                    Button(filter.label) { model.kindFilter = filter }
                        .buttonStyle(ChipStyle(isOn: model.kindFilter == filter, onColor: .primary))
                }
            }
            Spacer(minLength: 8)
            Button("ペースト ⏎") { model.activateSelection(.paste) }
                .buttonStyle(ActionStyle(isPrimary: true))
            Button("書式なし ⇧⏎") { model.activateSelection(.plainText) }
                .buttonStyle(ActionStyle(isPrimary: false))
            Button("コピー ⌥⏎") { model.activateSelection(.copyOnly) }
                .buttonStyle(ActionStyle(isPrimary: false))
            Button {
                model.showsDetails.toggle()
            } label: {
                Label("⌘I", systemImage: "info.circle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(ActionStyle(isPrimary: false, isOn: model.showsDetails))
            .help("詳細を表示（⌘I）")
        }
    }
}

/// 絞り込みやモードの丸いボタン
private struct ChipStyle: ButtonStyle {
    var isOn: Bool
    var onColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .foregroundStyle(isOn ? (onColor == .primary ? Color(nsColor: .windowBackgroundColor) : .white) : .primary)
            .background(Capsule().fill(isOn ? onColor : Color.primary.opacity(0.08)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// ペーストなどの操作ボタン
private struct ActionStyle: ButtonStyle {
    var isPrimary: Bool
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isPrimary ? .white : (isOn ? Color(nsColor: .windowBackgroundColor) : .primary))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPrimary ? Color.orange : (isOn ? Color.primary : Color.primary.opacity(0.08)))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - 履歴のリスト

private struct ItemListView: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !model.pinned.isEmpty {
                        SectionHeader(title: "ピン留め")
                        ForEach(model.pinned) { item in
                            row(item)
                        }
                    }
                    if !model.others.isEmpty {
                        SectionHeader(title: model.query.isEmpty ? "履歴" : "検索結果")
                        ForEach(model.others) { item in
                            row(item)
                        }
                    }
                    if model.pinned.isEmpty && model.others.isEmpty {
                        EmptyState(
                            text: !model.query.isEmpty || model.kindFilter != .all
                                ? "一致する項目はありません"
                                : (model.isLoaded ? "まだ履歴がありません" : "読み込み中…")
                        )
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func row(_ item: ClipSummary) -> some View {
        ItemRow(
            item: item,
            isSelected: model.selectedID == item.id,
            shortcut: model.shortcutNumber(for: item.id),
            model: model
        )
        .id(item.id)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.activate(id: item.id, action: .paste)
        }
        .simultaneousGesture(TapGesture().onEnded {
            model.select(item.id)
        })
    }
}

// MARK: - FIFO / LIFO のキュー

private struct QueueListView: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "\(model.queueMode == .lifo ? "LIFO" : "FIFO") のキュー（貼り付ける順）")
                    ForEach(model.queueRows) { row in
                        QueueRowView(row: row, isSelected: model.queueSelection == row.id)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.queueSelection = row.id }
                    }
                    if model.queueRows.isEmpty {
                        EmptyState(text: "まだ何もありません。\nコピーすると、ここに順番に積まれます。")
                    }
                }
                .padding(2)
            }
            .onChange(of: model.queueSelection) { _, index in
                proxy.scrollTo(index)
            }
        }
    }
}

private struct QueueRowView: View {
    let row: QueueRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // 貼り付ける順番。10 件を超えると 2 桁以上になるので、丸ではなく横に伸びる札にする
            Text("\(row.id + 1)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 7)
                .frame(minWidth: 30, minHeight: 26)
                .foregroundStyle(row.id == 0 ? Color.white : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(row.id == 0 ? Color.orange : Color.primary.opacity(0.08))
                )
                .fixedSize()
            VStack(alignment: .leading, spacing: 3) {
                Text(row.summary.title.isEmpty ? " " : row.summary.title)
                    .font(.system(size: 13))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(row.summary.kind.displayName)
                        .fontWeight(.semibold)
                        .foregroundStyle(row.summary.kind.tint)
                    Text(row.id == 0 ? "次の ⌘V で貼り付け" : "\(row.id + 1) 番目")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(SelectionBackground(isSelected: isSelected))
    }
}

// MARK: - 行

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct EmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }
}

private struct SelectionBackground: View {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? (colorScheme == .dark ? Color.white.opacity(0.13) : Color.white) : Color.clear)
            .shadow(color: isSelected && colorScheme == .light ? .black.opacity(0.10) : .clear, radius: 5, y: 2)
    }
}

private struct ItemRow: View {
    let item: ClipSummary
    let isSelected: Bool
    let shortcut: Int?
    let model: HistoryModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ItemIcon(item: item, model: model)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? " " : item.title)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(item.kind.displayName)
                        .fontWeight(.semibold)
                        .foregroundStyle(item.kind.tint)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.secondary)
                    }
                    if let shortcut {
                        Text("⌘\(shortcut)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(SelectionBackground(isSelected: isSelected))
    }

    private var subtitle: String {
        let date = Formatters.relative.localizedString(for: item.copiedAt, relativeTo: Date())
        if let app = item.sourceAppName {
            return "\(app) · \(date)"
        }
        return date
    }
}

/// 種類の色の四角。画像はサムネイル、それ以外は種類のアイコン（右下にコピー元のアプリ）
private struct ItemIcon: View {
    let item: ClipSummary
    let model: HistoryModel
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if item.kind == .image, let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(item.kind.tint.opacity(0.18))
                    .overlay {
                        Image(systemName: item.kind.symbolName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(item.kind.tint)
                    }
            }
            if let icon = AppIconCache.icon(bundleID: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .offset(x: 4, y: 4)
            }
        }
        .task(id: item.id) {
            if item.kind == .image {
                thumbnail = await model.thumbnail(for: item.id)
            }
        }
    }
}

extension ClipKind {
    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "doc.richtext"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    var displayName: String {
        switch self {
        case .text: return "テキスト"
        case .richText: return "リッチテキスト"
        case .url: return "URL"
        case .image: return "画像"
        case .file: return "ファイル"
        }
    }

    /// 種類ごとの色（モックと同じ）
    var tint: Color {
        switch self {
        case .text: return Color(red: 0.23, green: 0.51, blue: 0.96)
        case .richText: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .url: return Color(red: 0.08, green: 0.72, blue: 0.65)
        case .image: return Color(red: 0.98, green: 0.45, blue: 0.09)
        case .file: return Color(red: 0.58, green: 0.64, blue: 0.72)
        }
    }
}

@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func icon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let icon = cache[bundleID] { return icon }
        if missing.contains(bundleID) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

enum Formatters {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

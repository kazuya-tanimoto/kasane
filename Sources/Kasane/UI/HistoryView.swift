import AppKit
import KasaneStore
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if let info = model.queueInfo {
                QueueBanner(info: info)
            }
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                ItemListView(model: model)
                    .frame(width: 330)
                Divider().opacity(0.5)
                PreviewPane(content: model.preview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().opacity(0.5)
            FooterHints()
        }
        .frame(width: HistoryPanelController.size.width, height: HistoryPanelController.size.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) {
            searchFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("クリップボードの履歴を検索", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($searchFocused)
            if model.sortOrder == .mostPasted {
                Label("貼り付け回数順", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

/// FIFO / LIFO モード中に、キューの中身と次に貼り付ける項目を出す
private struct QueueBanner: View {
    let info: QueueInfo

    var body: some View {
        HStack(spacing: 8) {
            Text(info.mode == .fifo ? "FIFO" : "LIFO")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                .foregroundStyle(.white)
            if let next = info.titles.first {
                Text("次: \(next)")
                    .lineLimit(1)
                    .font(.callout)
                Spacer()
                Text("残り \(info.titles.count) 件")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("コピーするとここに積まれます。⌘V で順に貼り付けます")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}

private struct ItemListView: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
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
                        EmptyState(isSearching: !model.query.isEmpty, isLoaded: model.isLoaded)
                    }
                }
                .padding(8)
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

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct EmptyState: View {
    let isSearching: Bool
    let isLoaded: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isSearching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(isSearching ? "一致する項目はありません" : (isLoaded ? "まだ履歴がありません" : "読み込み中…"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

private struct ItemRow: View {
    let item: ClipSummary
    let isSelected: Bool
    let shortcut: Int?
    let model: HistoryModel

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(item: item, model: model)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? " " : item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
        )
    }

    private var subtitle: String {
        let date = Formatters.relative.localizedString(for: item.copiedAt, relativeTo: Date())
        if let app = item.sourceAppName {
            return "\(app) · \(date)"
        }
        return date
    }
}

private struct ItemIcon: View {
    let item: ClipSummary
    let model: HistoryModel
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if item.kind == .image, let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else if let icon = AppIconCache.icon(bundleID: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: item.kind.symbolName)
                            .font(.system(size: 8, weight: .bold))
                            .padding(2)
                            .background(Circle().fill(.regularMaterial))
                            .offset(x: 3, y: 3)
                    }
            } else {
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.id) {
            if item.kind == .image {
                thumbnail = await model.thumbnail(for: item.id)
            }
        }
    }
}

private struct FooterHints: View {
    var body: some View {
        HStack(spacing: 14) {
            hint("⏎", "ペースト")
            hint("⇧⏎", "書式なし")
            hint("⌥⏎", "コピーのみ")
            hint("⌘1–9", "直接ペースト")
            hint("⌘P", "ピン留め")
            hint("⌘⌫", "削除")
            Spacer()
            Text("Kasane")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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

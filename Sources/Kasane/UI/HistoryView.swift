import AppKit
import KasaneCore
import KasaneStore
import SwiftUI

/// 履歴ウインドウ（デザインモック「C案 改訂版」）
///
/// - 一番上: 「Kasane」の帯（つかんでウインドウを動かす）
/// - 1行目: 検索欄
/// - 2行目: 種類の絞り込み、操作ボタン、詳細の切り替え
/// - 本体: 左に履歴のリスト、右に大きなプレビュー（⌘I で詳細）
///
/// FIFO / LIFO 中も同じ履歴を出す。キューは画面の隅の小さいウインドウ（`QueueHUDController`）で見る
struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @ObservedObject var appearance: AppearanceSettings
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            searchBar
            Toolbar(model: model)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            HStack(spacing: 12) {
                ItemListView(model: model)
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
        .frame(
            minWidth: HistoryPanelController.minSize.width, maxWidth: .infinity,
            minHeight: HistoryPanelController.minSize.height, maxHeight: .infinity
        )
        .background(PanelBackground(appearance: appearance))
        .environment(\.kasaneAccent, appearance.accent)
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
            TextField("履歴を検索", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($searchFocused)
            Text("\(model.pinned.count + model.others.count) 件")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        // 検索欄の周りをつかんでウインドウを動かせるようにする
        .background(WindowDragArea())
    }
}

/// ウインドウの一番上の帯。一般的な Mac のアプリのタイトルバーと同じ場所で、どこをつかんでもウインドウが動く
private struct TitleBar: View {
    var body: some View {
        HStack {
            Text("Kasane")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(WindowDragArea())
    }
}

/// つかんでドラッグするとウインドウが動く領域
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - ツールバー（1行）

private struct Toolbar: View {
    @ObservedObject var model: HistoryModel
    @Environment(\.kasaneAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            ForEach(KindFilter.allCases) { filter in
                Button(filter.label) { model.kindFilter = filter }
                    .buttonStyle(ChipStyle(isOn: model.kindFilter == filter))
            }
            // 空いている所をつかんでもウインドウを動かせる
            WindowDragArea()
                .frame(minWidth: 8, maxWidth: .infinity, minHeight: 28, maxHeight: 28)
            Button("ペースト ⏎") { model.activateSelection(.paste) }
                .buttonStyle(ActionStyle(isPrimary: true, accent: accent))
            Button("書式なし ⇧⏎") { model.activateSelection(.plainText) }
                .buttonStyle(ActionStyle(isPrimary: false, accent: accent))
            // FIFO / LIFO 中の ⌥⏎ は、選んだ項目をキューに追加する（⌘C でコピーしたときと同じ）
            Button(model.queueMode == nil ? "コピー ⌥⏎" : "キューに追加 ⌥⏎") { model.activateSelection(.copyOnly) }
                .buttonStyle(ActionStyle(isPrimary: false, accent: accent))
            Button {
                model.showsDetails.toggle()
            } label: {
                Label("⌘I", systemImage: "info.circle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(ActionStyle(isPrimary: false, isOn: model.showsDetails, accent: accent))
            .help("詳細を表示（⌘I）")
        }
    }
}

/// 絞り込みの丸いボタン。
/// 選択中は macOS の切り替えボタンのように白く浮かせる（アクセントカラーはペーストと FIFO / LIFO だけに使う）
private struct ChipStyle: ButtonStyle {
    var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .foregroundStyle(isOn ? Color.raisedText : .primary)
            .background {
                if isOn {
                    RaisedFill(shape: Capsule())
                } else {
                    Capsule().fill(Color.primary.opacity(0.08))
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 選択中のボタンの、白く浮いた背景（ライトは白＋影＋薄い輪郭、ダークは白 22%＋影）
private struct RaisedFill<S: InsettableShape>: View {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        shape
            .fill(isDark ? Color.white.opacity(0.22) : Color.white)
            .overlay(shape.strokeBorder(Color.black.opacity(isDark ? 0 : 0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(isDark ? 0.3 : 0.16), radius: 1.5, y: 1)
    }
}

private extension Color {
    /// 白く浮いた背景に載せる文字の色（ライトは #1D1D1F、ダークは白）
    static let raisedText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .white
            : NSColor(srgbRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)
    })
}

/// ペーストなどの操作ボタン
private struct ActionStyle: ButtonStyle {
    var isPrimary: Bool
    var isOn = false
    var accent: AccentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isPrimary ? accent.foreground : (isOn ? Color.raisedText : .primary))
            .background {
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                if isPrimary {
                    shape.fill(accent.color)
                } else if isOn {
                    // ⌘I の詳細がオンのときは、絞り込みの選択中と同じ見た目
                    RaisedFill(shape: shape)
                } else {
                    shape.fill(Color.primary.opacity(0.08))
                }
            }
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

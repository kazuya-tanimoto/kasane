import AppKit
import KasaneCore
import KasaneStore
import SwiftUI

/// 履歴ウインドウ（デザインモック「C案 改訂版」）
///
/// - 一番上: 「Kasane」の帯（つかんでウインドウを動かす）
/// - 1行目: 検索欄
/// - 2行目: 種類の絞り込み
/// - 本体: 左に履歴のリスト、右に大きなプレビュー（⌘I で詳細）
/// - 一番下: 選んだ項目への操作ボタン
///
/// FIFO / LIFO 中も同じ履歴を出す。キューは画面の隅の小さいウインドウ（`QueueHUDController`）で見る
struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @ObservedObject var appearance: AppearanceSettings
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

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
            ActionBar(model: model)
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

    /// 検索欄。角丸の薄い塗りの中が文字を打つ場所で、塗りの外をつかむとウインドウが動く
    /// （2026-10-18 決定。詳細はデザインの ui-tweaks-2026-10-18.md）
    private var searchBar: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
            TextField("履歴を検索", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($searchFocused)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 13)
        .background(shape.fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
        // 塗りの中は、文字の上でなくてもクリックで検索欄に入れる
        .contentShape(shape)
        .onTapGesture { searchFocused = true }
        .pointerStyle(.horizontalText)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        // 検索欄の周りをつかんでウインドウを動かせるようにする
        .background(WindowDragArea())
    }
}

/// ウインドウの一番上の帯。一般的な Mac のアプリのタイトルバーと同じ場所で、どこをつかんでもウインドウが動く
private struct TitleBar: View {
    var body: some View {
        // 中央に 13pt（Mac の標準のウインドウタイトルと同じ大きさ）。2026-10-18 決定
        Text("Kasane")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.85))
            // 文字の上でも、背景の WindowDragArea でつかめるようにする
            .allowsHitTesting(false)
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

// MARK: - 絞り込み（1行）

private struct Toolbar: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(KindFilter.allCases) { filter in
                Button(filter.label) { model.kindFilter = filter }
                    .buttonStyle(ChipStyle(isOn: model.kindFilter == filter))
            }
            // 空いている所をつかんでもウインドウを動かせる
            WindowDragArea()
                .frame(minWidth: 8, maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        }
    }
}

// MARK: - 操作ボタン（一番下の帯）

/// 選んだ項目への操作ボタン。上の段（探す）と場所を分け、絞り込みのボタンと取り違えにくくする。
/// ピン留めと削除の入口もここに置く（右クリックのメニューは作らない。2026-10-18 決定）
private struct ActionBar: View {
    @ObservedObject var model: HistoryModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isPinned = model.selectedID.flatMap { model.summary(id: $0) }?.isPinned ?? false
        HStack(spacing: 6) {
            // 空いている所をつかんでもウインドウを動かせる
            WindowDragArea()
                .frame(minWidth: 8, maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            Button("ペースト ⏎") { model.activateSelection(.paste) }
                .buttonStyle(ActionStyle(isPrimary: true))
            Button("書式なし ⇧⏎") { model.activateSelection(.plainText) }
                .buttonStyle(ActionStyle())
            // FIFO / LIFO 中の ⌘⏎ は、選んだ項目をキューに追加する（⌘C でコピーしたときと同じ）
            Button(model.queueMode == nil ? "コピー ⌘⏎" : "キューに追加 ⌘⏎") { model.activateSelection(.copyOnly) }
                .buttonStyle(ActionStyle())
            Button {
                model.togglePinSelection()
            } label: {
                Label("⌘P", systemImage: isPinned ? "pin.fill" : "pin")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(ActionStyle(isOn: isPinned))
            .help(isPinned ? "ピン留めを外す（⌘P）" : "ピン留め（⌘P）")
            // ⌘⌫ でも消せるが、ボタンには ⌘D だけ書く（1 つの方がすぐ読める）
            Button {
                model.deleteSelection()
            } label: {
                Label("⌘D", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(ActionStyle())
            .help("削除（⌘D・⌘⌫）")
            Button {
                model.showsDetails.toggle()
            } label: {
                Label("⌘I", systemImage: "info.circle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(ActionStyle(isOn: model.showsDetails))
            .help("詳細を表示（⌘I）")
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 16)
        .background(WindowDragArea())
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08))
                .frame(height: 1)
        }
    }
}

/// 絞り込みの丸いボタン。
/// 選択中は macOS の切り替えボタンのように白く浮かせる（アクセントカラーは FIFO / LIFO の小さいウインドウだけに使う）
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

/// ペーストなどの操作ボタン。
/// ペーストも他と同じ色にし、太字で区別する（色付きのボタンは「選ばれている」ように見えるため。2026-10-18 決定）
private struct ActionStyle: ButtonStyle {
    var isPrimary = false
    /// ピン留め中や ⌘I の詳細がオンのとき、絞り込みの選択中と同じく白く浮かせる
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isOn ? Color.raisedText : .primary)
            .background {
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                if isOn {
                    RaisedFill(shape: shape)
                } else {
                    ActionFill(shape: shape)
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 操作ボタンのふだんの背景（ライトは黒 7%、ダークは白 12%）
private struct ActionFill<S: Shape>: View {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        shape.fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
    }
}

// MARK: - 履歴のリスト

private struct ItemListView: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    // 見出しは出さず、ピン留めとそれ以外の間に線を 1 本引くだけにする（2026-10-18 決定。
                    // ピン留めの段は自分でピン留めしたときにしか出ないので、見出しがなくても分かる）。
                    // ピン留めとそれ以外を 1 つの ForEach で描く。別々の ForEach にすると、ピン留めした行が
                    // 移った先で描き直されず、ピン留めする直前の見た目（選択中の背景、ピンの印なし）のまま残った（2026-10-18、Mac で確認）
                    let firstOtherID = model.pinned.isEmpty ? nil : model.others.first?.id
                    ForEach(model.visible) { item in
                        if item.id == firstOtherID {
                            PinDivider()
                        }
                        row(item)
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

/// ピン留めとそれ以外の履歴の境目の線（両方あるときだけ出す）
private struct PinDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.14))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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

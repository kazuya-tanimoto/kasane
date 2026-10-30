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
/// - 右下: 選んだ項目への操作ボタン。一覧とプレビューの上に浮く Liquid Glass の帯
///
/// FIFO / LIFO 中も同じ履歴を出す。キューは画面の隅の小さいウインドウ（`QueueHUDController`）で見る
struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @ObservedObject var appearance: AppearanceSettings
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    /// 右下に浮く操作ボタンの帯の高さ。一覧とプレビューの下端を、この分だけ帯に隠れない所まで送れるようにする
    @State private var actionBarHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            searchBar
            Toolbar(model: model)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            HStack(spacing: 12) {
                ItemListView(model: model)
                    .safeAreaPadding(.bottom, actionBarClearance)
                    .frame(width: appearance.historyTextSize.scaled(350))
                PreviewPane(content: model.preview, showsDetails: model.showsDetails, links: model.links)
                    .safeAreaPadding(.bottom, actionBarClearance)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, Self.contentBottomPadding)
        }
        // 帯は一覧とプレビューの上に浮かせ、下の行はガラス越しに透けて見える（requirements.md §3.3、2026-10-30 決定）
        .overlay(alignment: .bottomTrailing) {
            ActionBar(model: model)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionBarHeight = $0 }
                .padding(.trailing, ActionBar.margin)
                .padding(.bottom, ActionBar.margin)
        }
        .frame(
            minWidth: minSize.width, maxWidth: .infinity,
            minHeight: minSize.height, maxHeight: .infinity
        )
        .background(PanelBackground(appearance: appearance))
        .environment(\.kasaneAccent, appearance.accent)
        .environment(\.textSize, appearance.historyTextSize)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) {
            searchFocused = true
        }
    }

    /// 一覧とプレビューの下の余白（ウインドウの下端から）
    private static let contentBottomPadding: CGFloat = 12
    /// 帯と、その上に来る行やプレビューの文字との間
    private static let actionBarGap: CGFloat = 6

    /// 一覧とプレビューの下端のうち、帯が重なる高さに少し間を足したもの。
    /// スクロールする所は、いちばん下までスクロールすれば帯の上に出る。↓ で選んだ行も、帯に隠れない所まで送る
    private var actionBarClearance: CGFloat {
        guard actionBarHeight > 0 else { return 0 }
        return max(0, ActionBar.margin + actionBarHeight - Self.contentBottomPadding + Self.actionBarGap)
    }

    private var minSize: NSSize {
        HistoryPanelController.minSize(for: appearance.historyTextSize)
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

// MARK: - 操作ボタン（右下に浮く帯）

/// 選んだ項目への操作ボタン。上の段（探す）と場所を分け、絞り込みのボタンと取り違えにくくする。
/// ピン留めと削除の入口もここに置く（右クリックのメニューは作らない。2026-10-18 決定）
///
/// 6 つを 1 本の両端が丸い Liquid Glass の帯にまとめ、ウインドウの右下に浮かせる（requirements.md §3.3、2026-10-30 決定）。
/// ガラスの見え方は Mac のシステム設定（外観の Liquid Glass、透明度を下げる）に従い、Kasane の不透明度とぼかしは効かない。
/// ペーストだけはガラスにせず、アクセントの色で塗る（ガラスに色を付けると、透けて設定の色からずれるため）
private struct ActionBar: View {
    /// ウインドウの下と右からの間
    static let margin: CGFloat = 10

    @ObservedObject var model: HistoryModel
    @StateObject private var tooltips = TooltipState()

    var body: some View {
        let isPinned = model.selectedID.flatMap { model.summary(id: $0) }?.isPinned ?? false
        HStack(spacing: 4) {
            Button("ペースト ⏎") { model.activateSelection(.paste) }
                .buttonStyle(ActionStyle(isPrimary: true))
            Button("書式なし ⇧⏎") { model.activateSelection(.plainText) }
                .buttonStyle(ActionStyle())
            // FIFO / LIFO 中の ⌘⏎ は、選んだ項目をキューに追加する（⌘C でコピーしたときと同じ）
            Button(model.queueMode == nil ? "コピー ⌘⏎" : "キューに追加 ⌘⏎") { model.activateSelection(.copyOnly) }
                .buttonStyle(ActionStyle())
            Button {
                tooltips.dismiss()
                model.togglePinSelection()
            } label: {
                Label("⌘P", systemImage: isPinned ? "pin.fill" : "pin")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(ActionStyle(isOn: isPinned))
            .tooltip(isPinned ? "ピン留めを外す（⌘P）" : "ピン留め（⌘P）", id: "pin", state: tooltips)
            // ⌘⌫ でも消せるが、ボタンには ⌘D だけ書く（1 つの方がすぐ読める）
            Button {
                tooltips.dismiss()
                model.deleteSelection()
            } label: {
                Label("⌘D", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(ActionStyle())
            .tooltip("削除（⌘D・⌘⌫）", id: "delete", state: tooltips)
            Button {
                tooltips.dismiss()
                model.showsDetails.toggle()
            } label: {
                Label("⌘I", systemImage: "info.circle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(ActionStyle(isOn: model.showsDetails))
            .tooltip("詳細を表示（⌘I）", id: "info", state: tooltips)
        }
        .padding(4)
        .glassEffect(.regular, in: Capsule())
        // 閉じたときにマウスが載ったままだと、離れたことが伝わらない。開き直したときに消す
        .onChange(of: model.focusToken) { tooltips.dismiss() }
    }
}

// MARK: - ボタンの説明（ツールチップ）

/// ボタンの説明を出す時機を決める。
///
/// macOS 標準のツールチップ（`.help`）は、Kasane では出るまで 2〜3 秒かかり、文字も小さかった（2026-10-19、Kazuya さん）。
/// 標準のものは文字の大きさを変えられないので、自前で描く。決めたことは design/tooltip-unpin-2026-10-19.md
@MainActor
private final class TooltipState: ObservableObject {
    /// 止まって迷ったときにはすぐ出し、帯の上を動かしている途中では出さない長さ
    static let delay: Duration = .milliseconds(500)
    /// 説明が消えてからこの秒数のうちに別のボタンへ移ったら、待たずに出す（ボタンを順に見ていくとき）
    static let quickSwitchWindow: TimeInterval = 1

    @Published private(set) var shownID: String?
    private var pendingID: String?
    private var pending: Task<Void, Never>?
    private var lastHiddenAt = Date.distantPast

    func hover(_ id: String, inside: Bool) {
        if inside {
            cancelPending()
            if shownID != nil || Date().timeIntervalSince(lastHiddenAt) < Self.quickSwitchWindow {
                shownID = id
                return
            }
            pendingID = id
            pending = Task { [weak self] in
                try? await Task.sleep(for: Self.delay)
                guard !Task.isCancelled, let self, self.pendingID == id else { return }
                self.pendingID = nil
                self.shownID = id
            }
        } else {
            // 隣のボタンに入ったあとで、前のボタンから出た知らせが届くことがある。そのときは消さない
            if pendingID == id { cancelPending() }
            if shownID == id {
                shownID = nil
                lastHiddenAt = Date()
            }
        }
    }

    /// ボタンを押したときや、開き直したときに消す。続けて別のボタンに移っても、すぐには出さない
    func dismiss() {
        cancelPending()
        shownID = nil
        lastHiddenAt = .distantPast
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
        pendingID = nil
    }
}

private extension View {
    func tooltip(_ text: String, id: String, state: TooltipState) -> some View {
        modifier(Tooltip(text: text, id: id, state: state))
    }
}

/// ボタンのすぐ上に、右端をそろえて説明を出す（右端のボタンでもウインドウの外にはみ出さない）
private struct Tooltip: ViewModifier {
    let text: String
    let id: String
    @ObservedObject var state: TooltipState

    func body(content: Content) -> some View {
        content
            .onHover { state.hover(id, inside: $0) }
            // `.help` は VoiceOver が読む説明も兼ねていたので、その分をここで渡す
            .accessibilityHint(Text(text))
            .overlay(alignment: .topTrailing) {
                if state.shownID == id {
                    // 上端をボタンの上端にそろえてから、説明の高さ＋6pt だけ上にずらす。
                    // `alignmentGuide(.top)` で持ち上げる書き方は、Kazuya さんの Mac で効かず、ボタンに重なった（2026-10-21）
                    TooltipLabel(text: text)
                        .fixedSize()
                        .offset(y: -(TooltipLabel.height + 6))
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct TooltipLabel: View {
    /// 上にずらす量をこの値で決めるので、高さは固定にする（12pt の 1 行が収まる）
    static let height: CGFloat = 22

    let text: String

    var body: some View {
        // ボタンの文字（`ActionStyle`）と同じ 12pt
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
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
/// ペーストだけをアクセントで塗り、太字も残す。塗られたボタンが 1 つだけなら、Mac の「⏎ で押されるボタン」と同じに見える
/// （2026-10-22 決定。accent-usage-2026-10-22.md §4。色の見分けにくい人にも太字で主な操作と分かるように）。
/// ほかのボタンは帯のガラスの上に文字だけを置き、マウスを載せた間だけ薄く塗る。形は帯に合わせて両端を丸くする
private struct ActionStyle: ButtonStyle {
    var isPrimary = false
    /// ピン留め中や ⌘I の詳細がオンのとき、絞り込みの選択中と同じく白く浮かせる
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(configuration: configuration, isPrimary: isPrimary, isOn: isOn)
    }
}

private struct ActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isPrimary: Bool
    let isOn: Bool
    @State private var isHovered = false
    @Environment(\.kasaneAccent) private var accent

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isPrimary ? accent.foreground : (isOn ? Color.raisedText : .primary))
            .background {
                if isPrimary {
                    Capsule().fill(accent.color)
                } else if isOn {
                    RaisedFill(shape: Capsule())
                } else if isHovered {
                    Capsule().fill(Color.primary.opacity(0.08))
                }
            }
            .contentShape(Capsule())
            .onHover { isHovered = $0 }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - 履歴のリスト

private struct ItemListView: View {
    @ObservedObject var model: HistoryModel
    @Environment(\.textSize) private var size

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: size.scaled(4)) {
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
            .onChange(of: model.scrollToken) {
                guard let id = model.selectedID else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func row(_ item: ClipSummary) -> some View {
        ItemRow(
            item: item,
            // 行の入力として渡す（行は HistoryModel を見ていないので、クエリが変わったことを入力の違いで伝える）
            matches: model.matchRanges(for: item),
            isSelected: model.selectedID == item.id,
            shortcut: model.shortcutNumber(for: item.id)
        )
        .id(item.id)
        // URL の行は、見えている間だけタイトルと画像を取りに行く候補にする。LazyVStack の onAppear は
        // 画面の少し外の行にも呼ばれるので、半分以上見えているかで決める
        .onScrollVisibilityChange(threshold: 0.5) { visible in
            model.links.setVisible(item, visible)
        }
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
    @Environment(\.textSize) private var size

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.14))
            .frame(height: 1)
            .padding(.horizontal, size.scaled(8))
            .padding(.vertical, size.scaled(6))
    }
}

private struct EmptyState: View {
    let text: String
    @Environment(\.textSize) private var size

    var body: some View {
        Text(text)
            .font(.system(size: size.font(13)))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, size.scaled(60))
    }
}

private struct SelectionBackground: View {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.textSize) private var size

    var body: some View {
        RoundedRectangle(cornerRadius: size.scaled(12), style: .continuous)
            // ダークは不透明の #3D4047。半透明だと後ろの画面で地の明るさが変わり、一致した文字のコントラストが保てないため
            // （accent-usage-2026-10-22.md「実装で気をつけること」。今までの白 13% をふつうのダークのガラスに重ねた色とほぼ同じ）
            .fill(isSelected ? (colorScheme == .dark ? Color(nsColor: NSColor(ContrastFit.darkBackground)) : Color.white) : Color.clear)
            .shadow(color: isSelected && colorScheme == .light ? .black.opacity(0.10) : .clear, radius: 5, y: 2)
    }
}

private struct ItemRow: View {
    let item: ClipSummary
    /// 題名の中で、検索の語が当たった文字の位置（UTF-16）
    let matches: [Range<Int>]
    let isSelected: Bool
    let shortcut: Int?
    @Environment(\.textSize) private var size
    @Environment(\.kasaneAccent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: size.scaled(10)) {
            ItemIcon(item: item, isSelected: isSelected)
                .frame(width: size.scaled(44), height: size.scaled(44))
            VStack(alignment: .leading, spacing: size.scaled(3)) {
                Text(title)
                    .font(.system(size: size.font(13)))
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(item.kind.displayName)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.kindGray)
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
                .font(.system(size: size.font(11)))
            }
        }
        .padding(.horizontal, size.scaled(10))
        .padding(.vertical, size.scaled(9))
        .background(SelectionBackground(isSelected: isSelected))
    }

    /// 一致した文字の後ろをアクセントの色で塗り、文字を太字にした題名（design/match-highlight-2026-10-24.md）。
    /// 続けて当たった文字は 1 つの範囲なので、塗りも 1 つの面になる
    private var title: AttributedString {
        guard !item.title.isEmpty else { return AttributedString(" ") }
        var result = AttributedString(item.title)
        // AppKit と SwiftUI の両方に同じ名前の属性があるので、SwiftUI の属性を型で指定する
        typealias Attributes = AttributeScopes.SwiftUIAttributes
        for match in matches {
            guard let range = Range(NSRange(location: match.lowerBound, length: match.count), in: result) else { continue }
            result[range][Attributes.BackgroundColorAttribute.self] = accent.matchFill
            result[range][Attributes.ForegroundColorAttribute.self] = AccentColor.onMatchFill
            result[range][Attributes.FontAttribute.self] = .system(size: size.font(13), weight: .bold)
        }
        return result
    }

    private var subtitle: String {
        let date = Formatters.relative.localizedString(for: item.copiedAt, relativeTo: Date())
        if let app = item.sourceAppName {
            return "\(app) · \(date)"
        }
        return date
    }
}

/// 種類のアイコン（右下にコピー元のアプリ）。種類ごとの色はやめ、灰色の形だけにする。
/// 選んだ行は四角をアクセントで塗り、記号を上に載せる文字の色にする（2026-10-23 決定、accent-usage §3.1 の C）。
/// ダークでは、四角を一致した文字の塗りと同じ明るさにし、記号を #1D1D1F にする（2026-10-24、match-highlight §4）。
/// 画像の行も縮小表示は出さず、同じ灰色のアイコンにする（一覧の大きさでは見分けにくく、色のある縮小表示が一致した文字より先に目を引くため。
/// 縮小画像は作って保存し続けるが、一覧では読まない）
private struct ItemIcon: View {
    let item: ClipSummary
    let isSelected: Bool
    @Environment(\.textSize) private var size
    @Environment(\.kasaneAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size.scaled(9), style: .continuous)
                .fill(isSelected ? accent.color : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07)))
                .overlay {
                    Image(systemName: item.kind.symbolName)
                        .font(.system(size: size.scaled(18), weight: .medium))
                        .foregroundStyle(isSelected ? accent.foreground : Color.kindGray)
                }
            if let icon = AppIconCache.icon(bundleID: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size.scaled(18), height: size.scaled(18))
                    .offset(x: size.scaled(4), y: size.scaled(4))
            }
        }
    }
}

private struct TextSizeKey: EnvironmentKey {
    static let defaultValue = TextSizeLevel.default
}

extension EnvironmentValues {
    /// 履歴ウインドウの一覧とプレビューの文字の大きさ（2026-10-22 決定。上の帯・検索欄・絞り込み・下のボタンは変えない）
    var textSize: TextSizeLevel {
        get { self[TextSizeKey.self] }
        set { self[TextSizeKey.self] = newValue }
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

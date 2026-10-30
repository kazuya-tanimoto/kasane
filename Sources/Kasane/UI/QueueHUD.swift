import AppKit
import Combine
import KasaneCore
import KasaneStore
import SwiftUI

/// FIFO / LIFO 中に画面の端に出す帯（小さいウインドウ。2026-10-30 決定。requirements.md §3.6）。
///
/// - 設定の「左 / 右」の側の画面の端にくっつけ、メニューバーの下から画面の下まで出す。すき間なし、角丸なし。
///   Dock は避けずにかぶせる（帯の段 .statusBar は Dock の段より手前）
/// - 中は 1 件ずつのカード（`QueueCardContent`）。件数で大きさは変えず、入りきらない分は中をスクロールする
/// - 内側の端をドラッグして幅を変え、変えた幅を覚える（`QueueBandLayout`）
/// - 出すときと消すときだけ、画面の端から約 0.2 秒滑らせる。「視差効果を減らす」がオンならフェードだけ
/// - モード中は、履歴ウインドウを開いている間も出したままにする
/// - クリックは受け止めて下のアプリには通さないが、キーウインドウにはならない（作業中のアプリから入力先を移さない）
@MainActor
final class QueueHUDController {
    private var panel: QueueHUDPanel
    private let container: QueueBandContainer
    private let state = QueueBandState()
    private let links: LinkPrefetcher
    private var blurObserver: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var blurState = WindowBlurState()
    /// 消している途中に出し直したとき、前の「消し終わったら隠す」を取り消すため
    private var hideToken = UUID()
    /// ドラッグを始めたときの幅
    private var dragStartWidth: CGFloat = 0

    /// 出し入れの時間（§3.6。履歴の行の動きと同じ約 0.2 秒）
    private static let slideDuration: TimeInterval = 0.2
    /// 「視差効果を減らす」がオンのときのフェードの時間（§3.5 の行の動きと同じ）
    private static let fadeDuration: TimeInterval = 0.15

    init(links: LinkPrefetcher) {
        self.links = links
        panel = QueueHUDPanel(contentRect: NSRect(x: 0, y: 0, width: QueueBandLayout.baseWidth, height: 400))
        let hosting = NSHostingView(rootView: QueueHUDView(state: state, appearance: .shared, links: links))
        // 大きさはこちらで決める。SwiftUI 側からウインドウの大きさを変えさせない
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        container = QueueBandContainer(hosting: hosting)
        panel.contentView = container
        container.onDragBegan = { [weak self] in self?.dragBegan() }
        container.onDragged = { [weak self] deltaX in self?.dragged(deltaX) }
        container.onDragEnded = { [weak self] in self?.dragEnded() }
        blurObserver = AppearanceSettings.shared.$blurRadius.sink { [weak self] radius in
            self?.applyBlur(radius)
        }
        // 画面の構成（メニューバー、解像度、画面の抜き差し）が変わったら置き直す
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
    }

    /// ぼかしの半径を付ける。なしから半径を付けるときは、ウインドウを作り直す（`WindowBlurState`）
    private func applyBlur(_ radius: Int) {
        guard blurState.needsNewWindow(for: radius) else {
            blurState.apply(radius, to: panel)
            return
        }
        let old = panel
        let wasVisible = old.isVisible
        old.orderOut(nil)
        old.contentView = nil
        panel = QueueHUDPanel(contentRect: old.frame)
        panel.setFrame(old.frame, display: false)
        panel.contentView = container
        blurState = WindowBlurState()
        // 起動したときと同じく、出す前に半径を付ける
        blurState.apply(radius, to: panel)
        if wasVisible {
            panel.orderFrontRegardless()
        }
    }

    /// - Parameters:
    ///   - mode: nil ならモード外なので消す
    ///   - clips: 貼り付ける順のキューの中身
    func update(mode: QueueMode?, clips: [QueuedClip]) {
        guard let mode else {
            hide()
            return
        }
        state.mode = mode
        state.clips = clips
        state.fontSize = AppSettings.hudFontSize
        for clip in clips where clip.kind == .url {
            Task { await links.loadSaved(itemID: clip.itemID) }
        }
        if panel.isVisible && state.isShown {
            relayout()
        } else {
            show()
        }
    }

    // MARK: 置き場所

    private var screenFrame: CGRect? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return QueueBandLayout.bandArea(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    private var currentWidth: CGFloat {
        guard let screen = screenFrame else { return QueueBandLayout.baseWidth }
        return QueueBandLayout.width(
            savedBaseWidth: AppSettings.hudBandWidth,
            fontSize: CGFloat(state.fontSize),
            screen: screen
        )
    }

    private func shownFrame(width: CGFloat) -> NSRect? {
        guard let screen = screenFrame else { return nil }
        return QueueBandLayout.frame(side: AppSettings.hudSide, width: width, screen: screen)
    }

    /// 帯の幅を 0 にした、画面の端の枠。ここから広げると、中身が端から滑り出して見える
    private func collapsedFrame(from frame: NSRect) -> NSRect {
        var collapsed = frame
        collapsed.size.width = 1
        if AppSettings.hudSide == .right {
            collapsed.origin.x = frame.maxX - 1
        }
        return collapsed
    }

    private func relayout() {
        guard state.isShown, let frame = shownFrame(width: currentWidth) else { return }
        container.side = AppSettings.hudSide
        container.contentWidth = frame.width
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: 出し入れ

    private func show() {
        guard let frame = shownFrame(width: currentWidth) else { return }
        hideToken = UUID()
        state.isShown = true
        container.side = AppSettings.hudSide
        // 滑っている間も中身は出し終えた幅のまま描き、帯の幅だけを広げる
        container.contentWidth = frame.width
        let wasVisible = panel.isVisible
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: true)
            if !wasVisible { panel.alphaValue = 0 }
            orderFront()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 1
            }
            return
        }
        panel.alphaValue = 1
        if !wasVisible {
            panel.setFrame(collapsedFrame(from: frame), display: false)
            orderFront()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        }
    }

    private func hide() {
        guard state.isShown || panel.isVisible else { return }
        state.isShown = false
        guard panel.isVisible else { return }
        let token = UUID()
        hideToken = token
        let finish = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideToken == token else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 0
            }, completionHandler: finish)
            return
        }
        let target = collapsedFrame(from: panel.frame)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: finish)
    }

    private func orderFront() {
        panel.orderFrontRegardless()
        applyBlur(AppearanceSettings.shared.blurRadius)
    }

    // MARK: 幅のドラッグ

    private func dragBegan() {
        dragStartWidth = panel.frame.width
    }

    private func dragged(_ deltaX: CGFloat) {
        guard state.isShown, let screen = screenFrame else { return }
        let width = QueueBandLayout.draggedWidth(
            from: dragStartWidth,
            deltaX: deltaX,
            side: AppSettings.hudSide,
            fontSize: CGFloat(state.fontSize),
            screen: screen
        )
        guard let frame = shownFrame(width: width) else { return }
        container.contentWidth = width
        panel.setFrame(frame, display: true)
    }

    private func dragEnded() {
        AppSettings.hudBandWidth = QueueBandLayout.baseWidth(for: panel.frame.width, fontSize: CGFloat(state.fontSize))
        panel.invalidateShadow()
    }
}

/// 帯に出すもの。SwiftUI の帯はこれを見て描き直す
@MainActor
final class QueueBandState: ObservableObject {
    @Published var mode: QueueMode = .fifo
    @Published var clips: [QueuedClip] = []
    @Published var fontSize: Double = AppSettings.hudFontSize
    /// 出している（出している途中を含む）か。消している途中は false
    var isShown = false
}

/// クリックは受け止めるが、キーウインドウにはならないパネル。
/// キーウインドウになると、作業中のアプリ（や履歴ウインドウ）からキー入力を奪ってしまう。
/// 帯は角丸にしないので、タイトルなしのウインドウにする（ぼかしも四角いまま）
final class QueueHUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 帯の中身と、内側の端のつかむ所を並べる。
/// 中身は `contentWidth` の幅で内側の端に寄せる。出し入れで帯の幅が狭いときは、中身の内側の部分だけが見え、
/// 端から滑り出して見える
final class QueueBandContainer: NSView {
    private let hosting: NSView
    private let handle = QueueBandResizeHandle()

    var onDragBegan: (() -> Void)? {
        get { handle.onBegan }
        set { handle.onBegan = newValue }
    }
    var onDragged: ((CGFloat) -> Void)? {
        get { handle.onDragged }
        set { handle.onDragged = newValue }
    }
    var onDragEnded: (() -> Void)? {
        get { handle.onEnded }
        set { handle.onEnded = newValue }
    }

    var side: HUDSide = .right {
        didSet { if side != oldValue { needsLayout = true } }
    }
    var contentWidth: CGFloat = QueueBandLayout.baseWidth {
        didSet { if contentWidth != oldValue { needsLayout = true } }
    }

    init(hosting: NSView) {
        self.hosting = hosting
        super.init(frame: .zero)
        addSubview(hosting)
        addSubview(handle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let height = bounds.height
        let handleWidth = QueueBandLayout.Metrics.handleWidth
        switch side {
        case .right:
            // 右の帯は左端が内側
            hosting.frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
            handle.frame = NSRect(x: 0, y: 0, width: handleWidth, height: height)
        case .left:
            hosting.frame = NSRect(x: bounds.width - contentWidth, y: 0, width: contentWidth, height: height)
            handle.frame = NSRect(x: bounds.width - handleWidth, y: 0, width: handleWidth, height: height)
        }
    }
}

/// 帯の内側の端の、ドラッグで幅を変える所。
/// キーウインドウにならない帯でも 1 回目のクリックからつかめ、カーソルが左右の矢印になる
final class QueueBandResizeHandle: NSView {
    var onBegan: (() -> Void)?
    var onDragged: ((CGFloat) -> Void)?
    var onEnded: (() -> Void)?
    /// つかんだときのマウスの位置（画面の座標）。ドラッグ中は帯が動くので、帯の中の座標では測らない
    private var startX: CGFloat = 0

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // キーウインドウでなくてもカーソルを変える
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.columnResize.set()
    }

    override func mouseDown(with event: NSEvent) {
        startX = NSEvent.mouseLocation.x
        onBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.columnResize.set()
        onDragged?(NSEvent.mouseLocation.x - startX)
    }

    override func mouseUp(with event: NSEvent) {
        onEnded?()
    }
}

/// 帯の中身。上に FIFO / LIFO の印と残りの件数、その下に 1 件ずつのカード
struct QueueHUDView: View {
    @ObservedObject var state: QueueBandState
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var links: LinkPrefetcher

    private var scale: CGFloat { QueueBandLayout.scale(fontSize: state.fontSize) }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6 * scale) {
                header
                if state.clips.isEmpty {
                    Text("コピーするとここに追加されます")
                        .font(.system(size: state.fontSize))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(state.clips.enumerated()), id: \.element.id) { index, clip in
                    QueueCardView(
                        number: index + 1,
                        isNext: index == 0,
                        content: content(for: clip),
                        thumbnail: thumbnail(for: clip),
                        linkImage: linkImage(for: clip),
                        fontSize: state.fontSize
                    )
                }
            }
            .padding(.horizontal, QueueBandLayout.Metrics.bandPadding * scale)
            .padding(.vertical, 12 * scale)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelBackground(appearance: appearance))
        .environment(\.kasaneAccent, appearance.accent)
    }

    private var header: some View {
        HStack(spacing: 8 * scale) {
            Text(state.mode == .lifo ? "LIFO" : "FIFO")
                .font(.system(size: state.fontSize - 1, weight: .bold))
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 2 * scale)
                .foregroundStyle(appearance.accent.foreground)
                .background(Capsule().fill(appearance.accent.color))
            Text("残り \(state.clips.count) 件")
                .font(.system(size: state.fontSize))
                .foregroundStyle(.secondary)
        }
    }

    /// スイッチがオフなら、保存したページ情報も出さない（§3.3）
    private func loaded(for clip: QueuedClip) -> LinkPrefetcher.Loaded? {
        guard clip.kind == .url, links.isEnabled else { return nil }
        return links.loaded[clip.itemID]
    }

    private func content(for clip: QueuedClip) -> QueueCardContent {
        let page = loaded(for: clip)
        return QueueCardContent.make(
            kind: QueueCardContent.Kind(clip.kind),
            title: clip.title,
            text: clip.text,
            hasThumbnail: clip.thumbnail != nil,
            linkTitle: page?.title,
            hasLinkImage: page?.image != nil
        )
    }

    private func thumbnail(for clip: QueuedClip) -> NSImage? {
        guard clip.kind == .image else { return nil }
        return clip.thumbnail.flatMap(NSImage.init(data:))
    }

    private func linkImage(for clip: QueuedClip) -> NSImage? {
        loaded(for: clip)?.image
    }
}

/// 1 件のカード。番号は中身の左。次に貼る 1 件は番号の丸をアクセントの色そのもので塗り、地を明るくする
struct QueueCardView: View {
    let number: Int
    let isNext: Bool
    let content: QueueCardContent
    let thumbnail: NSImage?
    let linkImage: NSImage?
    let fontSize: Double
    @Environment(\.kasaneAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    private var scale: CGFloat { QueueBandLayout.scale(fontSize: fontSize) }

    var body: some View {
        let m = QueueBandLayout.Metrics.self
        HStack(alignment: .top, spacing: m.numberGap * scale) {
            Text("\(number)")
                .font(.system(size: fontSize * 0.75, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, number >= 10 ? 4 * scale : 0)
                .frame(minWidth: m.numberDiameter * scale, minHeight: m.numberDiameter * scale)
                .foregroundStyle(isNext ? accent.foreground : Color.primary)
                .background(Capsule().fill(isNext ? accent.color : numberFill))
            VStack(alignment: .leading, spacing: 4 * scale) {
                picture
                if let heading = content.heading {
                    Text(heading)
                        .font(.system(size: fontSize, weight: .semibold))
                        .lineLimit(1)
                }
                Text(content.body)
                    .font(.system(size: fontSize))
                    .foregroundStyle(content.bodyIsSecondary ? Color.secondary : Color.primary)
                    .lineLimit(content.bodyLines)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(m.cardPadding * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous).fill(cardFill))
    }

    @ViewBuilder
    private var picture: some View {
        if let image = content.picture == .thumbnail ? thumbnail : (content.picture == .linkImage ? linkImage : nil) {
            // 横はカードの幅いっぱい、縦は横の 9/16 まで（はみ出す分は切る）
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(Image(nsImage: image).resizable().scaledToFill())
                .clipShape(RoundedRectangle(cornerRadius: 4 * scale, style: .continuous))
        }
    }

    // 色はモック（QueueEdge の 3 つ目）の値
    private var cardFill: Color {
        switch (colorScheme, isNext) {
        case (.dark, true): return Color.white.opacity(0.14)
        case (.dark, false): return Color.white.opacity(0.08)
        case (_, true): return Color.white
        default: return Color.white.opacity(0.72)
        }
    }

    private var numberFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }
}

extension QueueCardContent.Kind {
    init(_ kind: ClipKind) {
        switch kind {
        case .text: self = .text
        case .richText: self = .richText
        case .url: self = .url
        case .image: self = .image
        case .file: self = .file
        }
    }
}

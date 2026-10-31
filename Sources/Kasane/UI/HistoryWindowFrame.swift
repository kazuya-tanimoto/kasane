import AppKit
import KasaneCore
import QuartzCore
import SwiftUI

/// 履歴ウインドウの角・縁を、デザインモックの値（`HistoryFrameLayout`）で描く。
///
/// ウインドウは縁なしにして、角丸に切り抜き、1pt の縁を重ねる。ぼかし（`WindowBlur`）は、
/// 縁なしのウインドウでは描いた所の形で切り抜かれるので、角の外はぼけない（2026-10-31、CI の Mac で確かめた）。
/// 周りに、ほとんど透明な余白（`HistoryFrameLayout.resizeMargin`）を付け、端と角で大きさを変えられるようにする
struct HistoryWindowFrame: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: HistoryFrameLayout.cornerRadius, style: .circular)
        content
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    Color.white.opacity(HistoryFrameLayout.borderWhiteOpacity(dark: colorScheme == .dark)),
                    lineWidth: HistoryFrameLayout.borderWidth
                )
            )
            .padding(HistoryFrameLayout.resizeMargin)
            .background(ResizeMargin())
    }
}

/// 角丸の外の余白。透明だとクリックが後ろのアプリに抜けて角で大きさを変えられないので、
/// 目に見えないほど薄く塗る（不透明度 1/255。CI の Mac で、ぼかしもかからないことを確かめた）
private struct ResizeMargin: View {
    var body: some View {
        MarginShape()
            .fill(Color.black.opacity(1.0 / 255), style: FillStyle(eoFill: true))
    }

    private struct MarginShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path(rect)
            let inset = HistoryFrameLayout.resizeMargin
            path.addRoundedRect(
                in: rect.insetBy(dx: inset, dy: inset),
                cornerSize: CGSize(width: HistoryFrameLayout.cornerRadius, height: HistoryFrameLayout.cornerRadius),
                style: .circular
            )
            return path
        }
    }
}

/// 履歴ウインドウの影だけのウインドウ（モック: box-shadow 0 30px 80px 黒 35%）。
/// 角丸の外にだけ影を描き、クリックは受けずに後ろのアプリに届ける。履歴ウインドウの子ウインドウにして一緒に動かす
final class HistoryShadowPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = HistoryShadowView()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // 影のウインドウは画面の上の端からはみ出す。Mac が画面の中へずらすと、切り抜いた所が本体とずれ、
    // 本体の上の端に影が透け、下の端の外に影のない隙間ができた（2026-10-31、CI の Mac で 10pt ずれた）ので、ずらさせない
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// 履歴ウインドウの位置と大きさに合わせる
    func follow(_ window: NSWindow) {
        setFrame(HistoryFrameLayout.shadowFrame(window: window.frame), display: true)
    }
}

/// 角丸の本体の形をした、絵のない層に影だけを描かせ、本体の所は切り抜く（履歴ウインドウは半透明なので、下に影が透けないように）
private final class HistoryShadowView: NSView {
    private let holder = CALayer()
    private let caster = CALayer()
    private let cutout = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        caster.shadowColor = NSColor.black.cgColor
        caster.shadowOpacity = Float(HistoryFrameLayout.shadowOpacity)
        // CSS の y は下向き。Mac の層は上向きなので負にする
        caster.shadowOffset = CGSize(width: 0, height: -HistoryFrameLayout.shadowOffsetY)
        // CSS のぼかしは標準偏差がぼかしの半分のガウス。shadowRadius は半分の値にする（小さいウインドウの帯の影と同じ換算）
        caster.shadowRadius = HistoryFrameLayout.shadowBlur / 2
        cutout.fillRule = .evenOdd
        holder.addSublayer(caster)
        holder.mask = cutout
        layer?.addSublayer(holder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 層の位置は、ビューの大きさが決まった後で合わせる（ウインドウの大きさを変えた直後に合わせると、前の大きさのままずれた。2026-10-31、CI の Mac）
    override func layout() {
        super.layout()
        let body = HistoryFrameLayout.shadowCaster(inShadowOfSize: bounds.size)
        let radius = HistoryFrameLayout.cornerRadius
        let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let outside = CGMutablePath()
        outside.addRect(bounds)
        outside.addPath(bodyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.frame = bounds
        caster.frame = bounds
        caster.shadowPath = bodyPath
        cutout.frame = bounds
        cutout.path = outside
        CATransaction.commit()
    }
}

/// 履歴ウインドウの中身。SwiftUI の画面の上に、端をつかんで大きさを変える所（`ResizeGrips`）を重ねる
final class HistoryContentView: NSView {
    private let grips = ResizeGrips()

    /// 端をつかんで大きさを変え終えたとき
    var onResizeEnd: (() -> Void)? {
        get { grips.onResizeEnd }
        set { grips.onResizeEnd = newValue }
    }

    init(content: NSView) {
        super.init(frame: content.frame)
        // SwiftUI の画面の最小の大きさ（NSHostingView の sizingOptions）がウインドウに伝わるよう、制約で四辺に付ける
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        grips.autoresizingMask = [.width, .height]
        grips.frame = bounds
        addSubview(grips)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 端と角をつかんで大きさを変える所。つかむ所の外のクリックは、下の SwiftUI の画面に渡す。
/// 縁なしのウインドウを Mac に任せると、つかめる所が前のシステムのウインドウより狭いので、自分で作る（`HistoryFrameLayout.resizeEdge`）
private final class ResizeGrips: NSView {
    var onResizeEnd: (() -> Void)?
    /// いま、つかむ所の矢印のカーソルを出しているか
    private var showsResizeCursor = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return HistoryFrameLayout.edges(at: local, in: bounds.size).isEmpty ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        updateCursor(at: NSPoint(x: -1, y: -1))
    }

    private func updateCursor(at point: NSPoint) {
        let edges = HistoryFrameLayout.edges(at: point, in: bounds.size)
        if let cursor = Self.cursor(for: edges) {
            cursor.set()
            showsResizeCursor = true
        } else if showsResizeCursor {
            // 端から離れたら矢印に戻す。中身の上のカーソル（検索欄の I など）は、中身が出し直す
            NSCursor.arrow.set()
            showsResizeCursor = false
        }
    }

    private static func cursor(for edges: HistoryFrameLayout.Edges) -> NSCursor? {
        let position: NSCursor.FrameResizePosition
        switch edges {
        case [.left, .top]: position = .topLeft
        case [.right, .top]: position = .topRight
        case [.left, .bottom]: position = .bottomLeft
        case [.right, .bottom]: position = .bottomRight
        case .left: position = .left
        case .right: position = .right
        case .top: position = .top
        case .bottom: position = .bottom
        default: return nil
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let edges = HistoryFrameLayout.edges(at: convert(event.locationInWindow, from: nil), in: bounds.size)
        guard !edges.isEmpty else { return }
        let start = NSEvent.mouseLocation
        let startFrame = window.frame
        let minSize = NSSize(
            width: max(window.minSize.width, window.contentMinSize.width),
            height: max(window.minSize.height, window.contentMinSize.height)
        )
        // ボタンを離すまで、ドラッグに合わせて大きさを変える
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let location = NSEvent.mouseLocation
            let frame = HistoryFrameLayout.resized(
                startFrame, edges: edges, dx: location.x - start.x, dy: location.y - start.y, minSize: minSize
            )
            if frame != window.frame {
                window.setFrame(frame, display: true)
            }
            if next.type == .leftMouseUp { break }
        }
        onResizeEnd?()
    }
}

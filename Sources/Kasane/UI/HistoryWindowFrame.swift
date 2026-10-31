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

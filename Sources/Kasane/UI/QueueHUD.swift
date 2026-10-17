import AppKit
import Combine
import KasaneCore
import SwiftUI

/// FIFO / LIFO 中に画面の隅に出す小さいウインドウ。
///
/// - モード中は、履歴ウインドウを開いている間も出したままにする
/// - キューの全件を貼り付ける順に出し、件数に合わせて縦に伸びる。画面の高さに収まらないときだけ、
///   画面の高さで止めて中をスクロールできるようにする
/// - クリックは受け止めて下のアプリには通さないが、キーウインドウにはならない（作業中のアプリから入力先を移さない）
/// - 文字の大きさは設定で変えられ、表示の大きさもそれに合わせる
@MainActor
final class QueueHUDController {
    private let panel: QueueHUDPanel
    private let hosting: NSHostingView<QueueHUDView>
    /// 高さを測るためだけのもの。スクロールのない中身を、画面に出さずに測る
    private let measuring: NSHostingController<QueueHUDContent>
    private var blurObserver: AnyCancellable?
    private let margin: CGFloat = 16

    init() {
        panel = QueueHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 80),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.hideTitlebar()
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        let empty = QueueHUDContent(mode: .fifo, titles: [], fontSize: AppSettings.hudFontSize)
        hosting = NSHostingView(rootView: QueueHUDView(content: empty, appearance: .shared))
        // 大きさはこちらで決める（`position()`）。SwiftUI 側からウインドウの大きさを変えさせない
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        panel.contentView = hosting
        measuring = NSHostingController(rootView: empty)
        measuring.sizingOptions = []
        blurObserver = AppearanceSettings.shared.$blurRadius.sink { [weak self] radius in
            guard let self else { return }
            WindowBlur.apply(radius: radius, to: self.panel)
        }
    }

    /// - Parameters:
    ///   - mode: nil ならモード外なので隠す
    ///   - titles: 貼り付ける順のタイトル
    func update(mode: QueueMode?, titles: [String]) {
        guard let mode else {
            panel.orderOut(nil)
            return
        }
        let content = QueueHUDContent(
            mode: mode,
            titles: titles,
            fontSize: AppSettings.hudFontSize
        )
        hosting.rootView = QueueHUDView(content: content, appearance: .shared)
        measuring.rootView = content
        position(content: content)
        if !panel.isVisible {
            panel.orderFrontRegardless()
            WindowBlur.apply(radius: AppearanceSettings.shared.blurRadius, to: panel)
        }
    }

    /// 中身の高さに合わせて、設定の隅に置く。画面の高さを超えるときは画面の高さで止める
    private func position(content: QueueHUDContent) {
        guard let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let width = content.width
        let fitting = measuring.sizeThatFits(in: NSSize(width: width, height: 100_000))
        let maxHeight = screen.height - margin * 2
        let height = min(max(ceil(fitting.height), 1), maxHeight)
        let size = NSSize(width: width, height: height)
        let origin: NSPoint
        switch AppSettings.hudPosition {
        case .topRight: origin = NSPoint(x: screen.maxX - size.width - margin, y: screen.maxY - size.height - margin)
        case .topLeft: origin = NSPoint(x: screen.minX + margin, y: screen.maxY - size.height - margin)
        case .bottomRight: origin = NSPoint(x: screen.maxX - size.width - margin, y: screen.minY + margin)
        case .bottomLeft: origin = NSPoint(x: screen.minX + margin, y: screen.minY + margin)
        }
        let frame = NSRect(origin: origin, size: size)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }
}

/// クリックは受け止めるが、キーウインドウにはならないパネル。
/// キーウインドウになると、作業中のアプリ（や履歴ウインドウ）からキー入力を奪ってしまう
final class QueueHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 小さいウインドウに出す中身（値だけを持つので、測るときも同じものを使える）
struct QueueHUDContent: View {
    let mode: QueueMode
    let titles: [String]
    let fontSize: Double
    /// アクセントカラーはメニューで変えるとすぐ反映されるよう、`QueueHUDView` から受け取る
    @Environment(\.kasaneAccent) private var accent

    /// 12pt のときを 1 とした倍率。余白や幅もこれに合わせて大きくする
    private var scale: CGFloat { fontSize / 12 }

    var width: CGFloat { 260 * scale }

    var body: some View {
        let size = fontSize
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 8 * scale) {
                Text(mode == .lifo ? "LIFO" : "FIFO")
                    .font(.system(size: size - 1, weight: .bold))
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 2 * scale)
                    .foregroundStyle(accent.foreground)
                    .background(Capsule().fill(accent.color))
                Text("残り \(titles.count) 件")
                    .font(.system(size: size))
                    .foregroundStyle(.secondary)
            }
            if titles.isEmpty {
                Text("コピーするとここに追加されます")
                    .font(.system(size: size))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                    // 2 桁以上になっても崩れないよう、番号の幅は件数の桁数に合わせる
                    Text("\(index + 1)")
                        .font(.system(size: size, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(index == 0 ? accent.text : Color.secondary)
                        .frame(width: numberWidth, alignment: .trailing)
                    Text(title.isEmpty ? " " : title)
                        .font(.system(size: size, weight: index == 0 ? .semibold : .regular))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 12 * scale)
        .frame(width: width, alignment: .topLeading)
    }

    private var numberWidth: CGFloat {
        let digits = max(String(titles.count).count, 1)
        return CGFloat(digits) * 8 * scale + 4 * scale
    }
}

/// 画面に出す小さいウインドウ。画面の高さを超えたときだけ中がスクロールする
struct QueueHUDView: View {
    let content: QueueHUDContent
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        ScrollView(.vertical) {
            content
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelBackground(appearance: appearance))
        .environment(\.kasaneAccent, appearance.accent)
    }
}

import AppKit
import Combine
import KasaneCore
import SwiftUI

/// FIFO / LIFO 中、履歴ウインドウを閉じているときに画面の隅に出す小さな表示。
///
/// クリックを受け付けず、フォーカスも奪わない（作業の邪魔にならないようにする）。
/// 文字の大きさは設定で変えられ、表示の大きさもそれに合わせる
@MainActor
final class QueueHUDController {
    private let panel: NSPanel
    private let hosting: NSHostingView<QueueHUDView>
    private let state = QueueHUDState()
    private var blurObserver: AnyCancellable?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 132),
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
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        hosting = NSHostingView(rootView: QueueHUDView(state: state, appearance: .shared))
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        panel.contentView = hosting
        blurObserver = AppearanceSettings.shared.$blurRadius.sink { [weak self] radius in
            guard let self else { return }
            WindowBlur.apply(radius: radius, to: self.panel)
        }
    }

    /// - Parameters:
    ///   - mode: nil ならモード外なので隠す
    ///   - titles: 貼り付ける順のタイトル
    ///   - visible: 履歴ウインドウを閉じているなど、表示してよい状況か
    func update(mode: QueueMode?, titles: [String], visible: Bool) {
        state.mode = mode
        state.titles = titles
        state.fontSize = AppSettings.hudFontSize
        guard mode != nil, visible else {
            panel.orderOut(nil)
            return
        }
        position()
        panel.orderFrontRegardless()
        WindowBlur.apply(radius: AppearanceSettings.shared.blurRadius, to: panel)
    }

    private func position() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let margin: CGFloat = 16
        let origin: NSPoint
        switch AppSettings.hudPosition {
        case .topRight: origin = NSPoint(x: screen.maxX - size.width - margin, y: screen.maxY - size.height - margin)
        case .topLeft: origin = NSPoint(x: screen.minX + margin, y: screen.maxY - size.height - margin)
        case .bottomRight: origin = NSPoint(x: screen.maxX - size.width - margin, y: screen.minY + margin)
        case .bottomLeft: origin = NSPoint(x: screen.minX + margin, y: screen.minY + margin)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

@MainActor
final class QueueHUDState: ObservableObject {
    @Published var mode: QueueMode?
    @Published var titles: [String] = []
    @Published var fontSize: Double = AppSettings.hudFontSize
}

struct QueueHUDView: View {
    @ObservedObject var state: QueueHUDState
    @ObservedObject var appearance: AppearanceSettings

    /// 12pt のときを 1 とした倍率。余白や幅もこれに合わせて大きくする
    private var scale: CGFloat { state.fontSize / 12 }

    var body: some View {
        let size = state.fontSize
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 8 * scale) {
                Text(state.mode == .lifo ? "LIFO" : "FIFO")
                    .font(.system(size: size - 1, weight: .bold))
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 2 * scale)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.orange))
                Text("残り \(state.titles.count) 件")
                    .font(.system(size: size))
                    .foregroundStyle(.secondary)
            }
            if state.titles.isEmpty {
                Text("コピーするとここに積まれます")
                    .font(.system(size: size))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(state.titles.prefix(3).enumerated()), id: \.offset) { index, title in
                HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                    Text("\(index + 1)")
                        .font(.system(size: size, weight: .bold, design: .rounded))
                        .foregroundStyle(index == 0 ? Color.orange : Color.secondary)
                        .frame(width: 14 * scale, alignment: .leading)
                    Text(title)
                        .font(.system(size: size, weight: index == 0 ? .semibold : .regular))
                        .lineLimit(1)
                }
            }
            if state.titles.count > 3 {
                Text("ほか \(state.titles.count - 3) 件")
                    .font(.system(size: size - 1))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 12 * scale)
        .frame(width: 260 * scale, alignment: .topLeading)
        .background(PanelBackground(appearance: appearance))
    }
}

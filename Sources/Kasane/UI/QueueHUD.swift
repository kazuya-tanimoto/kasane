import AppKit
import KasaneCore
import SwiftUI

/// FIFO / LIFO 中、履歴ウインドウを閉じているときに画面の隅に出す小さな表示。
///
/// クリックを受け付けず、フォーカスも奪わない（作業の邪魔にならないようにする）。
@MainActor
final class QueueHUDController {
    static let size = NSSize(width: 260, height: 132)

    private let panel: NSPanel
    private let state = QueueHUDState()

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: QueueHUDController.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: QueueHUDView(state: state, appearance: .shared))
    }

    /// - Parameters:
    ///   - mode: nil ならモード外なので隠す
    ///   - titles: 貼り付ける順のタイトル
    ///   - visible: 履歴ウインドウを閉じているなど、表示してよい状況か
    func update(mode: QueueMode?, titles: [String], visible: Bool) {
        state.mode = mode
        state.titles = titles
        guard let mode = mode, visible else {
            panel.orderOut(nil)
            return
        }
        _ = mode
        position()
        panel.orderFrontRegardless()
    }

    private func position() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let margin: CGFloat = 16
        let size = Self.size
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
}

private struct QueueHUDView: View {
    @ObservedObject var state: QueueHUDState
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(state.mode == .lifo ? "LIFO" : "FIFO")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.orange))
                Text("残り \(state.titles.count) 件")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if state.titles.isEmpty {
                Text("コピーするとここに積まれます")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(state.titles.prefix(3).enumerated()), id: \.offset) { index, title in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(index == 0 ? Color.orange : Color.secondary)
                        .frame(width: 14, alignment: .leading)
                    Text(title)
                        .font(.system(size: 12, weight: index == 0 ? .semibold : .regular))
                        .lineLimit(1)
                }
            }
            if state.titles.count > 3 {
                Text("ほか \(state.titles.count - 3) 件")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: QueueHUDController.size.width, height: QueueHUDController.size.height, alignment: .topLeading)
        .background(PanelBackground(appearance: appearance, cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

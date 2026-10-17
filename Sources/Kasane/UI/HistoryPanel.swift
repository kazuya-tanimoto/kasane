import AppKit
import Combine
import KasaneCore
import SwiftUI

/// 履歴ウインドウ。Spotlight や Raycast と同じく、Kasane 自身はアクティブにならないパネルにする。
/// 元のアプリが前面のままなので、閉じた直後に ⌘V を送れば元のアプリに貼り付けられる。
/// ドラッグで動かせて、端で大きさを変えられる。位置と大きさは次に開いたときも使う
final class HistoryPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        hideTitlebar()
        // 動かせるのは一番上の「Kasane」の帯、検索欄の周り、操作ボタンの横（`WindowDragArea`）だけ。
        // 背景全体をつかめるようにすると、プレビューの文字の選択とぶつかる
        isMovable = true
        minSize = HistoryPanelController.minSize
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    // 検索欄に入力できるよう、キーウインドウにはなれるようにする
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 880, height: 560)
    static let minSize = NSSize(width: 720, height: 420)

    private let panel: HistoryPanel
    private let model: HistoryModel
    private var keyMonitor: Any?
    private var isHiding = false
    /// 自分で位置を決めている間は、動かした・大きさを変えたとみなして保存しない
    private var isPositioning = false
    private var blurObserver: AnyCancellable?
    private let inputSource = InputSourceSwitcher()

    init(model: HistoryModel) {
        self.model = model
        panel = HistoryPanel(contentRect: NSRect(origin: .zero, size: HistoryPanelController.defaultSize))
        super.init()
        let hosting = NSHostingView(rootView: HistoryView(model: model, appearance: .shared))
        hosting.sizingOptions = [.minSize]
        // タイトルバーは隠しているので、その分の余白を空けない
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(origin: .zero, size: HistoryPanelController.defaultSize)
        panel.contentView = hosting
        panel.delegate = self
        blurObserver = AppearanceSettings.shared.$blurRadius.sink { [weak self] radius in
            guard let self else { return }
            WindowBlur.apply(radius: radius, to: self.panel)
        }
    }

    var isVisible: Bool { panel.isVisible && !isHiding }
    var isKey: Bool { panel.isKeyWindow }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.prepareForShow()
        position()
        isHiding = false
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        WindowBlur.apply(radius: AppearanceSettings.shared.blurRadius, to: panel)
        installKeyMonitor()
        // 検索欄にフォーカスが移ってから（SwiftUI の反映は次の描画）、英数に切り替える
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.inputSource.switchToASCII()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// フェードアウトして閉じる。閉じ終わってから `completion` を呼ぶ
    func hide(completion: (() -> Void)? = nil) {
        guard panel.isVisible, !isHiding else {
            completion?()
            return
        }
        isHiding = true
        removeKeyMonitor()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.orderOut(nil)
                self.isHiding = false
                // 前のアプリが前面に戻ってから、開く前の入力方法に戻す
                self.inputSource.restore()
                completion?()
            }
        })
    }

    /// マウスカーソルのある画面に置く。前に動かした・大きさを変えたときは、その位置と大きさを使う
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = WindowPlacement.frame(
            in: visible,
            savedSize: AppSettings.historyWindowSize,
            savedOffset: AppSettings.historyWindowOffset,
            defaultSize: Self.defaultSize,
            minSize: Self.minSize
        )
        isPositioning = true
        panel.setFrame(frame, display: false)
        isPositioning = false
    }

    /// 位置と大きさを既定に戻す（次に開いたときから）
    func resetFrame() {
        AppSettings.historyWindowSize = nil
        AppSettings.historyWindowOffset = nil
        if isVisible {
            position()
        }
    }

    private func saveFrame() {
        guard !isPositioning, panel.isVisible, !isHiding, let screen = panel.screen?.visibleFrame else { return }
        let frame = panel.frame
        AppSettings.historyWindowSize = frame.size
        AppSettings.historyWindowOffset = WindowPlacement.offset(of: frame, in: screen)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
    }

    // ウインドウの外をクリックしたら閉じる
    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible && !isHiding {
            hide()
        }
    }

    // MARK: - キーボード操作

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.panel.isKeyWindow else { return false }
                return self.handleKey(event)
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// 処理したキーなら true（検索欄には渡さない）
    private func handleKey(_ event: NSEvent) -> Bool {
        // 日本語の変換中は、Enter（確定）・↑↓（候補の選択）・Esc（取り消し）などを日本語入力に渡す。
        // このモニタは日本語入力より先にキーを受け取るので、確かめないと確定の Enter で貼り付けてしまう
        if let client = panel.firstResponder as? NSTextInputClient, client.hasMarkedText() {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case 125: // ↓
            model.moveSelection(1)
            return true
        case 126: // ↑
            model.moveSelection(-1)
            return true
        case 116: // Page Up
            model.moveSelection(-8)
            return true
        case 121: // Page Down
            model.moveSelection(8)
            return true
        case 36, 76: // ⏎ / テンキーの Enter
            if flags.contains(.option) {
                model.activateSelection(.copyOnly)
            } else if flags.contains(.shift) {
                model.activateSelection(.plainText)
            } else {
                model.activateSelection(.paste)
            }
            return true
        case 53: // Esc: 検索語があれば消し、なければ閉じる
            if model.query.isEmpty {
                hide()
            } else {
                model.query = ""
            }
            return true
        case 51 where flags.contains(.command): // ⌘⌫
            model.deleteSelection()
            return true
        default:
            break
        }
        if flags.contains(.command), let characters = event.charactersIgnoringModifiers?.lowercased() {
            if let number = Int(characters), (1...9).contains(number) {
                model.activate(index: number - 1, action: .paste)
                return true
            }
            if characters == "i" {
                model.showsDetails.toggle()
                return true
            }
            if characters == "p" {
                model.togglePinSelection()
                return true
            }
            if characters == "w" {
                hide()
                return true
            }
        }
        return false
    }
}

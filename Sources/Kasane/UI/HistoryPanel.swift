import AppKit
import SwiftUI

/// 履歴ウインドウ。Spotlight や Raycast と同じく、Kasane 自身はアクティブにならないパネルにする。
/// 元のアプリが前面のままなので、閉じた直後に ⌘V を送れば元のアプリに貼り付けられる
final class HistoryPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
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

    // 枠なしのパネルは既定ではキーウインドウになれないので、検索欄に入力できるようにする
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 800, height: 500)

    private let panel: HistoryPanel
    private let model: HistoryModel
    private var keyMonitor: Any?
    private var isHiding = false

    init(model: HistoryModel) {
        self.model = model
        panel = HistoryPanel(contentRect: NSRect(origin: .zero, size: Self.size))
        super.init()
        let hosting = NSHostingView(rootView: HistoryView(model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hosting
        panel.delegate = self
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
        installKeyMonitor()
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
                completion?()
            }
        })
    }

    /// マウスカーソルのある画面の中央（少し上寄り）に置く
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: frame.midX - Self.size.width / 2,
            y: frame.midY - Self.size.height / 2 + frame.height * 0.06
        )
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: false)
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

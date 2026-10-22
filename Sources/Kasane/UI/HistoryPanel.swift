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
        minSize = HistoryPanelController.minSize(for: AppSettings.historyTextSize)
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
    /// 文字の大きさが標準のときの、初めの大きさと最小の大きさ
    nonisolated static let defaultSize = NSSize(width: 880, height: 560)
    nonisolated static let minSize = NSSize(width: 720, height: 420)

    /// 文字の大きさの段階に合わせた初めの大きさ（一覧とプレビューの部分だけを割合で大きくする）
    nonisolated static func defaultSize(for level: TextSizeLevel) -> NSSize {
        WindowPlacement.size(defaultSize, scaledTo: level)
    }

    nonisolated static func minSize(for level: TextSizeLevel) -> NSSize {
        WindowPlacement.size(minSize, scaledTo: level)
    }

    private var panel: HistoryPanel
    private let hosting: NSHostingView<HistoryView>
    private let model: HistoryModel
    private var keyMonitor: Any?
    private var isHiding = false
    /// 自分で位置を決めている間は、動かした・大きさを変えたとみなして保存しない
    private var isPositioning = false
    private var blurObserver: AnyCancellable?
    private var blurState = WindowBlurState()
    private var textSizeObserver: AnyCancellable?
    /// 今の文字の大きさ。変えたときに、前の段階からの割合でウインドウの大きさを変える
    private var textSize = AppSettings.historyTextSize
    private let inputSource = InputSourceSwitcher()
    /// 検索欄。開くときに英数に切り替える間だけフォーカスを外すので、戻す先として覚えておく
    private weak var searchField: NSResponder?
    /// 検索欄のフォーカスを外していて、まだ戻していない
    private var focusDetached = false

    init(model: HistoryModel) {
        self.model = model
        panel = HistoryPanel(contentRect: NSRect(origin: .zero, size: HistoryPanelController.defaultSize))
        hosting = NSHostingView(rootView: HistoryView(model: model, appearance: .shared))
        super.init()
        hosting.sizingOptions = [.minSize]
        // タイトルバーは隠しているので、その分の余白を空けない
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(origin: .zero, size: HistoryPanelController.defaultSize)
        panel.contentView = hosting
        panel.delegate = self
        blurObserver = AppearanceSettings.shared.$blurRadius.sink { [weak self] radius in
            self?.applyBlur(radius)
        }
        textSizeObserver = AppearanceSettings.shared.$historyTextSize.dropFirst().sink { [weak self] level in
            self?.changeTextSize(to: level)
        }
    }

    /// 文字の大きさを変えたら、一覧とプレビューが大きくなった分だけウインドウを広げる（小さくしたら狭める）。
    /// 左上は動かさず、画面からはみ出すときは画面に収める（2026-10-22 決定。デザインの font-size-levels-2026-10-22.md）
    private func changeTextSize(to level: TextSizeLevel) {
        let old = textSize
        guard level != old else { return }
        textSize = level
        let minSize = Self.minSize(for: level)
        panel.minSize = minSize
        // この通知は値が変わる前に来る。次の回で、SwiftUI に新しい大きさで描き直させ
        // （小さくするときに古い最小の大きさが残らないように）、それからウインドウの大きさを変える
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hosting.layoutSubtreeIfNeeded()
            self.resizeForTextSize(from: old, to: level, minSize: minSize)
        }
    }

    private func resizeForTextSize(from old: TextSizeLevel, to level: TextSizeLevel, minSize: NSSize) {
        if isVisible, let screen = panel.screen?.visibleFrame {
            let frame = WindowPlacement.frame(panel.frame, in: screen, changingTextSizeFrom: old, to: level, minSize: minSize)
            isPositioning = true
            panel.setFrame(frame, display: true)
            isPositioning = false
            // 位置は画面の中心からのずれで覚えているので、広げたあとの位置で覚え直す
            saveFrame()
        } else if AppSettings.historyWindowSize != nil, let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            // 閉じている間に変えたときは、覚えている位置と大きさを同じように変える
            let current = WindowPlacement.frame(
                in: screen,
                savedSize: AppSettings.historyWindowSize,
                savedOffset: AppSettings.historyWindowOffset,
                defaultSize: Self.defaultSize(for: old),
                minSize: Self.minSize(for: old)
            )
            let frame = WindowPlacement.frame(current, in: screen, changingTextSizeFrom: old, to: level, minSize: minSize)
            AppSettings.historyWindowSize = frame.size
            AppSettings.historyWindowOffset = WindowPlacement.offset(of: frame, in: screen)
        }
    }

    /// ぼかしの半径を付ける。なしから半径を付けるときは、角丸を保つためにウインドウを作り直す（`WindowBlurState`）
    private func applyBlur(_ radius: Int) {
        guard blurState.needsNewWindow(for: radius) else {
            blurState.apply(radius, to: panel)
            return
        }
        let old = panel
        let wasOpen = old.isVisible && !isHiding
        let wasKey = old.isKeyWindow
        // 検索欄に入力中なら、フォーカスはウインドウの持つフィールドエディタにあるので、検索欄そのものを覚える
        let focused = ((old.firstResponder as? NSTextView)?.delegate as? NSView) ?? (old.firstResponder as? NSView)
        // 古いウインドウが閉じたことを、外をクリックしたとき（windowDidResignKey）と取り違えないよう先に外す
        old.delegate = nil
        old.orderOut(nil)
        old.contentView = nil
        panel = HistoryPanel(contentRect: old.frame)
        panel.setFrame(old.frame, display: false)
        panel.contentView = hosting
        panel.delegate = self
        blurState = WindowBlurState()
        // 起動したときと同じく、出す前に半径を付ける
        blurState.apply(radius, to: panel)
        guard wasOpen else { return }
        if wasKey {
            panel.makeKeyAndOrderFront(nil)
            if let focused {
                _ = panel.makeFirstResponder(focused)
            }
        } else {
            panel.orderFront(nil)
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
        // 作業中のアプリが前面にいるうちに、英数に切り替える。
        // 検索欄にフォーカスがあるまま切り替えると、macOS がカーソルの横に入力言語の表示を出す。
        // その表示の描画を待つ間（約 0.5 秒）、ウインドウがアクティブな見た目にならない（2026-10-17、Mac で計測）。
        // そこで検索欄のフォーカスを外してから切り替え、英数に変わってからフォーカスを戻す
        detachSearchField()
        let switching = inputSource.switchToASCII { [weak self] _ in
            self?.reattachSearchField()
        }
        if !switching {
            reattachSearchField()
        }
        panel.makeKeyAndOrderFront(nil)
        applyBlur(AppearanceSettings.shared.blurRadius)
        installKeyMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// 検索欄からフォーカスを外す。`reattachSearchField()` で戻す
    private func detachSearchField() {
        // 検索欄に入力中（フィールドエディタがフォーカスを持っている）のときだけ外す。戻す先がわからなければ触らない
        guard !focusDetached, let field = (panel.firstResponder as? NSTextView)?.delegate as? NSResponder else { return }
        searchField = field
        _ = panel.makeFirstResponder(nil)
        focusDetached = true
    }

    /// 外していたフォーカスを検索欄に戻す
    private func reattachSearchField() {
        guard focusDetached else { return }
        focusDetached = false
        _ = panel.makeFirstResponder(searchField)
    }

    /// フェードアウトして閉じる。閉じ終わってから `completion` を呼ぶ
    func hide(completion: (() -> Void)? = nil) {
        guard panel.isVisible, !isHiding else {
            completion?()
            return
        }
        isHiding = true
        removeKeyMonitor()
        // 検索欄にフォーカスがあるままフェードすると、2 回に 1 回ほど、隠す処理（orderOut）が
        // 約 0.5 秒止まり、薄れかけたウインドウが残って見える（2026-10-17、Mac で計測）。
        // フォーカスを外してからフェードすると起きなかったので、外してから閉じる（隠したあとで戻す）
        detachSearchField()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // フェード中に開き直していたら（show() が isHiding を戻している）、隠さない
                guard self.isHiding else { return }
                self.panel.orderOut(nil)
                self.isHiding = false
                // 次に開いたときのために、検索欄にフォーカスを戻しておく
                self.reattachSearchField()
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
            defaultSize: Self.defaultSize(for: textSize),
            minSize: Self.minSize(for: textSize)
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
        // 英数に変わる前にキーが押されたら、先に検索欄へフォーカスを戻して、打った文字を検索欄に届ける
        reattachSearchField()
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
            // ⌥⏎ や ⌃⏎ では何もしない。前のコピーのキー（⌥⏎）を押したときに、貼り付けてしまわないようにする
            guard flags.isDisjoint(with: [.option, .control]) else { return true }
            if flags.contains(.command) {
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
            // ⌘+ / ⌘− で一覧とプレビューの文字の大きさを一段変える。端では何もしない（音も鳴らさない）
            if flags.isDisjoint(with: [.option, .control]), let step = Self.textSizeStep(characters) {
                let appearance = AppearanceSettings.shared
                if let next = step > 0 ? appearance.historyTextSize.larger : appearance.historyTextSize.smaller {
                    appearance.historyTextSize = next
                }
                return true
            }
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
            // ⌘D でも消せる。⌘⌫ はキーボードによって押しにくいため（2026-10-18、Kazuya さんの要望）
            if characters == "d", flags.isDisjoint(with: [.shift, .option, .control]) {
                model.deleteSelection()
                return true
            }
            if characters == "w" {
                hide()
                return true
            }
            if let action = Self.editAction(characters, flags: flags) {
                if action == #selector(NSText.paste(_:)), pasteAsOneLine() {
                    return true
                }
                return NSApp.sendAction(action, to: nil, from: nil)
            }
        }
        return false
    }

    /// 検索欄に、改行やタブを空白に置き換えて 1 行で貼り付ける。
    /// 検索欄は 1 行なので、改行を含む文字をそのまま貼ると表示が崩れる（2026-10-18、Mac で確認）。
    /// 空白は検索の区切り（AND）になるので、行ごとの語がそれぞれ検索語になる。貼り付けられなければ false
    private func pasteAsOneLine() -> Bool {
        guard let editor = panel.firstResponder as? NSTextView, editor.isEditable,
              let text = NSPasteboard.general.string(forType: .string)
        else { return false }
        // insertText はキーで打った文字と同じ扱いで、そのままだと直前に打った文字とまとめて取り消される。
        // ⌘Z で貼った分だけが消えるよう、前後で区切る（2026-10-21 決定。要件書 §3.3）
        editor.breakUndoCoalescing()
        editor.insertText(TextNormalizer.singleLine(text), replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        return true
    }

    /// ⌘ と一緒に押したキーが、文字の大きさを一段大きくする（1）か小さくする（-1）か。
    /// US 配列の ⌘+ は ⇧ と = のキーなので、⌘= と ⌘⇧=（+）のどちらでも大きくする。
    /// JIS 配列の + は ⇧ と ; のキーなので、⌘; と ⌘⇧;（+）でも大きくする
    private static func textSizeStep(_ characters: String) -> Int? {
        switch characters {
        case "+", "=", ";": return 1
        case "-": return -1
        default: return nil
        }
    }

    /// ⌘V・⌘C・⌘X・⌘A・⌘Z（⇧⌘Z）を検索欄の編集の操作に置き換える。
    /// Kasane はメニューバーにメニューを出さないので「編集」メニューがなく、
    /// ふつうのアプリのようにはこれらのキーが検索欄に届かない
    static func editAction(_ characters: String, flags: NSEvent.ModifierFlags) -> Selector? {
        guard flags.isDisjoint(with: [.option, .control]) else { return nil }
        let shift = flags.contains(.shift)
        switch characters {
        case "v" where !shift: return #selector(NSText.paste(_:))
        case "c" where !shift: return #selector(NSText.copy(_:))
        case "x" where !shift: return #selector(NSText.cut(_:))
        case "a" where !shift: return #selector(NSText.selectAll(_:))
        case "z": return shift ? Selector(("redo:")) : Selector(("undo:"))
        default: return nil
        }
    }
}

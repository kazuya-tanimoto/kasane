import AppKit
import KasaneCore
import KasaneStore
import XCTest
@testable import Kasane

/// 調べ用（PR には入れない）。履歴ウインドウを閉じ方ごとに閉じて開き直し、一覧のスクロール位置を CI の Mac で測る
@MainActor
final class ScrollProbeTests: XCTestCase {
    func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func allScrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let s = view as? NSScrollView { result.append(s) }
        for sub in view.subviews { result += allScrollViews(in: sub) }
        return result
    }

    func describe(_ panel: NSWindow, _ model: HistoryModel, _ label: String) {
        let views = allScrollViews(in: panel.contentView!)
        let parts = views.map { sv -> String in
            let doc = sv.documentView?.frame.height ?? -1
            return "y=\(Int(sv.contentView.bounds.origin.y)) doc=\(Int(doc)) flipped=\(sv.contentView.isFlipped)"
        }
        let index = model.visible.firstIndex { $0.id == model.selectedID } ?? -1
        print("PROBE \(label) visible=\(panel.isVisible) key=\(panel.isKeyWindow) selectedIndex=\(index) scrolls=[\(parts.joined(separator: "; "))]")
    }

    func listScrollView(_ panel: NSWindow) -> NSScrollView? {
        allScrollViews(in: panel.contentView!).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
    }

    func scrollDown(_ panel: NSWindow) {
        guard let sv = listScrollView(panel) else { print("PROBE no scroll view"); return }
        // ホイールで下へ（ピクセル単位、何回かに分ける）
        for _ in 0..<8 {
            if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -100, wheel2: 0, wheel3: 0),
               let ev = NSEvent(cgEvent: cg) {
                sv.scrollWheel(with: ev)
            }
            wait(0.05)
        }
        wait(0.3)
    }

    func key(_ panel: NSWindow, code: UInt16, chars: String, flags: NSEvent.ModifierFlags = []) {
        guard let ev = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
        ) else { return }
        NSApp.sendEvent(ev)
    }

    func testScrollAfterReopen() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let store = try HistoryStore(directory: nil)
        for i in 0..<80 {
            let text = "probe item \(i)"
            let data = Data(text.utf8)
            _ = try store.save(Capture(
                kind: .text, title: text, text: text, primaryData: data,
                representations: [.init(itemIndex: 0, type: "public.utf8-plain-text", data: data)]
            ), limit: 1000)
        }
        let model = HistoryModel(store: store, sortOrder: .recent)
        model.load()
        wait(1.5)
        print("PROBE loaded=\(model.isLoaded) count=\(model.visible.count)")
        let controller = HistoryPanelController(model: model)
        var settingsOpened = 0
        controller.onOpenSettings = { settingsOpened += 1 }

        let toggle: (NSWindow) -> Void = { _ in controller.toggle() }
        let esc: (NSWindow) -> Void = { [unowned self] p in self.key(p, code: 53, chars: "\u{1b}") }
        let cmdComma: (NSWindow) -> Void = { [unowned self] p in self.key(p, code: 43, chars: ",", flags: .command) }
        // (名前, 閉じ方, スクロールのあとで ↓ で選択を動かすか)
        let paths: [(String, (NSWindow) -> Void, Bool)] = [
            ("toggle-wheel", toggle, false),
            ("esc-wheel", esc, false),
            ("cmdComma-wheel", cmdComma, false),
            ("toggle-moved", toggle, true),
            ("esc-moved", esc, true),
            ("cmdComma-moved", cmdComma, true),
        ]
        for (name, close, moves) in paths {
            controller.show()
            wait(0.8)
            guard let panel = NSApp.windows.first(where: { $0 is HistoryPanel && $0.isVisible }) else {
                print("PROBE \(name) panel not visible"); continue
            }
            describe(panel, model, "\(name) opened")
            if moves {
                for _ in 0..<3 { key(panel, code: 125, chars: "\u{F701}") ; wait(0.1) }
            }
            scrollDown(panel)
            describe(panel, model, "\(name) scrolled")
            close(panel)
            wait(0.6)
            describe(panel, model, "\(name) closed")
            controller.show()
            wait(0.8)
            describe(panel, model, "\(name) reopened")
            controller.hide()
            wait(0.6)
        }
        print("PROBE settingsOpened=\(settingsOpened)")
    }
}

#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI
import XCTest

/// 一時的な調べ: 設定画面の部品が .font(14) で 14pt になるかを CI の Mac で出す（PR には入れない）
final class ControlFontProbeTests: XCTestCase {
    func testPrintControlFonts() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            for size in [NSControl.ControlSize.mini, .small, .regular, .large, .extraLarge] {
                print("PROBE systemFontSize(for: \(size.rawValue)) = \(NSFont.systemFontSize(for: size))")
            }
            let sizes: [(String, ControlSize?)] = [("none", nil), ("large", .large), ("extraLarge", .extraLarge)]
            for (name, controlSize) in sizes {
                let host = NSHostingView(rootView: ProbeView(controlSize: controlSize))
                host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                print("PROBE --- controlSize \(name)")
                dump(host, depth: 0)
            }
        }
    }

    @MainActor
    private func dump(_ view: NSView, depth: Int) {
        var line = String(repeating: "  ", count: depth) + String(describing: type(of: view)) + " frame=\(view.frame.size)"
        if let control = view as? NSControl {
            line += " font=\(control.font?.pointSize ?? -1) controlSize=\(control.controlSize.rawValue)"
            if let popup = view as? NSPopUpButton { line += " popup=\(popup.titleOfSelectedItem ?? "")" }
            if let seg = view as? NSSegmentedControl { line += " segments=\(seg.segmentCount)" }
            if let button = view as? NSButton { line += " title=\(button.title)" }
            if let field = view as? NSTextField { line += " text=\(field.stringValue)" }
        }
        print("PROBE " + line)
        for sub in view.subviews { dump(sub, depth: depth + 1) }
    }
}

private struct ProbeView: View {
    var controlSize: ControlSize?
    @State private var segment = 0
    @State private var menu = 1
    @State private var number = 70.0
    @State private var on = true

    var body: some View {
        let content = VStack(alignment: .leading) {
            Picker("seg", selection: $segment) {
                Text("標準").tag(0)
                Text("大").tag(1)
                Text("特大").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Picker("menu", selection: $menu) {
                Text("1,000 件").tag(1)
                Text("5,000 件").tag(2)
            }
            .labelsHidden().fixedSize()
            Button("標準に戻す") {}
            Button("GitHub を開く") {}.buttonStyle(.link)
            TextField("n", value: $number, format: .number).textFieldStyle(.roundedBorder).frame(width: 60)
            Toggle("t", isOn: $on).toggleStyle(.switch).labelsHidden()
            Text("文字 14")
        }
        .font(.system(size: 14))
        if let controlSize {
            return AnyView(content.controlSize(controlSize))
        }
        return AnyView(content)
    }
}
#endif

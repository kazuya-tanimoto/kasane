#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest

// 一時的な計測（PR には入れない）。帯の幅（HistoryView.swift の ActionBar と同じ文字・余白）
private struct B: View {
    let copy: String
    var body: some View {
        HStack(spacing: 4) {
            l("ペースト ⏎", bold: true)
            l("書式なし ⇧⏎")
            l(copy)
            Label("⌘P", systemImage: "pin").labelStyle(.titleAndIcon).modifier(P())
            Label("⌘D", systemImage: "trash").labelStyle(.titleAndIcon).modifier(P())
            Label("⌘I", systemImage: "info.circle").labelStyle(.titleAndIcon).modifier(P())
        }
        .padding(4)
        .glassEffect(.regular, in: Capsule())
    }
    func l(_ s: String, bold: Bool = false) -> some View {
        Text(s).font(.system(size: 12, weight: bold ? .semibold : .regular)).padding(.horizontal, 10).padding(.vertical, 5)
    }
}
private struct P: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 5)
    }
}

final class GlassProbeTests: XCTestCase {
    @MainActor
    func testBarWidth() {
        for c in ["コピー ⌘⏎", "キューに追加 ⌘⏎"] {
            let h = NSHostingView(rootView: B(copy: c))
            print("PROBE bar copy=\(c) size=\(h.fittingSize)")
        }
    }
}
#endif

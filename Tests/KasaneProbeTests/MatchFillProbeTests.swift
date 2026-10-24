import AppKit
import SwiftUI
import XCTest
@testable import Kasane
@testable import KasaneCore
@testable import KasaneStore

/// 一時的な計測（PR には入れない）。実物の行を窓に描いて、一致した文字の後ろの塗りと、選んだ行の四角の色を読む
@MainActor
final class MatchFillProbeTests: XCTestCase {
    func render(accent: AccentColor, dark: Bool, matches: [Range<Int>], selected: Bool) -> NSBitmapImageRep {
        let item = ClipItem(id: 1, kind: .text, title: "git push --tags", text: "git push --tags", romaji: nil, contentHash: "x",
                            sourceBundleID: nil, sourceAppName: "App", thumbnail: nil, pixelWidth: nil, pixelHeight: nil,
                            byteSize: 10, createdAt: Date(), copiedAt: Date(), copyCount: 1, pasteCount: 0, lastPastedAt: nil,
                            isPinned: false, pinnedAt: nil)
        let row = ItemRow(item: ClipSummary(item), matches: matches, isSelected: selected, shortcut: nil)
            .environment(\.kasaneAccent, accent)
            .frame(width: 360)
            .background(dark ? Color(white: 0.16) : Color(white: 0.96))
        let host = NSHostingView(rootView: row)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: host.fittingSize.height)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.display()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    func count(_ rep: NSBitmapImageRep, near hex: UInt32, xRange: Range<Int>? = nil) -> Int {
        let target = SRGBColor(hex: hex)
        var n = 0
        for y in 0..<rep.pixelsHigh {
            for x in (xRange ?? 0..<rep.pixelsWide) where x < rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(Double(c.redComponent) - target.red) < 0.03 && abs(Double(c.greenComponent) - target.green) < 0.03
                    && abs(Double(c.blueComponent) - target.blue) < 0.03 { n += 1 }
            }
        }
        return n
    }

    func testProbe() throws {
        // g, t, p, s of "git push --tags"
        let matches = [0..<1, 2..<3, 4..<5, 6..<7]
        let cases: [(AccentColor, Bool, UInt32, UInt32)] = [
            // (色, ダーク, 塗りの色, 選んだ行の四角の色)
            (.matcha, false, 0x647324, 0x6B7B26), (.seiji, false, 0x2C7868, 0x2F7F6F), (.mono, false, 0x1D1D1F, 0x1D1D1F),
            (.ai, true, 0x79B5DB, 0x79B5DB), (.enji, true, 0xDCA0A4, 0xDCA0A4), (.edoMurasaki, true, 0xB8A7C9, 0xB8A7C9),
            (.rikyuNezumi, true, 0xABB0A1, 0xABB0A1), (.mono, true, 0xF2F2F5, 0xF2F2F5),
        ]
        for (accent, dark, fill, square) in cases {
            let with = render(accent: accent, dark: dark, matches: matches, selected: true)
            let without = render(accent: accent, dark: dark, matches: [], selected: true)
            let other = render(accent: accent, dark: dark, matches: matches, selected: false)
            let scale = with.pixelsWide / 360
            let titleX = (64 * scale)..<with.pixelsWide
            let iconX = 0..<(64 * scale)
            print("PROBE \(accent.rawValue) \(dark ? "dark" : "light") scale=\(scale) height with=\(with.pixelsHigh) without=\(without.pixelsHigh)"
                  + " fillPx(selected)=\(count(with, near: fill, xRange: titleX)) fillPx(noMatch)=\(count(without, near: fill, xRange: titleX))"
                  + " fillPx(other)=\(count(other, near: fill, xRange: titleX)) squarePx=\(count(with, near: square, xRange: iconX))")
            XCTAssertEqual(with.pixelsHigh, without.pixelsHigh, "行の高さが変わらない")
            XCTAssertGreaterThan(count(with, near: fill, xRange: titleX), 40 * scale * scale, "塗りがある")
            XCTAssertGreaterThan(count(other, near: fill, xRange: titleX), 40 * scale * scale, "ほかの行にも塗りがある")
            XCTAssertGreaterThan(count(with, near: square, xRange: iconX), 300 * scale * scale, "四角の色")
        }
        // 見た目を目で確かめる用に、藍ダークとモノクロのライトの PNG を base64 でログに出す
        for (accent, dark) in [(AccentColor.ai, true), (.mono, false), (.mono, true)] {
            let a = render(accent: accent, dark: dark, matches: matches, selected: true)
            let b = render(accent: accent, dark: dark, matches: matches, selected: false)
            for (name, rep) in [("sel", a), ("oth", b)] {
                let png = rep.representation(using: .png, properties: [:])!
                print("PNGB64 \(accent.rawValue)-\(dark ? "dark" : "light")-\(name) \(png.base64EncodedString())")
            }
        }
    }
}

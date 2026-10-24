import XCTest
@testable import KasaneCore

/// 一致した文字の後ろの塗りの色（requirements.md 外観の節: 色みと彩度を保ち、明るさだけでいちばん条件の悪い地に 4.5 以上）
final class ContrastFitTests: XCTestCase {
    /// モック（Match.dc.html の ksFitL）と同じ値になる（PRレビューが Python で写して確認した値）
    func testMatchTextValues() {
        let expected: [AccentTone: (light: UInt32, dark: UInt32)] = [
            .matcha: (0x647324, 0xB4BC5C),
            .seiji: (0x2C7868, 0x7EBEAB),
            .ai: (0x165E83, 0x79B5DB),
            .edoMurasaki: (0x745399, 0xB8A7C9),
            .enji: (0xA8323A, 0xDCA0A4),
            .rikyuNezumi: (0x61675A, 0xABB0A1),
            .mono: (0x1D1D1F, 0xF2F2F5),
        ]
        for tone in AccentTone.allCases {
            let light = ContrastFit.matchFill(tone.light, dark: false, increasedContrast: false)
            let dark = ContrastFit.matchFill(tone.dark, dark: true, increasedContrast: false)
            XCTAssertEqual(String(light.hex, radix: 16), String(expected[tone]!.light, radix: 16), "\(tone) ライト")
            XCTAssertEqual(String(dark.hex, radix: 16), String(expected[tone]!.dark, radix: 16), "\(tone) ダーク")
        }
        // システムが青（Mac の初期値）のとき
        XCTAssertEqual(ContrastFit.matchFill(SRGBColor(hex: 0x007AFF), dark: false, increasedContrast: false).hex, 0x0069DB)
        XCTAssertEqual(ContrastFit.matchFill(SRGBColor(hex: 0x0A84FF), dark: true, increasedContrast: false).hex, 0x66B2FF)
    }

    func testEveryToneReadsOnTheWorstBackground() {
        for tone in AccentTone.allCases {
            for increased in [false, true] {
                let target = increased ? 7.0 : 4.5
                let light = ContrastFit.matchFill(tone.light, dark: false, increasedContrast: increased)
                let dark = ContrastFit.matchFill(tone.dark, dark: true, increasedContrast: increased)
                XCTAssertGreaterThanOrEqual(ContrastFit.contrast(light, ContrastFit.lightBackground), target, "\(tone) ライト")
                XCTAssertGreaterThanOrEqual(ContrastFit.contrast(dark, ContrastFit.darkBackground), target, "\(tone) ダーク")
            }
        }
    }

    /// システムの色は利用者が変えられる（黄色なども）ので、色みと彩度と明るさを広く変えた色のすべてで届く
    func testAnySystemAccentReaches() {
        for hueStep in 0..<24 {
            for saturation in [0.0, 0.3, 0.7, 1.0] {
                for lightness in [0.2, 0.5, 0.8] {
                    let color = SRGBColor(hue: Double(hueStep) / 24, saturation: saturation, lightness: lightness)
                    for dark in [false, true] {
                        for increased in [false, true] {
                            let fitted = ContrastFit.matchFill(color, dark: dark, increasedContrast: increased)
                            let background = dark ? ContrastFit.darkBackground : ContrastFit.lightBackground
                            XCTAssertGreaterThanOrEqual(ContrastFit.contrast(fitted, background), increased ? 7.0 : 4.5)
                        }
                    }
                }
            }
        }
    }

    /// 白や黒を混ぜず、色みと彩度は元のまま。返した色は「元の色みと彩度で、明るさだけを変えた色」を 8 ビットにしたもの
    /// （丸めたあとの色で色みを比べると、明るさが端に近い色でずれが大きいため、丸める前の明るさで比べる）
    func testHueAndSaturationAreKept() throws {
        for tone in AccentTone.allCases {
            for (color, dark) in [(tone.light, false), (tone.dark, true)] {
                let (h, s, _) = color.hsl
                let background = dark ? ContrastFit.darkBackground : ContrastFit.lightBackground
                let fitted = ContrastFit.matchFill(color, dark: dark, increasedContrast: false)
                let lightness = try XCTUnwrap(ContrastFit.fittedLightness(color, background: background, target: ContrastFit.matchTarget))
                XCTAssertEqual(SRGBColor(hue: h, saturation: s, lightness: lightness).hex, fitted.hex, "\(tone)")
            }
        }
    }

    /// 一致した文字の後ろの塗りの目安（design/match-highlight-2026-10-24.md §5）。8 色（システムは Mac の初期の青）× ライト・ダーク
    func testMatchFillTargets() {
        let lightRows = [SRGBColor(hex: 0xFFFFFF), ContrastFit.lightBackground] // 選んだ行・ほかの行
        let darkRows = [ContrastFit.darkBackground, SRGBColor(hex: 0x2A2C30)] // 選んだ行・ほかの行（ガラスは仮の色）
        var colors = AccentTone.allCases.map { ("\($0)", $0.light, $0.dark) }
        colors.append(("システム", SRGBColor(hex: 0x007AFF), SRGBColor(hex: 0x0A84FF)))
        for (name, light, dark) in colors {
            for increased in [false, true] {
                let textTarget = increased ? 7.0 : 4.5
                let lightFill = ContrastFit.matchFill(light, dark: false, increasedContrast: increased)
                let darkFill = ContrastFit.matchFill(dark, dark: true, increasedContrast: increased)
                // 塗りと行の地: 3.0 以上（WCAG 1.4.11）
                for row in lightRows {
                    XCTAssertGreaterThanOrEqual(ContrastFit.contrast(lightFill, row), 3.0, "\(name) ライト 塗りと地")
                }
                for row in darkRows {
                    XCTAssertGreaterThanOrEqual(ContrastFit.contrast(darkFill, row), 3.0, "\(name) ダーク 塗りと地")
                }
                // 塗りの上の文字と塗り: 4.5 以上（コントラストを上げるがオンなら 7.0 以上）
                XCTAssertGreaterThanOrEqual(ContrastFit.contrast(ContrastFit.onMatchFillLight, lightFill), textTarget, "\(name) ライト 塗りの上の文字")
                XCTAssertGreaterThanOrEqual(ContrastFit.contrast(ContrastFit.onMatchFillDark, darkFill), textTarget, "\(name) ダーク 塗りの上の文字")
                // ダークの選んだ行の四角（塗りと同じ色）と行の地: 3.0 以上、上の記号（#1D1D1F）: 4.5 以上
                XCTAssertGreaterThanOrEqual(ContrastFit.contrast(darkFill, ContrastFit.darkBackground), 3.0, "\(name) ダーク 四角と地")
                XCTAssertGreaterThanOrEqual(ContrastFit.contrast(ContrastFit.onMatchFillDark, darkFill), 4.5, "\(name) ダーク 四角の記号")
            }
        }
    }

    /// システムの色は利用者が変えられるので、色を広く変えても塗りの上の文字が読める
    func testTextOnFillReadsForAnySystemAccent() {
        for hueStep in 0..<24 {
            for saturation in [0.0, 0.3, 0.7, 1.0] {
                for lightness in [0.2, 0.5, 0.8] {
                    let color = SRGBColor(hue: Double(hueStep) / 24, saturation: saturation, lightness: lightness)
                    for increased in [false, true] {
                        let target = increased ? 7.0 : 4.5
                        let lightFill = ContrastFit.matchFill(color, dark: false, increasedContrast: increased)
                        let darkFill = ContrastFit.matchFill(color, dark: true, increasedContrast: increased)
                        XCTAssertGreaterThanOrEqual(ContrastFit.contrast(ContrastFit.onMatchFillLight, lightFill), target)
                        XCTAssertGreaterThanOrEqual(ContrastFit.contrast(ContrastFit.onMatchFillDark, darkFill), target)
                    }
                }
            }
        }
    }

    func testKindGrayReads() {
        XCTAssertGreaterThanOrEqual(ContrastFit.contrast(ContrastFit.kindGrayLight, ContrastFit.lightBackground), 4.5)
        XCTAssertGreaterThanOrEqual(ContrastFit.contrast(ContrastFit.kindGrayDark, ContrastFit.darkBackground), 4.5)
    }

    func testHexRoundTrip() {
        XCTAssertEqual(SRGBColor(hex: 0x165E83).hex, 0x165E83)
        let (h, s, l) = SRGBColor(hex: 0x165E83).hsl
        XCTAssertEqual(SRGBColor(hue: h, saturation: s, lightness: l).hex, 0x165E83)
    }
}

final class FileKindsTests: XCTestCase {
    #if canImport(UniformTypeIdentifiers)
    func testImageFiles() {
        XCTAssertTrue(FileKinds.areAllImages(paths: ["/Users/me/a.png"]))
        XCTAssertTrue(FileKinds.areAllImages(paths: ["/tmp/B.JPG", "/tmp/c.heic", "/tmp/d.svg"]))
    }
    #endif

    func testNotImages() {
        XCTAssertFalse(FileKinds.areAllImages(paths: []))
        XCTAssertFalse(FileKinds.areAllImages(paths: ["/tmp/report.pdf"]))
        XCTAssertFalse(FileKinds.areAllImages(paths: ["/tmp/folder"]))
        XCTAssertFalse(FileKinds.areAllImages(paths: ["/tmp/a.png", "/tmp/notes.txt"]), "画像とそれ以外が混ざっていたら画像に入れない")
    }
}

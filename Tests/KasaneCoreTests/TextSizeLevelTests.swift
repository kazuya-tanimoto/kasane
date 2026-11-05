import XCTest
import KasaneCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class TextSizeLevelTests: XCTestCase {
    func testFontSizesGrowByOneAndAHalfPoints() {
        XCTAssertEqual(TextSizeLevel.allCases.map { $0.font(13) }, [13, 14.5, 16])
        XCTAssertEqual(TextSizeLevel.allCases.map { $0.font(11) }, [11, 12.5, 14])
        XCTAssertEqual(TextSizeLevel.allCases.map(\.displayName), ["標準", "大", "特大"])
    }

    func testOtherSizesUseTheTitleRatio() {
        XCTAssertEqual(TextSizeLevel.standard.scaled(350), 350)
        XCTAssertEqual(TextSizeLevel.large.scaled(350), 350 * 14.5 / 13, accuracy: 0.001)
        XCTAssertEqual(TextSizeLevel.extraLarge.scaled(44), 44 * 16 / 13, accuracy: 0.001)
    }

    func testStepsStopAtTheEnds() {
        XCTAssertEqual(TextSizeLevel.standard.larger, .large)
        XCTAssertNil(TextSizeLevel.extraLarge.larger)
        XCTAssertEqual(TextSizeLevel.extraLarge.smaller, .large)
        XCTAssertNil(TextSizeLevel.standard.smaller)
    }

    func testOldHUDFontSizesMoveToTheNearestLevel() {
        let mapped = [11.0, 12, 14, 16, 18, 20].map { TextSizeLevel.nearest(toHUDFontSize: CGFloat($0)) }
        XCTAssertEqual(mapped, [.standard, .standard, .large, .extraLarge, .extraLarge, .extraLarge])
    }

    func testDefaultAndMinimumWindowSizes() {
        // デザインの font-size-levels-2026-10-22.md の目安は 大: 約 977×604、最小 約 799×448（変わらない高さを約 175 とした値。
        // 「正確な値は実装で、実際の高さから計算」）。下のボタンが浮く帯になり、変わらない高さは 127 なので、高さは 610 と 454
        let large = WindowPlacement.size(CGSize(width: 880, height: 560), scaledTo: .large)
        XCTAssertEqual(large.width, 977, accuracy: 1)
        XCTAssertEqual(large.height, 610, accuracy: 1)
        let minimum = WindowPlacement.size(CGSize(width: 720, height: 420), scaledTo: .large)
        XCTAssertEqual(minimum.width, 799, accuracy: 1)
        XCTAssertEqual(minimum.height, 454, accuracy: 1)
    }

    func testChangingTextSizeKeepsTopLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 100, y: 300, width: 880, height: 560)
        let larger = WindowPlacement.frame(frame, in: screen, changingTextSizeFrom: .standard, to: .large, minSize: CGSize(width: 799, height: 454))
        XCTAssertEqual(larger.minX, frame.minX)
        XCTAssertEqual(larger.maxY, frame.maxY)
        XCTAssertGreaterThan(larger.width, frame.width)
        // 標準に戻すと元の大きさに戻る
        let back = WindowPlacement.frame(larger, in: screen, changingTextSizeFrom: .large, to: .standard, minSize: CGSize(width: 720, height: 420))
        XCTAssertEqual(back.width, frame.width, accuracy: 0.5)
        XCTAssertEqual(back.height, frame.height, accuracy: 0.5)
        XCTAssertEqual(back.maxY, frame.maxY, accuracy: 0.5)
    }

    func testChangingTextSizeStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let frame = CGRect(x: 100, y: 50, width: 880, height: 600)
        let larger = WindowPlacement.frame(frame, in: screen, changingTextSizeFrom: .standard, to: .extraLarge, minSize: CGSize(width: 878, height: 488))
        XCTAssertLessThanOrEqual(larger.width, screen.width)
        XCTAssertLessThanOrEqual(larger.height, screen.height)
        XCTAssertTrue(screen.contains(larger))
    }
}

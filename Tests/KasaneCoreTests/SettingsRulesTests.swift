import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import KasaneCore

/// 設定画面の PR で足した決めごと（design/settings-implementation-2026-10-22.md §6.2）
final class SettingsRulesTests: XCTestCase {
    // MARK: - 小さいウインドウの位置

    func testLegacyCornersBecomeLeftOrRight() {
        XCTAssertEqual(HUDSide(legacyPosition: "topLeft"), .left)
        XCTAssertEqual(HUDSide(legacyPosition: "bottomLeft"), .left, "下の角だった人は、同じ側の上に移る")
        XCTAssertEqual(HUDSide(legacyPosition: "topRight"), .right)
        XCTAssertEqual(HUDSide(legacyPosition: "bottomRight"), .right)
        XCTAssertEqual(HUDSide(legacyPosition: nil), .right, "設定がなければ標準の右")
        XCTAssertEqual(HUDSide(legacyPosition: "middle"), .right)
    }

    // MARK: - ペーストの扱い

    func testPasteSendsCommandVAndCountsWithoutMoving() {
        let expected = PasteOutcome(sendsCommandV: true, movesToTop: false, countsPaste: true)
        XCTAssertEqual(PasteAction.paste.outcome(openedOverKasane: false), expected)
        XCTAssertEqual(PasteAction.plainText.outcome(openedOverKasane: false), expected)
    }

    func testCopyOnlyMovesToTopWithoutCounting() {
        let expected = PasteOutcome(sendsCommandV: false, movesToTop: true, countsPaste: false)
        XCTAssertEqual(PasteAction.copyOnly.outcome(openedOverKasane: false), expected)
        XCTAssertEqual(PasteAction.copyOnly.outcome(openedOverKasane: true), expected)
    }

    func testPasteOverKasaneOnlyCopies() {
        let expected = PasteOutcome(sendsCommandV: false, movesToTop: false, countsPaste: false)
        XCTAssertEqual(PasteAction.paste.outcome(openedOverKasane: true), expected)
        XCTAssertEqual(PasteAction.plainText.outcome(openedOverKasane: true), expected)
    }

    // MARK: - 履歴ウインドウの「標準に戻す」

    private let screen = CGRect(x: 0, y: 0, width: 1_440, height: 875)
    private let defaultSize = CGSize(width: 880, height: 560)
    private let minSize = CGSize(width: 720, height: 420)

    private func isStandard(size: CGSize?, offset: CGPoint?) -> Bool {
        WindowPlacement.isStandard(savedSize: size, savedOffset: offset, defaultSize: defaultSize, minSize: minSize, in: screen)
    }

    func testNothingSavedIsStandard() {
        XCTAssertTrue(isStandard(size: nil, offset: nil))
    }

    func testSavedValuesEqualToTheStandardAreStandard() {
        // ⌘+ のあと ⌘− で戻した人は、標準と同じ値を覚えている
        let standardOffset = CGPoint(x: 0, y: screen.height * 0.06)
        XCTAssertTrue(isStandard(size: defaultSize, offset: standardOffset))
        XCTAssertTrue(isStandard(size: CGSize(width: 880.5, height: 559.5), offset: CGPoint(x: 0.5, y: standardOffset.y)))
        XCTAssertTrue(isStandard(size: defaultSize, offset: nil))
    }

    func testMovedOrResizedIsNotStandard() {
        let standardOffset = CGPoint(x: 0, y: screen.height * 0.06)
        XCTAssertFalse(isStandard(size: defaultSize, offset: CGPoint(x: -200, y: standardOffset.y)))
        XCTAssertFalse(isStandard(size: CGSize(width: 980, height: 560), offset: standardOffset))
        XCTAssertFalse(isStandard(size: CGSize(width: 980, height: 560), offset: nil))
    }

    func testDifferencesHiddenByTheScreenEdgeDoNotCount() {
        // 画面より大きい大きさを覚えていても、画面に収めると標準と違う。収めた枠どうしで比べる
        let small = CGRect(x: 0, y: 0, width: 800, height: 500)
        XCTAssertTrue(WindowPlacement.isStandard(
            savedSize: CGSize(width: 2_000, height: 1_000), savedOffset: nil,
            defaultSize: defaultSize, minSize: minSize, in: small
        ), "どちらも画面いっぱいに収まるので、押しても変わらない")
    }
}

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import KasaneCore

final class HistoryFrameLayoutTests: XCTestCase {
    private let window = CGRect(x: 100, y: 200, width: 880, height: 560)

    func testBodyLeavesTheResizeMargin() {
        let body = HistoryFrameLayout.body(in: window)
        XCTAssertEqual(body, CGRect(x: 103, y: 203, width: 874, height: 554))
    }

    /// 影のウインドウの中の本体は、画面の上で履歴ウインドウの本体と重なる
    func testShadowCasterMatchesTheBodyOnScreen() {
        let shadow = HistoryFrameLayout.shadowFrame(window: window)
        let caster = HistoryFrameLayout.shadowCaster(inShadowOfSize: shadow.size)
        let onScreen = caster.offsetBy(dx: shadow.minX, dy: shadow.minY)
        XCTAssertEqual(onScreen, HistoryFrameLayout.body(in: window))
    }

    /// 影は下へ 30 ずれ、ぼかしの 3 標準偏差（120）まで描ける広さがある
    func testShadowFrameHoldsTheWholeShadow() {
        let shadow = HistoryFrameLayout.shadowFrame(window: window)
        XCTAssertLessThanOrEqual(shadow.minY, window.minY - 30 - 120)
        XCTAssertLessThanOrEqual(shadow.minX, window.minX - 120)
    }

    func testMockValues() {
        XCTAssertEqual(HistoryFrameLayout.cornerRadius, 20)
        XCTAssertEqual(HistoryFrameLayout.borderWidth, 1)
        XCTAssertEqual(HistoryFrameLayout.borderWhiteOpacity(dark: true), 0.12)
        XCTAssertEqual(HistoryFrameLayout.borderWhiteOpacity(dark: false), 0.70)
        XCTAssertEqual(HistoryFrameLayout.shadowOpacity, 0.35)
    }
}

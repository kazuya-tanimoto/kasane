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

    private let size = CGSize(width: 880, height: 560)

    /// 見える縁の外 3pt（ウインドウの端）から内 3pt までが、端をつかむ所
    func testEdgeGripReachesThreeInsideTheVisibleEdge() {
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 879.5, y: 280), in: size), .right)
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 880 - 3 - 2.5, y: 280), in: size), .right)
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 880 - 3 - 3.5, y: 280), in: size), [])
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 0.5, y: 280), in: size), .left)
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 440, y: 559.5), in: size), .top)
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 440, y: 0.5), in: size), .bottom)
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 440, y: 280), in: size), [])
    }

    func testCornersResizeBothWays() {
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 2, y: 2), in: size), [.left, .bottom])
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 878, y: 558), in: size), [.right, .top])
        // 角から 15pt 離れた端の上も、まだ角
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 878, y: 15), in: size), [.right, .bottom])
    }

    func testResizeKeepsTheOppositeEdge() {
        let frame = CGRect(x: 100, y: 200, width: 880, height: 560)
        let min = CGSize(width: 720, height: 420)
        XCTAssertEqual(HistoryFrameLayout.resized(frame, edges: .right, dx: 30, dy: 0, minSize: min), CGRect(x: 100, y: 200, width: 910, height: 560))
        XCTAssertEqual(HistoryFrameLayout.resized(frame, edges: [.left, .top], dx: -20, dy: 10, minSize: min), CGRect(x: 80, y: 200, width: 900, height: 570))
        // 最小より小さくしようとしたら、最小で止め、右と上の端は動かさない
        let shrunk = HistoryFrameLayout.resized(frame, edges: [.left, .bottom], dx: 500, dy: 500, minSize: min)
        XCTAssertEqual(shrunk, CGRect(x: 260, y: 340, width: 720, height: 420))
    }
}
